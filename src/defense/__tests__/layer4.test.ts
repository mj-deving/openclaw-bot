import { describe, test, expect } from "bun:test";
import { redact } from "../layer4-redaction";
import type { RedactionConfig } from "../types";

const defaultConfig: RedactionConfig = {
  workDomains: ["company.com", "corp.org"],
};

describe("Layer 4: Redaction Pipeline", () => {
  // ── API Key Redaction ──────────────────────────────────────────────

  describe("API key redaction", () => {
    test("redacts Anthropic API keys", () => {
      const text = "Key: sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_KEY]");
      expect(result.redacted).not.toContain("sk-ant");
      expect(result.counts.apiKeys).toBeGreaterThan(0);
    });

    test("redacts Bearer tokens", () => {
      const text = "Auth: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_KEY]");
      expect(result.counts.apiKeys).toBeGreaterThan(0);
    });

    test("redacts Slack tokens", () => {
      // Build token dynamically to avoid GitHub push protection false positive
      const text = "Slack: " + ["xoxb", "123456789012", "1234567890123", "abcdefghijklmnop"].join("-");
      const result = redact(text, defaultConfig);
      expect(result.counts.apiKeys).toBeGreaterThan(0);
    });

    test("redacts multiple keys in same text", () => {
      const text = "Keys: sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaa and ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh12";
      const result = redact(text, defaultConfig);
      expect(result.counts.apiKeys).toBeGreaterThanOrEqual(2);
    });
  });

  // ── Email Redaction ────────────────────────────────────────────────

  describe("Email redaction", () => {
    test("redacts personal Gmail addresses", () => {
      const text = "Contact: john.doe@gmail.com";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_EMAIL]");
      expect(result.redacted).not.toContain("john.doe@gmail.com");
      expect(result.counts.emails).toBe(1);
    });

    test("redacts Yahoo addresses", () => {
      const text = "Email: user@yahoo.com";
      const result = redact(text, defaultConfig);
      expect(result.counts.emails).toBe(1);
    });

    test("redacts Hotmail/Outlook addresses", () => {
      const text = "Emails: a@hotmail.com and b@outlook.com";
      const result = redact(text, defaultConfig);
      expect(result.counts.emails).toBe(2);
    });

    test("redacts ProtonMail addresses", () => {
      const text = "Secure: user@protonmail.com";
      const result = redact(text, defaultConfig);
      expect(result.counts.emails).toBe(1);
    });

    test("preserves work domain emails", () => {
      const text = "Contact: alice@company.com and bob@corp.org";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("alice@company.com");
      expect(result.redacted).toContain("bob@corp.org");
      expect(result.counts.emails).toBe(0);
    });

    test("redacts personal but preserves work in same text", () => {
      const text = "Personal: john@gmail.com, Work: alice@company.com";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_EMAIL]");
      expect(result.redacted).toContain("alice@company.com");
      expect(result.counts.emails).toBe(1);
    });

    test("lets unknown domains through (conservative)", () => {
      const text = "Contact: user@someunknowndomain.io";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("user@someunknowndomain.io");
      expect(result.counts.emails).toBe(0);
    });
  });

  // ── Phone Number Redaction ─────────────────────────────────────────

  describe("Phone number redaction", () => {
    test("redacts US phone with dashes", () => {
      const text = "Call: 234-567-8901";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_PHONE]");
      expect(result.counts.phones).toBeGreaterThan(0);
    });

    test("redacts US phone with parentheses", () => {
      const text = "Call: (234) 567-8901";
      const result = redact(text, defaultConfig);
      expect(result.counts.phones).toBeGreaterThan(0);
    });

    test("redacts international phone numbers", () => {
      const text = "International: +44-20-7946-0958";
      const result = redact(text, defaultConfig);
      expect(result.counts.phones).toBeGreaterThan(0);
    });

    test("redacts US phone with +1 prefix", () => {
      const text = "Call: +1-234-567-8901";
      const result = redact(text, defaultConfig);
      expect(result.counts.phones).toBeGreaterThan(0);
    });
  });

  // ── Dollar Amount Redaction ────────────────────────────────────────

  describe("Dollar amount redaction", () => {
    test("redacts dollar amounts with commas", () => {
      const text = "Total: $1,234.56";
      const result = redact(text, defaultConfig);
      expect(result.redacted).toContain("[REDACTED_AMOUNT]");
      expect(result.counts.dollars).toBeGreaterThan(0);
    });

    test("redacts simple dollar amounts", () => {
      const text = "Cost: $99.99";
      const result = redact(text, defaultConfig);
      expect(result.counts.dollars).toBeGreaterThan(0);
    });

    test("redacts USD prefix format", () => {
      const text = "Amount: USD 5,000.00";
      const result = redact(text, defaultConfig);
      expect(result.counts.dollars).toBeGreaterThan(0);
    });

    test("redacts large amounts", () => {
      const text = "Budget: $1,000,000.00";
      const result = redact(text, defaultConfig);
      expect(result.counts.dollars).toBeGreaterThan(0);
    });
  });

  // ── Pipeline Integration ───────────────────────────────────────────

  describe("Pipeline chaining", () => {
    test("chains all filters in single pass", () => {
      const text =
        "Send $500 to john@gmail.com, key: sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaa, call (555) 123-4567";
      const result = redact(text, defaultConfig);
      expect(result.counts.apiKeys).toBeGreaterThan(0);
      expect(result.counts.emails).toBeGreaterThan(0);
      expect(result.counts.phones).toBeGreaterThan(0);
      expect(result.counts.dollars).toBeGreaterThan(0);
      // All should be redacted
      expect(result.redacted).not.toContain("john@gmail.com");
      expect(result.redacted).not.toContain("sk-ant");
    });

    test("returns zero counts for clean text", () => {
      const result = redact("Hello, how are you?", defaultConfig);
      expect(result.counts.apiKeys).toBe(0);
      expect(result.counts.emails).toBe(0);
      expect(result.counts.phones).toBe(0);
      expect(result.counts.dollars).toBe(0);
      expect(result.redacted).toBe("Hello, how are you?");
    });
  });
});
