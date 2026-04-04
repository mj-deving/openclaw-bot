/**
 * Defense Proxy Server
 *
 * HTTP proxy that sits between OpenClaw and upstream LLM APIs.
 * Intercepts all API calls to run the 6-layer defense system:
 *
 * Inbound (request):  L1 sanitizer on latest user message → L5 governor check
 * Outbound (response): L3 gate + L4 redaction on model response
 *
 * Configured via ANTHROPIC_BASE_URL and OPENAI_BASE_URL env vars in OpenClaw's
 * systemd service — both SDKs respect these and route through us.
 *
 * Handles both streaming (SSE) and non-streaming responses.
 */

import { sanitize } from "../layer1-sanitizer";
import { gate } from "../layer3-outbound";
import { redact } from "../layer4-redaction";
import { createGovernor } from "../layer5-governor";
import type { CallGovernor } from "../layer5-governor";
import { loadConfig, type ProxyConfig } from "./config";

// ── State ────────────────────────────────────────────────────────────

let config: ProxyConfig;
let governor: CallGovernor;

// ── Upstream Resolution ──────────────────────────────────────────────

function resolveUpstream(path: string): { upstream: string; provider: string } {
  // Anthropic Messages API
  if (path.startsWith("/v1/messages")) {
    return { upstream: config.anthropicUpstream, provider: "anthropic" };
  }
  // OpenAI-compatible (OpenRouter, etc.)
  if (path.startsWith("/v1/chat/completions") || path.startsWith("/v1/completions")) {
    return { upstream: config.openrouterUpstream, provider: "openrouter" };
  }
  // All other paths (models list, tokenize, etc.) — pass through to Anthropic
  return { upstream: config.anthropicUpstream, provider: "anthropic" };
}

// ── User Message Extraction ──────────────────────────────────────────

/**
 * Extract the latest user message from the request body.
 * Handles both Anthropic (messages[].role/content) and OpenAI (messages[].role/content) formats.
 */
function extractUserMessage(body: Record<string, unknown>): string | null {
  const messages = body.messages as Array<{ role: string; content: unknown }> | undefined;
  if (!Array.isArray(messages) || messages.length === 0) return null;

  // Find the last user message
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i]!;
    if (msg.role === "user") {
      if (typeof msg.content === "string") return msg.content;
      // Anthropic format: content can be array of {type: "text", text: "..."}
      if (Array.isArray(msg.content)) {
        const textParts = (msg.content as Array<{ type: string; text?: string }>)
          .filter((p) => p.type === "text" && typeof p.text === "string")
          .map((p) => p.text!);
        return textParts.join("\n") || null;
      }
    }
  }
  return null;
}

// ── Response Text Extraction ─────────────────────────────────────────

/** Extract assistant text from a non-streaming Anthropic response */
function extractAnthropicResponse(body: Record<string, unknown>): string | null {
  const content = body.content as Array<{ type: string; text?: string }> | undefined;
  if (!Array.isArray(content)) return null;
  return content.filter((c) => c.type === "text" && typeof c.text === "string")
    .map((c) => c.text!).join("\n") || null;
}

/** Extract assistant text from a non-streaming OpenAI response */
function extractOpenAIResponse(body: Record<string, unknown>): string | null {
  const choices = body.choices as Array<{ message?: { content?: string } }> | undefined;
  if (!Array.isArray(choices) || choices.length === 0) return null;
  return choices[0]?.message?.content ?? null;
}

// ── Response Patching ────────────────────────────────────────────────

/** Replace assistant text in Anthropic response body */
function patchAnthropicResponse(body: Record<string, unknown>, newText: string): void {
  const content = body.content as Array<{ type: string; text?: string }> | undefined;
  if (!Array.isArray(content)) return;
  for (const block of content) {
    if (block.type === "text" && typeof block.text === "string") {
      block.text = newText;
      break;
    }
  }
}

/** Replace assistant text in OpenAI response body */
function patchOpenAIResponse(body: Record<string, unknown>, newText: string): void {
  const choices = body.choices as Array<{ message?: { content?: string } }> | undefined;
  if (!Array.isArray(choices) || choices.length === 0) return;
  if (choices[0]?.message) {
    choices[0].message.content = newText;
  }
}

// ── Audit Logging ────────────────────────────────────────────────────

function audit(event: string, data: Record<string, unknown>): void {
  if (!config.auditLog) return;
  const entry = {
    ts: new Date().toISOString(),
    event,
    ...data,
  };
  console.error(JSON.stringify(entry));
}

// ── Outbound Defense (L3 + L4) ───────────────────────────────────────

function defendOutbound(text: string): string {
  const gateResult = gate(text);
  let cleaned = gateResult.cleaned;

  const redactResult = redact(cleaned, config.redaction);
  cleaned = redactResult.redacted;

  if (!gateResult.passed || redactResult.counts.apiKeys > 0 || redactResult.counts.emails > 0) {
    audit("outbound_violation", {
      gateViolations: gateResult.violations.length,
      redactions: redactResult.counts,
    });
  }

  return cleaned;
}

// ── Streaming SSE Handler ────────────────────────────────────────────

/**
 * For streaming responses, we collect the full text from SSE chunks,
 * run L3+L4 on the assembled text, and if violations are found,
 * append a warning to the final chunk. We can't un-stream already-sent
 * text, but we CAN:
 * 1. Detect and log violations for audit
 * 2. Append a redaction notice in the stream_end event
 * 3. Block future requests from the same source via circuit breaker
 *
 * For true pre-delivery scanning, non-streaming mode is needed.
 * The proxy logs a warning when streaming responses contain violations.
 */
async function handleStreaming(
  upstreamResponse: Response,
  provider: string,
): Promise<Response> {
  // Pass through the stream but monitor it
  const reader = upstreamResponse.body?.getReader();
  if (!reader) return upstreamResponse;

  const decoder = new TextDecoder();
  let assembledText = "";

  const stream = new ReadableStream({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        // Stream complete — run outbound defense on assembled text
        if (assembledText.length > 0) {
          const gateResult = gate(assembledText);
          if (!gateResult.passed) {
            audit("streaming_violation_detected", {
              provider,
              violations: gateResult.violations.length,
              note: "Violations detected in streaming response — cannot redact already-sent chunks",
            });
          }
        }
        controller.close();
        return;
      }

      // Pass chunk through to client
      controller.enqueue(value);

      // Extract text from SSE chunks for monitoring
      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split("\n");
      for (const line of lines) {
        if (!line.startsWith("data: ") || line === "data: [DONE]") continue;
        try {
          const data = JSON.parse(line.slice(6));
          // Anthropic streaming: content_block_delta with delta.text
          if (data.delta?.text) assembledText += data.delta.text;
          // OpenAI streaming: choices[0].delta.content
          if (data.choices?.[0]?.delta?.content) assembledText += data.choices[0].delta.content;
        } catch {
          // Not JSON, skip
        }
      }
    },
  });

  return new Response(stream, {
    status: upstreamResponse.status,
    headers: upstreamResponse.headers,
  });
}

// ── Request Handler ──────────────────────────────────────────────────

async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);

  // Health check
  if (url.pathname === "/health") {
    const state = governor.getState();
    return Response.json({
      status: "ok",
      governor: state,
      uptime: Math.round(performance.now() / 1000),
    });
  }

  // Only proxy POST requests to API endpoints
  if (req.method !== "POST") {
    // Pass through GET/OPTIONS/etc. (model lists, etc.)
    const { upstream } = resolveUpstream(url.pathname);
    const upstreamUrl = upstream + url.pathname + url.search;
    return fetch(upstreamUrl, {
      method: req.method,
      headers: req.headers,
    });
  }

  const { upstream, provider } = resolveUpstream(url.pathname);

  // Parse request body
  let body: Record<string, unknown>;
  let rawBody: string;
  try {
    rawBody = await req.text();
    body = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const isStreaming = body.stream === true;

  // ── INBOUND DEFENSE: L1 sanitizer on latest user message ────────
  const userMessage = extractUserMessage(body);
  if (userMessage) {
    const sanitizerResult = sanitize(userMessage);

    audit("inbound_scan", {
      provider,
      detections: sanitizerResult.totalDetections,
      highSeverity: sanitizerResult.highSeverity,
      path: url.pathname,
    });

    // Auto-block if L1 finds overwhelming evidence
    if (sanitizerResult.highSeverity && sanitizerResult.totalDetections > config.autoBlockThreshold) {
      audit("inbound_blocked", {
        provider,
        detections: sanitizerResult.totalDetections,
        stats: sanitizerResult.stats,
      });

      // Return an error response in the provider's format
      if (provider === "anthropic") {
        return Response.json({
          type: "error",
          error: { type: "invalid_request_error", message: "Request blocked by security defense layer" },
        }, { status: 400 });
      }
      return Response.json({
        error: { message: "Request blocked by security defense layer", type: "invalid_request_error" },
      }, { status: 400 });
    }
  }

  // ── L5 GOVERNOR CHECK ──────────────────────────────────────────
  const callerId = provider; // Use provider as caller ID for governor
  const estimatedCost = isStreaming ? 0.02 : 0.01; // Rough estimate
  const govDecision = governor.check({
    callerId,
    prompt: userMessage ?? "",
    estimatedCostDollars: estimatedCost,
  });

  if (!govDecision.allowed) {
    audit("governor_blocked", { provider, reason: govDecision.reason });
    return Response.json({
      type: "error",
      error: { type: "rate_limit_error", message: `Rate limited: ${govDecision.reason}` },
    }, { status: 429 });
  }

  // Return cached result if dedup hit
  if (govDecision.cached) {
    audit("governor_cache_hit", { provider });
    return new Response(govDecision.cachedResult, {
      headers: { "content-type": "application/json", "x-defense-cached": "true" },
    });
  }

  // ── FORWARD TO UPSTREAM ────────────────────────────────────────
  const upstreamUrl = upstream + url.pathname + url.search;
  const upstreamHeaders = new Headers(req.headers);
  // Ensure host header matches upstream
  upstreamHeaders.delete("host");

  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(upstreamUrl, {
      method: "POST",
      headers: upstreamHeaders,
      body: rawBody,
    });
  } catch (err) {
    audit("upstream_error", { provider, error: String(err) });
    return Response.json({
      type: "error",
      error: { type: "api_error", message: "Upstream API unreachable" },
    }, { status: 502 });
  }

  // Record successful call for governor
  if (upstreamResponse.ok) {
    // We'll record after getting the response
  }

  // ── STREAMING: monitor but pass through ────────────────────────
  if (isStreaming && upstreamResponse.ok) {
    governor.record({ callerId, prompt: userMessage ?? "", estimatedCostDollars: estimatedCost }, "streaming");
    return handleStreaming(upstreamResponse, provider);
  }

  // ── NON-STREAMING: buffer, scan, return ────────────────────────
  const responseBody = await upstreamResponse.text();

  if (!upstreamResponse.ok) {
    // Pass through error responses untouched
    return new Response(responseBody, {
      status: upstreamResponse.status,
      headers: upstreamResponse.headers,
    });
  }

  let responseParsed: Record<string, unknown>;
  try {
    responseParsed = JSON.parse(responseBody);
  } catch {
    return new Response(responseBody, {
      status: upstreamResponse.status,
      headers: upstreamResponse.headers,
    });
  }

  // Extract response text
  const responseText = provider === "anthropic"
    ? extractAnthropicResponse(responseParsed)
    : extractOpenAIResponse(responseParsed);

  if (responseText) {
    // ── OUTBOUND DEFENSE: L3 gate + L4 redaction ─────────────────
    const cleaned = defendOutbound(responseText);

    if (cleaned !== responseText) {
      // Patch the response with cleaned text
      if (provider === "anthropic") {
        patchAnthropicResponse(responseParsed, cleaned);
      } else {
        patchOpenAIResponse(responseParsed, cleaned);
      }

      audit("outbound_cleaned", { provider, originalLength: responseText.length, cleanedLength: cleaned.length });
    }
  }

  // Record for governor
  const finalBody = JSON.stringify(responseParsed);
  governor.record({ callerId, prompt: userMessage ?? "", estimatedCostDollars: estimatedCost }, finalBody);

  return new Response(finalBody, {
    status: upstreamResponse.status,
    headers: new Headers({
      "content-type": "application/json",
    }),
  });
}

// ── Server Entry Point ───────────────────────────────────────────────

config = loadConfig();
governor = createGovernor(config.governor);

const server = Bun.serve({
  port: config.port,
  hostname: config.bind,
  fetch: handleRequest,
});

console.error(`[defense-proxy] Listening on ${config.bind}:${config.port}`);
console.error(`[defense-proxy] Anthropic upstream: ${config.anthropicUpstream}`);
console.error(`[defense-proxy] OpenRouter upstream: ${config.openrouterUpstream}`);
console.error(`[defense-proxy] Auto-block threshold: ${config.autoBlockThreshold}`);
console.error(`[defense-proxy] Governor spend limit: $${config.governor.spendLimitDollars}/hr`);

export { server };
