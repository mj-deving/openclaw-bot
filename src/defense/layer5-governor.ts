/**
 * Layer 5: Call Governor
 *
 * Wraps every LLM call in the system with four mechanisms:
 * 1. Spend limit — tracks dollar cost in a rolling window
 * 2. Volume limit — total calls with per-caller overrides
 * 3. Lifetime counter — kills runaway loops (per-process)
 * 4. Duplicate detection — caches recent prompts, returns cached results
 *
 * All state is in-memory. Restart resets all counters (acceptable for bot).
 */

import type { GovernorConfig, GovernorCallRequest, GovernorDecision } from "./types";

// ── Internal State ───────────────────────────────────────────────────

interface CallRecord {
  timestamp: number;
  costDollars: number;
  callerId: string;
}

interface CacheEntry {
  result: string;
  timestamp: number;
}

export class CallGovernor {
  private config: GovernorConfig;
  private calls: CallRecord[] = [];
  private lifetimeCount = 0;
  private dedupCache = new Map<string, CacheEntry>();
  private callerCounts = new Map<string, number>();
  /** Circuit breaker: tracks consecutive blocks per caller (H-6) */
  private blockedCounts = new Map<string, { count: number; windowStart: number }>();

  constructor(config: GovernorConfig) {
    this.config = config;
  }

  /**
   * Check whether a call should be allowed before making it.
   * Returns a decision with the reason if blocked, or cached result if dedup hit.
   */
  check(request: GovernorCallRequest): GovernorDecision {
    const now = this.now();

    // 0. Circuit breaker — auto-reject repeat offenders (H-6)
    const cbThreshold = this.config.circuitBreakerThreshold ?? Infinity;
    const cbWindowMs = this.config.circuitBreakerWindowMs ?? 60_000;
    const blocked = this.blockedCounts.get(request.callerId);
    if (blocked) {
      if (now - blocked.windowStart > cbWindowMs) {
        // Window expired — reset
        this.blockedCounts.delete(request.callerId);
      } else if (blocked.count >= cbThreshold) {
        return this.recordBlock(request.callerId, now, "circuit_breaker");
      }
    }

    // Sweep expired entries from dedup cache (amortized cleanup)
    this.sweepCache(now);

    // 1. Lifetime limit — absolute cap per process
    if (this.lifetimeCount >= this.config.lifetimeLimit) {
      return this.recordBlock(request.callerId, now, "lifetime_limit");
    }

    // 2. Volume limit — rolling window call count
    this.pruneOldCalls(now);
    const callerLimit = this.config.callerOverrides.get(request.callerId)
      ?? this.config.volumeLimit;
    const callerCount = this.callerCounts.get(request.callerId) ?? 0;
    if (callerCount >= callerLimit) {
      return this.recordBlock(request.callerId, now, "volume_limit");
    }

    // Also check global volume
    if (this.calls.length >= this.config.volumeLimit) {
      return this.recordBlock(request.callerId, now, "volume_limit");
    }

    // 3. Spend limit — rolling window dollar cost
    const windowSpend = this.calls.reduce((sum, c) => sum + c.costDollars, 0);
    if (windowSpend + request.estimatedCostDollars > this.config.spendLimitDollars) {
      return this.recordBlock(request.callerId, now, "spend_limit");
    }

    // 4. Duplicate detection — check content hash (C-3: scoped by callerId)
    const hash = this.hashPrompt(request.callerId, request.prompt);
    const cached = this.dedupCache.get(hash);
    if (cached && now - cached.timestamp < this.config.dedupTtlMs) {
      return { allowed: true, cached: true, cachedResult: cached.result };
    }

    return { allowed: true, cached: false };
  }

  /**
   * Record a completed call. Must be called after each successful LLM call
   * to keep state accurate.
   */
  record(request: GovernorCallRequest, result: string): void {
    const now = this.now();

    // Record the call
    this.calls.push({
      timestamp: now,
      costDollars: request.estimatedCostDollars,
      callerId: request.callerId,
    });

    // Update caller count
    const current = this.callerCounts.get(request.callerId) ?? 0;
    this.callerCounts.set(request.callerId, current + 1);

    // Increment lifetime counter
    this.lifetimeCount++;

    // Cache for dedup (C-3: scoped by callerId)
    const hash = this.hashPrompt(request.callerId, request.prompt);
    this.dedupCache.set(hash, { result, timestamp: now });
  }

  /**
   * Get current governor state for monitoring.
   */
  getState(): {
    lifetimeCount: number;
    windowCalls: number;
    windowSpend: number;
    cacheSize: number;
  } {
    this.pruneOldCalls(this.now());
    return {
      lifetimeCount: this.lifetimeCount,
      windowCalls: this.calls.length,
      windowSpend: this.calls.reduce((sum, c) => sum + c.costDollars, 0),
      cacheSize: this.dedupCache.size,
    };
  }

  // ── Internal Helpers ─────────────────────────────────────────────

  /** Monotonic clock — immune to NTP jumps and wall-clock manipulation (M-6) */
  private now(): number {
    return performance.now();
  }

  /** Record a block and increment circuit breaker counter for this caller (H-6) */
  private recordBlock(
    callerId: string,
    now: number,
    reason: "spend_limit" | "volume_limit" | "lifetime_limit" | "circuit_breaker"
  ): GovernorDecision & { allowed: false } {
    const existing = this.blockedCounts.get(callerId);
    if (existing && now - existing.windowStart <= (this.config.circuitBreakerWindowMs ?? 60_000)) {
      existing.count++;
    } else {
      this.blockedCounts.set(callerId, { count: 1, windowStart: now });
    }
    return { allowed: false, reason };
  }

  private pruneOldCalls(now: number): void {
    const cutoff = now - this.config.spendWindowMs;
    // Remove calls outside the rolling window
    this.calls = this.calls.filter((c) => c.timestamp >= cutoff);

    // Rebuild caller counts from surviving calls
    this.callerCounts.clear();
    for (const call of this.calls) {
      const current = this.callerCounts.get(call.callerId) ?? 0;
      this.callerCounts.set(call.callerId, current + 1);
    }
  }

  private sweepCache(now: number): void {
    // Safe to delete during forEach in JS/Bun — single-pass cleanup
    this.dedupCache.forEach((entry, hash) => {
      if (now - entry.timestamp >= this.config.dedupTtlMs) {
        this.dedupCache.delete(hash);
      }
    });
  }

  /** (C-3) Hash includes callerId so same prompt from different callers is distinct */
  private hashPrompt(callerId: string, prompt: string): string {
    const { createHash } = require("node:crypto");
    return createHash("sha256").update(callerId + ":" + prompt).digest("hex");
  }
}

/**
 * Create a new call governor with the given configuration.
 */
export function createGovernor(config: GovernorConfig): CallGovernor {
  return new CallGovernor(config);
}
