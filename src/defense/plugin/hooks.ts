/**
 * Defense Shield Plugin — Hook Handler Factories
 *
 * Each exported function creates a hook handler bound to its configuration.
 * The plugin index.ts wires these into OpenClaw's hook system.
 *
 * Hook 1: message_received   → L1 sanitizer (inbound, void)
 * Hook 2: message_sending     → L3 gate + L4 redaction (outbound, modifying)
 * Hook 3: before_tool_call    → L6 access control (tool guard, modifying)
 * Hook 4: llm_input           → L5 governor tracking (void)
 * Hook 5: llm_output          → L3+L4 audit trail (void)
 */

import { sanitize } from "../layer1-sanitizer";
import { scan } from "../layer2-scanner";
import { gate } from "../layer3-outbound";
import { redact } from "../layer4-redaction";
import { checkPath, checkUrl } from "../layer6-access";
import type { CallGovernor } from "../layer5-governor";
import type { RedactionConfig, AccessControlConfig, ScannerConfig } from "../types";
import type { PluginLogger, HookEvent } from "./types";

/** Violation types that warrant message cancellation (not just redaction) */
const CRITICAL_VIOLATION_TYPES = new Set(["leaked_secret"]);

/** Tool names that perform file system operations */
const FILE_TOOLS = new Set([
  "bash", "exec", "read", "write", "edit", "read_file", "write_file",
  "create_file", "delete_file", "move_file", "copy_file", "list_files",
]);

/** Tool names that perform URL/network operations */
const URL_TOOLS = new Set([
  "fetch", "browser", "browse", "http", "curl", "web_search",
  "web_browse", "navigate", "open_url",
]);

// ── Hook 1: message_received (void) ──────────────────────────────────

/**
 * Channels considered trusted (paired DMs from the operator).
 * Messages from these channels skip L2 scanner (too expensive for trusted input).
 * All other channels (email, webhooks, web content, pipeline) get L2.
 */
const TRUSTED_CHANNELS = new Set(["telegram"]);

/**
 * L1 sanitizer on ALL inbound messages.
 * L2 LLM scanner on HIGH-RISK sources only (non-telegram channels).
 *
 * L2 fires when: channel is not trusted AND L1 found detections but
 * didn't auto-block (the ambiguous zone where deterministic checks
 * see something but not enough to be certain).
 */
export function createInboundHandler(config: {
  autoBlockThreshold: number;
  logVerdicts: boolean;
  logger: PluginLogger;
  scannerConfig?: ScannerConfig;
}) {
  return async (event: HookEvent): Promise<void> => {
    const content = (event.context?.content ?? event.content) as string | undefined;
    if (!content || typeof content !== "string" || content.length === 0) return;

    const channelId = (event.context?.channelId ?? event.channelId ?? "unknown") as string;
    const isTrustedChannel = TRUSTED_CHANNELS.has(channelId.toLowerCase());

    // ── L1: Always runs (deterministic, instant, free) ────────
    const result = sanitize(content);

    if (config.logVerdicts) {
      config.logger.info(
        `[defense-shield] inbound | detections=${result.totalDetections} | ` +
        `highSeverity=${result.highSeverity} | ` +
        `from=${event.context?.from ?? event.from ?? "unknown"} | ` +
        `channel=${channelId} | trusted=${isTrustedChannel}`
      );
    }

    // Auto-block: L1 found overwhelming evidence
    if (result.highSeverity && result.totalDetections > config.autoBlockThreshold) {
      config.logger.warn(
        `[defense-shield] BLOCKED inbound | detections=${result.totalDetections} | ` +
        `stats=${JSON.stringify(result.stats)}`
      );
      event.messages.push(
        "Message blocked by security defense: suspicious content detected " +
        `(${result.totalDetections} indicators). If this is legitimate, ` +
        "contact the operator."
      );
      return;
    }

    // ── L2: Fires only for high-risk (untrusted) sources ──────
    // Skip L2 for trusted channels (Telegram paired DMs from operator)
    // Skip L2 if L1 found nothing (no reason to spend on classification)
    if (
      !isTrustedChannel &&
      result.totalDetections > 0 &&
      config.scannerConfig
    ) {
      config.logger.info(
        `[defense-shield] L2 scanner triggered | channel=${channelId} | ` +
        `l1Detections=${result.totalDetections}`
      );

      try {
        const scanResult = await scan(result.cleaned, config.scannerConfig);

        config.logger.info(
          `[defense-shield] L2 verdict=${scanResult.verdict} | ` +
          `score=${scanResult.score} | ` +
          `categories=${scanResult.categories.join(",")}`
        );

        if (scanResult.verdict === "block") {
          event.messages.push(
            "Message blocked by L2 security scanner: " +
            `${scanResult.reasoning} (score: ${scanResult.score}/100)`
          );
        } else if (scanResult.verdict === "review") {
          event.messages.push(
            "Security notice: this message was flagged for review " +
            `(score: ${scanResult.score}/100). Processing with caution.`
          );
        }
      } catch (err) {
        config.logger.warn(
          `[defense-shield] L2 scanner error: ${String(err)} — ` +
          `falling back to L1-only verdict`
        );
        // L2 failure: fall through to L1-only verdict (already handled above)
      }
    }
  };
}

// ── Hook 2: message_sending (MODIFYING) ──────────────────────────────

/**
 * L3 outbound gate + L4 redaction BEFORE delivery.
 * Returns { content: cleanedText } to replace outbound message,
 * or { cancel: true } for critical violations (leaked secrets).
 */
export function createOutboundEnforcementHandler(config: {
  redactionConfig: RedactionConfig;
  logVerdicts: boolean;
  cancelOnCritical: boolean;
  logger: PluginLogger;
}) {
  return async (event: HookEvent): Promise<{ content?: string; cancel?: boolean }> => {
    const content = (event.context?.content ?? event.content) as string | undefined;
    if (!content || typeof content !== "string" || content.length === 0) return {};

    // L3: Outbound content gate
    const gateResult = gate(content);

    // L4: Redaction pipeline — chain from gate-cleaned text if violations found
    const redactResult = redact(
      gateResult.passed ? content : gateResult.cleaned,
      config.redactionConfig
    );

    const hasGateViolations = !gateResult.passed;
    const hasRedactions =
      redactResult.counts.apiKeys > 0 ||
      redactResult.counts.emails > 0 ||
      redactResult.counts.phones > 0 ||
      redactResult.counts.dollars > 0;

    const hasCriticalViolation = gateResult.violations.some(
      (v) => CRITICAL_VIOLATION_TYPES.has(v.type)
    );

    if ((hasGateViolations || hasRedactions) && config.logVerdicts) {
      config.logger.warn(
        `[defense-shield] outbound enforcement | ` +
        `gateViolations=${gateResult.violations.length} | ` +
        `redactions=${JSON.stringify(redactResult.counts)} | ` +
        `critical=${hasCriticalViolation} | ` +
        `channel=${event.context?.channelId ?? event.channelId ?? "unknown"}`
      );
    }

    // Critical violation + cancel mode: block the message entirely
    if (hasCriticalViolation && config.cancelOnCritical) {
      const criticalTypes = gateResult.violations
        .filter((v) => CRITICAL_VIOLATION_TYPES.has(v.type))
        .map((v) => v.type)
        .join(", ");
      config.logger.warn(
        `[defense-shield] CANCELLED outbound — critical violation (${criticalTypes})`
      );
      return { cancel: true };
    }

    // Return cleaned text if any modifications were needed
    if (hasGateViolations || hasRedactions) {
      return { content: redactResult.redacted };
    }

    return {};
  };
}

// ── Hook 3: before_tool_call (MODIFYING) ─────────────────────────────

/**
 * L6 access control on file and URL tool calls.
 * Returns { block: true, blockReason } to deny access to sensitive paths/URLs.
 */
export function createToolCallGuard(config: {
  accessConfig: AccessControlConfig;
  logVerdicts: boolean;
  logger: PluginLogger;
}) {
  return async (
    event: HookEvent
  ): Promise<{ block?: boolean; blockReason?: string; params?: unknown }> => {
    const toolName = (event.toolName ?? event.context?.toolName) as string | undefined;
    if (!toolName) return {};

    const params = (event.params ?? event.context?.params ?? {}) as Record<string, unknown>;
    const toolLower = toolName.toLowerCase();

    // File tool checks
    if (FILE_TOOLS.has(toolLower)) {
      const pathCandidates = extractPaths(params);
      for (const filePath of pathCandidates) {
        const result = checkPath(filePath, config.accessConfig);
        if (!result.allowed) {
          if (config.logVerdicts) {
            config.logger.warn(
              `[defense-shield] BLOCKED tool=${toolName} | ` +
              `path=${filePath} | reason=${result.reason}`
            );
          }
          return {
            block: true,
            blockReason: `Defense Shield: access denied — ${result.reason}`,
          };
        }
      }
    }

    // URL tool checks
    if (URL_TOOLS.has(toolLower)) {
      const urlCandidates = extractUrls(params);
      for (const url of urlCandidates) {
        const result = await checkUrl(url);
        if (!result.allowed) {
          if (config.logVerdicts) {
            config.logger.warn(
              `[defense-shield] BLOCKED tool=${toolName} | ` +
              `url=${url} | reason=${result.reason}`
            );
          }
          return {
            block: true,
            blockReason: `Defense Shield: access denied — ${result.reason}`,
          };
        }
      }
    }

    return {};
  };
}

// ── Hook 4: llm_input (void) ─────────────────────────────────────────

/**
 * L5 governor tracking on LLM calls. Logs warnings for rate/spend concerns.
 * Cannot block — informational only (void hook).
 */
export function createLlmInputTracker(config: {
  governor: CallGovernor;
  logVerdicts: boolean;
  logger: PluginLogger;
}) {
  return async (event: HookEvent): Promise<void> => {
    const prompt = (event.prompt ?? event.context?.prompt ?? "") as string;
    const model = (event.model ?? event.context?.model ?? "unknown") as string;
    const provider = (event.provider ?? event.context?.provider ?? "unknown") as string;

    // Rough cost estimate: $0.003 per 1K input tokens for Sonnet
    const estimatedTokens = Math.ceil(prompt.length / 4);
    const estimatedCost = (estimatedTokens / 1000) * 0.003;
    const callerId = `${provider}/${model}`;

    const decision = config.governor.check({
      callerId,
      prompt,
      estimatedCostDollars: estimatedCost,
    });

    if (decision.allowed) {
      if (decision.cached && config.logVerdicts) {
        config.logger.info(
          `[defense-shield] governor | CACHE_HIT | model=${model}`
        );
      }
      // Record for tracking (placeholder result — actual response not available yet)
      config.governor.record(
        { callerId, prompt, estimatedCostDollars: estimatedCost },
        "tracked"
      );
    } else {
      // Can't block (void hook) — log warning for operational awareness
      config.logger.warn(
        `[defense-shield] governor | WOULD_BLOCK | reason=${decision.reason} | ` +
        `model=${model} | state=${JSON.stringify(config.governor.getState())}`
      );
    }
  };
}

// ── Hook 5: llm_output (void) ────────────────────────────────────────

/**
 * L3 gate audit on raw LLM response text.
 * Catches things that message_sending might miss (tool-generated responses).
 */
export function createLlmOutputAuditor(config: {
  redactionConfig: RedactionConfig;
  logVerdicts: boolean;
  logger: PluginLogger;
}) {
  return async (event: HookEvent): Promise<void> => {
    const texts: string[] = [];
    if (event.assistantTexts && Array.isArray(event.assistantTexts)) {
      texts.push(...event.assistantTexts.filter((t): t is string => typeof t === "string"));
    }
    if (event.content && typeof event.content === "string") {
      texts.push(event.content);
    }
    if (event.context?.content && typeof event.context.content === "string") {
      texts.push(event.context.content as string);
    }

    if (texts.length === 0) return;

    const combined = texts.join("\n");
    const gateResult = gate(combined);
    const redactResult = redact(combined, config.redactionConfig);

    const hasViolations = !gateResult.passed ||
      redactResult.counts.apiKeys > 0 ||
      redactResult.counts.emails > 0;

    if (hasViolations && config.logVerdicts) {
      const model = (event.model ?? event.context?.model ?? "unknown") as string;
      config.logger.warn(
        `[defense-shield] llm_output audit | ` +
        `gateViolations=${gateResult.violations.length} | ` +
        `redactions=${JSON.stringify(redactResult.counts)} | ` +
        `model=${model} | ` +
        `tokens=${event.usage ? JSON.stringify(event.usage) : "n/a"}`
      );
    }
  };
}

// ── Utility Functions ─────────────────────────────────────────────────

/** Extract file paths from tool call params */
function extractPaths(params: Record<string, unknown>): string[] {
  const paths: string[] = [];
  const pathKeys = [
    "path", "file", "filePath", "file_path", "filename",
    "target", "source", "destination", "dir", "directory",
    "command",
  ];

  for (const key of pathKeys) {
    const val = params[key];
    if (typeof val === "string" && val.length > 0) {
      if (key === "command") {
        const cmdPaths = val.match(/(?:\/[\w./-]+)+/g);
        if (cmdPaths) paths.push(...cmdPaths);
      } else {
        paths.push(val);
      }
    }
  }

  return paths;
}

/** Extract URLs from tool call params */
function extractUrls(params: Record<string, unknown>): string[] {
  const urls: string[] = [];
  const urlKeys = ["url", "href", "uri", "link", "address", "endpoint"];

  for (const key of urlKeys) {
    const val = params[key];
    if (typeof val === "string" && val.startsWith("http")) {
      urls.push(val);
    }
  }

  return urls;
}
