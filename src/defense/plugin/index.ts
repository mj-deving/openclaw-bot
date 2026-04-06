/**
 * Defense Shield — OpenClaw Native Plugin
 *
 * Hooks into OpenClaw's plugin SDK to enforce the 6-layer defense system
 * at the message lifecycle level:
 *
 * - message_received   → L1 sanitizer on inbound (blocks high-severity)
 * - message_sending     → L3 gate + L4 redaction PRE-DELIVERY enforcement
 * - before_tool_call    → L6 access control on file/URL tool calls
 * - llm_input           → L5 governor tracking (spend/volume monitoring)
 * - llm_output          → L3+L4 audit on raw LLM response text
 *
 * This replaces the defense proxy with native enforcement — no extra
 * process, no latency, no single point of failure.
 */

import { createGovernor } from "../layer5-governor";
import type { RedactionConfig, AccessControlConfig } from "../types";
import type { PluginApi } from "./types";
import {
  createInboundHandler,
  createOutboundEnforcementHandler,
  createToolCallGuard,
  createLlmInputTracker,
  createLlmOutputAuditor,
} from "./hooks";

// Plugin configuration defaults
const DEFAULT_AUTO_BLOCK_THRESHOLD = 5;
const DEFAULT_WORK_DOMAINS: string[] = [];
const DEFAULT_ALLOWED_DIRECTORIES = ["/home/openclaw/.openclaw/workspace"];

// ── Plugin Registration ──────────────────────────────────────────────

const defensePlugin = {
  register(api: PluginApi) {
    const pluginConfig = api.pluginConfig ?? {};
    const enabled = pluginConfig.enabled !== false;

    if (!enabled) {
      api.logger.info("[defense-shield] Plugin disabled via config");
      return;
    }

    // ── Config extraction ──────────────────────────────────────
    const autoBlockThreshold =
      (pluginConfig.autoBlockThreshold as number) ?? DEFAULT_AUTO_BLOCK_THRESHOLD;
    const workDomains =
      (pluginConfig.workDomains as string[]) ?? DEFAULT_WORK_DOMAINS;
    const allowedDirectories =
      (pluginConfig.allowedDirectories as string[]) ?? DEFAULT_ALLOWED_DIRECTORIES;
    const cancelOnCritical =
      (pluginConfig.cancelOnCritical as boolean) ?? false;
    const logVerdicts = pluginConfig.logVerdicts !== false;

    const redactionConfig: RedactionConfig = { workDomains };
    const accessConfig: AccessControlConfig = { allowedDirectories };

    // Initialize L5 governor (stateful, lives for the process lifetime)
    const governor = createGovernor({
      spendLimitDollars: (pluginConfig.spendLimitDollars as number) ?? 50,
      spendWindowMs: (pluginConfig.spendWindowMs as number) ?? 3_600_000,
      volumeLimit: (pluginConfig.volumeLimit as number) ?? 500,
      callerOverrides: new Map(),
      lifetimeLimit: (pluginConfig.lifetimeLimit as number) ?? 10_000,
      dedupTtlMs: (pluginConfig.dedupTtlMs as number) ?? 300_000,
      circuitBreakerThreshold: (pluginConfig.circuitBreakerThreshold as number) ?? 10,
      circuitBreakerWindowMs: 60_000,
    });

    // ── Hook 1: message_received → L1 inbound defense ────────
    api.registerHook(
      "message_received",
      createInboundHandler({ autoBlockThreshold, logVerdicts, logger: api.logger }),
      {
        name: "defense-shield-inbound",
        description:
          "L1 sanitizer on inbound messages — blocks prompt injection, " +
          "encoding attacks, wallet drains",
      }
    );

    // ── Hook 2: message_sending → L3+L4 pre-delivery enforcement
    api.registerHook(
      "message_sending",
      createOutboundEnforcementHandler({
        redactionConfig, logVerdicts, cancelOnCritical, logger: api.logger,
      }),
      {
        name: "defense-shield-outbound",
        description:
          "L3 gate + L4 redaction on outbound — modifies content to " +
          "redact secrets, PII, injection artifacts before delivery",
      }
    );

    // ── Hook 3: before_tool_call → L6 access control ────────
    api.registerHook(
      "before_tool_call",
      createToolCallGuard({ accessConfig, logVerdicts, logger: api.logger }),
      {
        name: "defense-shield-tool-guard",
        description:
          "L6 access control on tool calls — blocks file access to " +
          "sensitive paths and URL access to internal/private networks",
      }
    );

    // ── Hook 4: llm_input → L5 governor tracking ────────────
    api.registerHook(
      "llm_input",
      createLlmInputTracker({ governor, logVerdicts, logger: api.logger }),
      {
        name: "defense-shield-governor",
        description:
          "L5 governor on LLM calls — tracks spend, volume, dedup, " +
          "and circuit breaker state (informational, cannot block)",
      }
    );

    // ── Hook 5: llm_output → L3+L4 audit trail ──────────────
    api.registerHook(
      "llm_output",
      createLlmOutputAuditor({ redactionConfig, logVerdicts, logger: api.logger }),
      {
        name: "defense-shield-llm-audit",
        description:
          "L3+L4 audit on raw LLM responses — logs violations for " +
          "investigation even if message_sending catches them first",
      }
    );

    // ── Startup hook → initialization ────────────────────────
    api.registerHook(
      "gateway:startup",
      async () => {
        api.logger.info(
          `[defense-shield] Initialized | threshold=${autoBlockThreshold} | ` +
          `workDomains=${workDomains.length} | ` +
          `allowedDirs=${allowedDirectories.length} | ` +
          `cancelOnCritical=${cancelOnCritical} | ` +
          `logVerdicts=${logVerdicts}`
        );
      },
      {
        name: "defense-shield-startup",
        description: "Defense shield initialization on gateway startup",
      }
    );

    api.logger.info(
      "[defense-shield] Plugin registered — 5 hooks: " +
      "L1 inbound, L3+L4 outbound, L6 tool guard, L5 governor, L3+L4 audit"
    );
  },
};

export default defensePlugin;
