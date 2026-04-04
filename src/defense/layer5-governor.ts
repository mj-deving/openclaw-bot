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

  constructor(config: GovernorConfig) {
    this.config = config;
  }

  /**
   * Check whether a call should be allowed before making it.
   * Returns a decision with the reason if blocked, or cached result if dedup hit.
   */
  check(request: GovernorCallRequest): GovernorDecision {
    const now = Date.now();

    // Sweep expired entries from dedup cache (amortized cleanup)
    this.sweepCache(now);

    // 1. Lifetime limit — absolute cap per process
    if (this.lifetimeCount >= this.config.lifetimeLimit) {
      return { allowed: false, reason: "lifetime_limit" };
    }

    // 2. Volume limit — rolling window call count
    this.pruneOldCalls(now);
    const callerLimit = this.config.callerOverrides.get(request.callerId)
      ?? this.config.volumeLimit;
    const callerCount = this.callerCounts.get(request.callerId) ?? 0;
    if (callerCount >= callerLimit) {
      return { allowed: false, reason: "volume_limit" };
    }

    // Also check global volume
    if (this.calls.length >= this.config.volumeLimit) {
      return { allowed: false, reason: "volume_limit" };
    }

    // 3. Spend limit — rolling window dollar cost
    const windowSpend = this.calls.reduce((sum, c) => sum + c.costDollars, 0);
    if (windowSpend + request.estimatedCostDollars > this.config.spendLimitDollars) {
      return { allowed: false, reason: "spend_limit" };
    }

    // 4. Duplicate detection — check content hash
    const hash = this.hashPrompt(request.prompt);
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
    const now = Date.now();

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

    // Cache for dedup
    const hash = this.hashPrompt(request.prompt);
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
    this.pruneOldCalls(Date.now());
    return {
      lifetimeCount: this.lifetimeCount,
      windowCalls: this.calls.length,
      windowSpend: this.calls.reduce((sum, c) => sum + c.costDollars, 0),
      cacheSize: this.dedupCache.size,
    };
  }

  // ── Internal Helpers ─────────────────────────────────────────────

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

  private hashPrompt(prompt: string): string {
    // Use Bun's built-in hasher for fast content hashing
    const hasher = new Bun.CryptoHasher("sha256");
    hasher.update(prompt);
    return hasher.digest("hex");
  }
}

/**
 * Create a new call governor with the given configuration.
 */
export function createGovernor(config: GovernorConfig): CallGovernor {
  return new CallGovernor(config);
}
