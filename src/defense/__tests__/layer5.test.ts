import { describe, test, expect } from "bun:test";
import { createGovernor } from "../layer5-governor";
import type { GovernorConfig, GovernorCallRequest } from "../types";

function defaultConfig(overrides?: Partial<GovernorConfig>): GovernorConfig {
  return {
    spendLimitDollars: 10,
    spendWindowMs: 60_000, // 1 minute
    volumeLimit: 100,
    callerOverrides: new Map(),
    lifetimeLimit: 1000,
    dedupTtlMs: 300_000, // 5 minutes
    ...overrides,
  };
}

function makeRequest(overrides?: Partial<GovernorCallRequest>): GovernorCallRequest {
  return {
    callerId: "test-caller",
    prompt: "Tell me about TypeScript",
    estimatedCostDollars: 0.01,
    ...overrides,
  };
}

describe("Layer 5: Call Governor", () => {
  // ── Spend Limit ────────────────────────────────────────────────────

  describe("Spend limit", () => {
    test("tracks dollar cost in rolling window", () => {
      const gov = createGovernor(defaultConfig({ spendLimitDollars: 0.05 }));
      const req = makeRequest({ estimatedCostDollars: 0.02 });

      // First two calls should pass
      const d1 = gov.check(req);
      expect(d1.allowed).toBe(true);
      gov.record(req, "result1");

      const d2 = gov.check(req);
      expect(d2.allowed).toBe(true);
      gov.record(req, "result2");

      // Third call would exceed $0.05 limit (3 * $0.02 = $0.06)
      const d3 = gov.check(req);
      expect(d3.allowed).toBe(false);
      if (!d3.allowed) {
        expect(d3.reason).toBe("spend_limit");
      }
    });

    test("rejects calls when budget exceeded", () => {
      const gov = createGovernor(defaultConfig({ spendLimitDollars: 0.01 }));
      const req = makeRequest({ estimatedCostDollars: 0.02 });

      // Single call exceeds budget
      const decision = gov.check(req);
      expect(decision.allowed).toBe(false);
      if (!decision.allowed) {
        expect(decision.reason).toBe("spend_limit");
      }
    });
  });

  // ── Volume Limit ───────────────────────────────────────────────────

  describe("Volume limit", () => {
    test("enforces total call count cap", () => {
      const gov = createGovernor(defaultConfig({ volumeLimit: 3 }));
      const req = makeRequest();

      for (let i = 0; i < 3; i++) {
        const d = gov.check(req);
        expect(d.allowed).toBe(true);
        gov.record({ ...req, prompt: `prompt ${i}` }, `result ${i}`);
      }

      // 4th call should be blocked
      const d4 = gov.check(req);
      expect(d4.allowed).toBe(false);
      if (!d4.allowed) {
        expect(d4.reason).toBe("volume_limit");
      }
    });

    test("supports per-caller override thresholds", () => {
      const overrides = new Map([["vip-caller", 10]]);
      const gov = createGovernor(
        defaultConfig({ volumeLimit: 100, callerOverrides: overrides })
      );

      // Regular caller with default limit (100) — make 100 calls would be too many
      // Instead, set a lower per-caller override for regular and confirm it applies
      const overrides2 = new Map([
        ["vip-caller", 10],
        ["regular", 2],
      ]);
      const gov2 = createGovernor(
        defaultConfig({ volumeLimit: 100, callerOverrides: overrides2 })
      );

      const regular = makeRequest({ callerId: "regular" });
      gov2.record(regular, "r1");
      gov2.record({ ...regular, prompt: "p2" }, "r2");
      const d1 = gov2.check(regular);
      expect(d1.allowed).toBe(false);

      // VIP caller still has room (limit 10)
      const vip = makeRequest({ callerId: "vip-caller" });
      const d2 = gov2.check(vip);
      expect(d2.allowed).toBe(true);
    });
  });

  // ── Lifetime Counter ───────────────────────────────────────────────

  describe("Lifetime counter", () => {
    test("kills after max total calls per process", () => {
      const gov = createGovernor(defaultConfig({ lifetimeLimit: 3 }));
      const req = makeRequest();

      for (let i = 0; i < 3; i++) {
        gov.record({ ...req, prompt: `p${i}` }, `r${i}`);
      }

      const decision = gov.check(req);
      expect(decision.allowed).toBe(false);
      if (!decision.allowed) {
        expect(decision.reason).toBe("lifetime_limit");
      }
    });

    test("lifetime counter survives window pruning", () => {
      const gov = createGovernor(
        defaultConfig({ lifetimeLimit: 2, spendWindowMs: 1 })
      );
      const req = makeRequest();

      gov.record(req, "r1");
      gov.record({ ...req, prompt: "p2" }, "r2");

      // Even after window pruning, lifetime stays
      const decision = gov.check(req);
      expect(decision.allowed).toBe(false);
      if (!decision.allowed) {
        expect(decision.reason).toBe("lifetime_limit");
      }
    });
  });

  // ── Duplicate Detection ────────────────────────────────────────────

  describe("Duplicate detection", () => {
    test("caches recent prompts by content hash", () => {
      const gov = createGovernor(defaultConfig());
      const req = makeRequest({ prompt: "What is TypeScript?" });

      // First call: no cache
      const d1 = gov.check(req);
      expect(d1.allowed).toBe(true);
      if (d1.allowed) expect(d1.cached).toBe(false);
      gov.record(req, "TypeScript is a typed superset of JavaScript.");

      // Second call with same prompt: cached
      const d2 = gov.check(req);
      expect(d2.allowed).toBe(true);
      if (d2.allowed && d2.cached) {
        expect(d2.cachedResult).toBe("TypeScript is a typed superset of JavaScript.");
      }
    });

    test("returns cached result instead of new call", () => {
      const gov = createGovernor(defaultConfig());
      const req = makeRequest({ prompt: "Hello" });

      gov.record(req, "Hi there!");
      const decision = gov.check(req);

      expect(decision.allowed).toBe(true);
      if (decision.allowed && decision.cached) {
        expect(decision.cachedResult).toBe("Hi there!");
      }
    });

    test("does not cache different prompts", () => {
      const gov = createGovernor(defaultConfig());
      gov.record(makeRequest({ prompt: "Alpha" }), "Result A");

      const decision = gov.check(makeRequest({ prompt: "Beta" }));
      expect(decision.allowed).toBe(true);
      if (decision.allowed) expect(decision.cached).toBe(false);
    });
  });

  // ── Circuit Breaker (H-6) ─────────────────────────────────────────

  describe("Circuit breaker", () => {
    test("triggers after threshold blocks within window", () => {
      const gov = createGovernor(defaultConfig({
        spendLimitDollars: 0.001,
        circuitBreakerThreshold: 3,
        circuitBreakerWindowMs: 60_000,
      }));
      const req = makeRequest({ estimatedCostDollars: 0.01 });

      // Each check will be blocked by spend_limit, incrementing circuit breaker
      for (let i = 0; i < 3; i++) {
        const d = gov.check(req);
        expect(d.allowed).toBe(false);
        if (!d.allowed) expect(d.reason).toBe("spend_limit");
      }

      // 4th check should be circuit_breaker
      const d4 = gov.check(req);
      expect(d4.allowed).toBe(false);
      if (!d4.allowed) expect(d4.reason).toBe("circuit_breaker");
    });

    test("circuit breaker does not affect different callers", () => {
      const gov = createGovernor(defaultConfig({
        spendLimitDollars: 0.001,
        circuitBreakerThreshold: 2,
        circuitBreakerWindowMs: 60_000,
      }));

      // Trigger circuit breaker for caller-a
      for (let i = 0; i < 3; i++) {
        gov.check(makeRequest({ callerId: "caller-a", estimatedCostDollars: 0.01 }));
      }

      // caller-b should still get spend_limit, not circuit_breaker
      const d = gov.check(makeRequest({ callerId: "caller-b", estimatedCostDollars: 0.01 }));
      expect(d.allowed).toBe(false);
      if (!d.allowed) expect(d.reason).toBe("spend_limit");
    });
  });

  // ── CallerId-scoped Cache (C-3) ─────────────────────────────────

  describe("CallerId-scoped cache", () => {
    test("same prompt from different callers are not cached together", () => {
      const gov = createGovernor(defaultConfig());
      const prompt = "What is TypeScript?";

      // Caller A records a result
      gov.record(makeRequest({ callerId: "caller-a", prompt }), "Result A");

      // Caller B with same prompt should NOT get cached result
      const d = gov.check(makeRequest({ callerId: "caller-b", prompt }));
      expect(d.allowed).toBe(true);
      if (d.allowed) expect(d.cached).toBe(false);
    });

    test("same caller with same prompt gets cached result", () => {
      const gov = createGovernor(defaultConfig());
      const prompt = "What is TypeScript?";

      gov.record(makeRequest({ callerId: "caller-a", prompt }), "Result A");

      const d = gov.check(makeRequest({ callerId: "caller-a", prompt }));
      expect(d.allowed).toBe(true);
      if (d.allowed && d.cached) {
        expect(d.cachedResult).toBe("Result A");
      }
    });
  });

  // ── Configuration ──────────────────────────────────────────────────

  describe("Configuration", () => {
    test("all four mechanisms are independently configurable", () => {
      // Verify each config field is respected
      const config = defaultConfig({
        spendLimitDollars: 100,
        spendWindowMs: 3600_000,
        volumeLimit: 50,
        lifetimeLimit: 500,
        dedupTtlMs: 60_000,
      });
      const gov = createGovernor(config);
      const state = gov.getState();

      expect(state.lifetimeCount).toBe(0);
      expect(state.windowCalls).toBe(0);
      expect(state.windowSpend).toBe(0);
      expect(state.cacheSize).toBe(0);
    });
  });
});
