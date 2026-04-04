/**
 * Defense Proxy Configuration
 *
 * Loaded from environment variables with sensible defaults.
 */

import type { GovernorConfig, RedactionConfig } from "../types";

export interface ProxyConfig {
  /** Port to listen on */
  port: number;
  /** Bind address */
  bind: string;
  /** Upstream Anthropic API base URL */
  anthropicUpstream: string;
  /** Upstream OpenRouter API base URL */
  openrouterUpstream: string;
  /** L1 auto-block threshold (highSeverity + detections > this = block) */
  autoBlockThreshold: number;
  /** L5 governor configuration */
  governor: GovernorConfig;
  /** L4 redaction configuration */
  redaction: RedactionConfig;
  /** Enable audit logging to stderr */
  auditLog: boolean;
}

export function loadConfig(): ProxyConfig {
  return {
    port: parseInt(process.env.DEFENSE_PROXY_PORT ?? "18800", 10),
    bind: process.env.DEFENSE_PROXY_BIND ?? "127.0.0.1",
    anthropicUpstream: process.env.DEFENSE_ANTHROPIC_UPSTREAM ?? "https://api.anthropic.com",
    openrouterUpstream: process.env.DEFENSE_OPENROUTER_UPSTREAM ?? "https://openrouter.ai/api",
    autoBlockThreshold: parseInt(process.env.DEFENSE_AUTO_BLOCK_THRESHOLD ?? "5", 10),
    governor: {
      spendLimitDollars: parseFloat(process.env.DEFENSE_SPEND_LIMIT ?? "50"),
      spendWindowMs: parseInt(process.env.DEFENSE_SPEND_WINDOW_MS ?? "3600000", 10), // 1 hour
      volumeLimit: parseInt(process.env.DEFENSE_VOLUME_LIMIT ?? "500", 10),
      callerOverrides: new Map(),
      lifetimeLimit: parseInt(process.env.DEFENSE_LIFETIME_LIMIT ?? "10000", 10),
      dedupTtlMs: parseInt(process.env.DEFENSE_DEDUP_TTL_MS ?? "300000", 10), // 5 min
      circuitBreakerThreshold: parseInt(process.env.DEFENSE_CIRCUIT_BREAKER ?? "10", 10),
      circuitBreakerWindowMs: 60_000,
    },
    redaction: {
      workDomains: (process.env.DEFENSE_WORK_DOMAINS ?? "").split(",").filter(Boolean),
    },
    auditLog: process.env.DEFENSE_AUDIT_LOG !== "false",
  };
}
