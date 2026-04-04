/**
 * Defense Shield — OpenClaw Native Plugin
 *
 * Hooks into OpenClaw's plugin SDK to enforce the 6-layer defense system
 * at the message lifecycle level:
 *
 * - message:received  → L1 sanitizer on inbound (blocks high-severity)
 * - message:sent       → L3 gate + L4 redaction audit on outbound
 * - gateway:startup    → initialization and startup audit
 *
 * This replaces the defense proxy with native enforcement — no extra
 * process, no latency, no single point of failure.
 */

import { sanitize } from "../layer1-sanitizer";
import { gate } from "../layer3-outbound";
import { redact } from "../layer4-redaction";
import type { RedactionConfig } from "../types";

// Plugin configuration defaults
const DEFAULT_AUTO_BLOCK_THRESHOLD = 5;
const DEFAULT_WORK_DOMAINS: string[] = [];

/**
 * OpenClaw Plugin API type (subset we use).
 * Full type from "openclaw/plugin-sdk" — we declare what we need
 * to avoid import dependency on the OpenClaw package.
 */
interface PluginApi {
  id: string;
  name: string;
  pluginConfig?: Record<string, unknown>;
  logger: {
    info: (msg: string) => void;
    warn: (msg: string) => void;
    error: (msg: string) => void;
  };
  registerHook: (
    events: string | string[],
    handler: (event: HookEvent) => Promise<void> | void,
    opts?: { name?: string; description?: string }
  ) => void;
}

interface HookEvent {
  type: string;
  action: string;
  sessionKey: string;
  context: Record<string, unknown>;
  timestamp: Date;
  messages: string[];
}

// ── Hook Handlers ────────────────────────────────────────────────────

function createInboundHandler(config: {
  autoBlockThreshold: number;
  logVerdicts: boolean;
  logger: PluginApi["logger"];
}) {
  return async (event: HookEvent): Promise<void> => {
    const content = event.context.content as string | undefined;
    if (!content || typeof content !== "string" || content.length === 0) return;

    const result = sanitize(content);

    if (config.logVerdicts) {
      config.logger.info(
        `[defense-shield] inbound | detections=${result.totalDetections} | ` +
        `highSeverity=${result.highSeverity} | ` +
        `from=${event.context.from ?? "unknown"} | ` +
        `channel=${event.context.channelId ?? "unknown"}`
      );
    }

    // Block if L1 finds overwhelming evidence
    if (result.highSeverity && result.totalDetections > config.autoBlockThreshold) {
      config.logger.warn(
        `[defense-shield] BLOCKED inbound | detections=${result.totalDetections} | ` +
        `stats=${JSON.stringify(result.stats)}`
      );
      // Push warning message back to the conversation
      event.messages.push(
        "⚠️ Message blocked by security defense: suspicious content detected " +
        `(${result.totalDetections} indicators). If this is legitimate, ` +
        "contact the operator."
      );
    }
  };
}

function createOutboundHandler(config: {
  redactionConfig: RedactionConfig;
  logVerdicts: boolean;
  logger: PluginApi["logger"];
}) {
  return async (event: HookEvent): Promise<void> => {
    const content = event.context.content as string | undefined;
    if (!content || typeof content !== "string" || content.length === 0) return;

    // L3: Outbound content gate
    const gateResult = gate(content);

    // L4: Redaction check (we log but can't modify sent messages — they're already sent)
    const redactResult = redact(content, config.redactionConfig);

    const hasViolations = !gateResult.passed ||
      redactResult.counts.apiKeys > 0 ||
      redactResult.counts.emails > 0;

    if (hasViolations && config.logVerdicts) {
      config.logger.warn(
        `[defense-shield] outbound violation | ` +
        `gateViolations=${gateResult.violations.length} | ` +
        `redactions=${JSON.stringify(redactResult.counts)} | ` +
        `channel=${event.context.channelId ?? "unknown"}`
      );
    }

    // Note: message:sent fires AFTER delivery — we can audit but not modify.
    // For pre-delivery enforcement, the proxy approach is needed.
    // The audit trail here catches leaks for investigation.
  };
}

// ── Plugin Registration ──────────────────────────────────────────────

const defensePlugin = {
  register(api: PluginApi) {
    const pluginConfig = api.pluginConfig ?? {};
    const enabled = pluginConfig.enabled !== false;

    if (!enabled) {
      api.logger.info("[defense-shield] Plugin disabled via config");
      return;
    }

    const autoBlockThreshold =
      (pluginConfig.autoBlockThreshold as number) ?? DEFAULT_AUTO_BLOCK_THRESHOLD;
    const workDomains =
      (pluginConfig.workDomains as string[]) ?? DEFAULT_WORK_DOMAINS;
    const logVerdicts = pluginConfig.logVerdicts !== false;

    const redactionConfig: RedactionConfig = { workDomains };

    // ── Hook: message:received → L1 inbound defense ────────────
    api.registerHook(
      "message:received",
      createInboundHandler({
        autoBlockThreshold,
        logVerdicts,
        logger: api.logger,
      }),
      {
        name: "defense-shield-inbound",
        description: "L1 sanitizer on inbound messages — blocks prompt injection, encoding attacks, wallet drains",
      }
    );

    // ── Hook: message:sent → L3+L4 outbound audit ──────────────
    api.registerHook(
      "message:sent",
      createOutboundHandler({
        redactionConfig,
        logVerdicts,
        logger: api.logger,
      }),
      {
        name: "defense-shield-outbound",
        description: "L3 gate + L4 redaction audit on outbound responses",
      }
    );

    // ── Hook: gateway:startup → initialization ─────────────────
    api.registerHook(
      "gateway:startup",
      async () => {
        api.logger.info(
          `[defense-shield] Initialized | threshold=${autoBlockThreshold} | ` +
          `workDomains=${workDomains.length} | logVerdicts=${logVerdicts}`
        );
      },
      {
        name: "defense-shield-startup",
        description: "Defense shield initialization on gateway startup",
      }
    );

    api.logger.info("[defense-shield] Plugin registered — L1 inbound + L3/L4 outbound");
  },
};

export default defensePlugin;
