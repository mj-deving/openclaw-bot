import { describe, test, expect } from "bun:test";
import { scan, _internals } from "../layer2-scanner";
import type { ScannerConfig } from "../types";

// ── Test Helpers ─────────────────────────────────────────────────────

function mockLlm(response: string): ScannerConfig["llmCall"] {
  return async () => response;
}

function mockConfig(
  response: string,
  sourceRisk: ScannerConfig["sourceRisk"] = "low"
): ScannerConfig {
  return { llmCall: mockLlm(response), sourceRisk };
}

function errorConfig(sourceRisk: ScannerConfig["sourceRisk"] = "low"): ScannerConfig {
  return {
    llmCall: async () => { throw new Error("LLM unavailable"); },
    sourceRisk,
  };
}

// ── Tests ────────────────────────────────────────────────────────────

describe("Layer 2: LLM Frontier Scanner", () => {
  describe("Structured JSON response", () => {
    test("parses valid JSON response with all fields", async () => {
      const response = JSON.stringify({
        verdict: "block",
        score: 95,
        categories: ["prompt_injection", "jailbreak"],
        reasoning: "Clear attempt to override system instructions",
        evidence: ["ignore previous instructions", "you are now"],
      });
      const result = await scan("test input", mockConfig(response));

      expect(result.verdict).toBe("block");
      expect(result.score).toBe(95);
      expect(result.categories).toContain("prompt_injection");
      expect(result.categories).toContain("jailbreak");
      expect(result.reasoning).toBe("Clear attempt to override system instructions");
      expect(result.evidence).toHaveLength(2);
    });

    test("returns structured JSON with verdict field", async () => {
      const response = JSON.stringify({
        verdict: "allow",
        score: 5,
        categories: [],
        reasoning: "Benign text",
        evidence: [],
      });
      const result = await scan("hello world", mockConfig(response));
      expect(result.verdict).toBe("allow");
    });

    test("returns risk score 0-100", async () => {
      const response = JSON.stringify({
        verdict: "review",
        score: 65,
        categories: ["encoding_evasion"],
        reasoning: "Suspicious encoding found",
        evidence: ["base64 detected"],
      });
      const result = await scan("test", mockConfig(response));
      expect(result.score).toBe(65);
      expect(result.score).toBeGreaterThanOrEqual(0);
      expect(result.score).toBeLessThanOrEqual(100);
    });

    test("returns attack categories array", async () => {
      const response = JSON.stringify({
        verdict: "block",
        score: 90,
        categories: ["wallet_drain", "social_engineering"],
        reasoning: "Wallet drain attempt",
        evidence: ["0x742d35..."],
      });
      const result = await scan("test", mockConfig(response));
      expect(Array.isArray(result.categories)).toBe(true);
      expect(result.categories).toContain("wallet_drain");
    });

    test("returns reasoning string", async () => {
      const response = JSON.stringify({
        verdict: "allow",
        score: 10,
        categories: [],
        reasoning: "No suspicious patterns found",
        evidence: [],
      });
      const result = await scan("test", mockConfig(response));
      expect(typeof result.reasoning).toBe("string");
      expect(result.reasoning.length).toBeGreaterThan(0);
    });

    test("returns evidence array of suspicious fragments", async () => {
      const response = JSON.stringify({
        verdict: "block",
        score: 85,
        categories: ["prompt_injection"],
        reasoning: "Injection attempt",
        evidence: ["ignore previous", "system prompt override"],
      });
      const result = await scan("test", mockConfig(response));
      expect(Array.isArray(result.evidence)).toBe(true);
      expect(result.evidence.length).toBe(2);
    });
  });

  describe("Score-verdict override logic", () => {
    test("overrides allow to block when score >= 71", async () => {
      const response = JSON.stringify({
        verdict: "allow",  // Model says allow but score says danger
        score: 85,
        categories: ["prompt_injection"],
        reasoning: "Model misjudged",
        evidence: [],
      });
      const result = await scan("test", mockConfig(response));
      expect(result.verdict).toBe("block");
      expect(result.overridden).toBe(true);
    });

    test("overrides allow to review when score 51-70", async () => {
      const response = JSON.stringify({
        verdict: "allow",
        score: 60,
        categories: ["encoding_evasion"],
        reasoning: "Moderate risk",
        evidence: [],
      });
      const result = await scan("test", mockConfig(response));
      expect(result.verdict).toBe("review");
      expect(result.overridden).toBe(true);
    });

    test("overrides block to allow when score <= 20", async () => {
      const response = JSON.stringify({
        verdict: "block",
        score: 10,
        categories: [],
        reasoning: "False positive",
        evidence: [],
      });
      const result = await scan("test", mockConfig(response));
      expect(result.verdict).toBe("allow");
      expect(result.overridden).toBe(true);
    });

    test("does not override when score matches verdict", async () => {
      const response = JSON.stringify({
        verdict: "block",
        score: 90,
        categories: ["jailbreak"],
        reasoning: "Clear jailbreak",
        evidence: [],
      });
      const result = await scan("test", mockConfig(response));
      expect(result.verdict).toBe("block");
      expect(result.overridden).toBe(false);
    });
  });

  describe("Error handling", () => {
    test("blocks high-risk sources on error", async () => {
      const result = await scan("test", errorConfig("high"));
      expect(result.verdict).toBe("block");
      expect(result.reasoning).toContain("Scanner error");
    });

    test("allows low-risk sources on error", async () => {
      const result = await scan("test", errorConfig("low"));
      expect(result.verdict).toBe("allow");
    });

    test("reviews medium-risk sources on error", async () => {
      const result = await scan("test", errorConfig("medium"));
      expect(result.verdict).toBe("review");
    });

    test("handles malformed JSON response", async () => {
      const result = await scan("test", mockConfig("not json at all"));
      // Should fall back to error path
      expect(["allow", "review", "block"]).toContain(result.verdict);
    });

    test("handles JSON in markdown code block", async () => {
      const response = '```json\n' + JSON.stringify({
        verdict: "allow",
        score: 5,
        categories: [],
        reasoning: "Benign",
        evidence: [],
      }) + '\n```';
      const result = await scan("test", mockConfig(response));
      expect(result.verdict).toBe("allow");
      expect(result.score).toBe(5);
    });
  });

  describe("Internal helpers", () => {
    test("applyScoreOverride corrects mismatches", () => {
      expect(_internals.applyScoreOverride("allow", 90)).toEqual({
        verdict: "block",
        overridden: true,
      });
      expect(_internals.applyScoreOverride("block", 5)).toEqual({
        verdict: "allow",
        overridden: true,
      });
      expect(_internals.applyScoreOverride("block", 90)).toEqual({
        verdict: "block",
        overridden: false,
      });
    });

    test("parseResponse validates category names", () => {
      const result = _internals.parseResponse(JSON.stringify({
        verdict: "block",
        score: 50,
        categories: ["prompt_injection", "invalid_category"],
        reasoning: "test",
        evidence: [],
      }));
      expect(result?.categories).toContain("prompt_injection");
      expect(result?.categories).not.toContain("invalid_category");
    });

    test("parseResponse clamps score to 0-100", () => {
      const result = _internals.parseResponse(JSON.stringify({
        verdict: "block",
        score: 150,
        categories: [],
        reasoning: "test",
        evidence: [],
      }));
      expect(result?.score).toBe(100);
    });
  });
});
