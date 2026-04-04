/**
 * Layer 4: Redaction Pipeline
 *
 * Catches and redacts before any outbound message:
 * - API keys and bearer tokens
 * - Personal email addresses (filtered against personal providers, work domains pass through)
 * - Phone numbers in multiple formats
 * - Dollar amounts
 *
 * Chains all filters into a single pipeline that runs before outbound delivery.
 */

import type { RedactionResult, RedactionConfig } from "./types";
import { buildGlobalPatterns } from "./patterns";

// ── Personal Email Providers ─────────────────────────────────────────

/**
 * Domains classified as personal email providers.
 * Emails at these domains get redacted. Work domains pass through.
 */
const PERSONAL_EMAIL_DOMAINS = new Set([
  // Major providers
  "gmail.com", "googlemail.com",
  "yahoo.com", "yahoo.co.uk", "yahoo.fr", "yahoo.de", "yahoo.co.jp",
  "hotmail.com", "hotmail.co.uk", "hotmail.fr", "hotmail.de",
  "outlook.com", "live.com", "msn.com",
  "aol.com",
  "icloud.com", "me.com", "mac.com",
  "protonmail.com", "proton.me", "pm.me",
  "tutanota.com", "tuta.io",
  "zoho.com",
  "mail.com",
  "yandex.com", "yandex.ru",
  "gmx.com", "gmx.de", "gmx.net",
  "fastmail.com", "fastmail.fm",
  "hushmail.com",
  "mailfence.com",
  "startmail.com",
  "posteo.de",
  "mailbox.org",
  "runbox.com",
  "disroot.org",
  "riseup.net",
  "cock.li",
  // Disposable/temporary
  "tempmail.com", "guerrillamail.com", "mailinator.com",
  "throwaway.email", "temp-mail.org", "10minutemail.com",
  "yopmail.com", "sharklasers.com", "guerrillamailblock.com",
  "grr.la", "maildrop.cc",
]);

// ── Patterns ─────────────────────────────────────────────────────────

/** Email regex — captures the full email and the domain part */
const EMAIL_REGEX = /\b([a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}))\b/g;

/** Built from shared pattern definitions with global flag for replacement */
const API_KEY_PATTERNS: RegExp[] = buildGlobalPatterns();

/**
 * Phone number patterns — covers:
 * - International: +1-234-567-8901, +44 20 7946 0958
 * - US formats: (234) 567-8901, 234-567-8901, 234.567.8901
 * - With extensions: x1234, ext. 1234
 */
const PHONE_PATTERNS: RegExp[] = [
  /\+?1?\s*[-.]?\s*\(?[2-9]\d{2}\)?\s*[-.]?\s*\d{3}\s*[-.]?\s*\d{4}(?:\s*(?:x|ext\.?)\s*\d{1,5})?/g,
  /\+[1-9]\d{0,2}[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,9}/g,
];

/**
 * Dollar amount patterns — catches:
 * - $1,234.56, $1234, $0.99
 * - USD 1,234.56, 1,234.56 USD
 */
const DOLLAR_PATTERNS: RegExp[] = [
  /\$\s*\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\b/g,
  /\bUSD\s*\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\b/g,
  /\b\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\s*USD\b/g,
];

// ── Pipeline Steps ───────────────────────────────────────────────────

function redactApiKeys(text: string): { text: string; count: number } {
  let count = 0;
  let result = text;
  for (const pattern of API_KEY_PATTERNS) {
    pattern.lastIndex = 0;
    result = result.replace(pattern, () => {
      count++;
      return "[REDACTED_KEY]";
    });
  }
  return { text: result, count };
}

function redactEmails(
  text: string,
  workDomains: Set<string>
): { text: string; count: number } {
  let count = 0;
  const result = text.replace(EMAIL_REGEX, (fullMatch, _email, domain) => {
    const domainLower = domain.toLowerCase();
    // Skip work domains — let them through
    if (workDomains.has(domainLower)) {
      return fullMatch;
    }
    // Redact if it's a personal provider domain
    if (PERSONAL_EMAIL_DOMAINS.has(domainLower)) {
      count++;
      return "[REDACTED_EMAIL]";
    }
    // Unknown domain — let it through (conservative: only redact known personal providers)
    return fullMatch;
  });
  return { text: result, count };
}

function redactPhones(text: string): { text: string; count: number } {
  let count = 0;
  let result = text;
  for (const pattern of PHONE_PATTERNS) {
    pattern.lastIndex = 0;
    result = result.replace(pattern, () => {
      count++;
      return "[REDACTED_PHONE]";
    });
  }
  return { text: result, count };
}

function redactDollars(text: string): { text: string; count: number } {
  let count = 0;
  let result = text;
  for (const pattern of DOLLAR_PATTERNS) {
    pattern.lastIndex = 0;
    result = result.replace(pattern, () => {
      count++;
      return "[REDACTED_AMOUNT]";
    });
  }
  return { text: result, count };
}

// ── Public API ────────────────────────────────────────────────────────

/**
 * Run the full redaction pipeline in a single pass.
 * Order: API keys → emails → phones → dollars
 *
 * @param text - Outbound text to redact
 * @param config - Configuration with work email domains to preserve
 */
export function redact(text: string, config: RedactionConfig): RedactionResult {
  const workDomains = new Set(
    config.workDomains.map((d) => d.toLowerCase())
  );

  const keys = redactApiKeys(text);
  const emails = redactEmails(keys.text, workDomains);
  const phones = redactPhones(emails.text);
  const dollars = redactDollars(phones.text);

  return {
    redacted: dollars.text,
    counts: {
      apiKeys: keys.count,
      emails: emails.count,
      phones: phones.count,
      dollars: dollars.count,
    },
  };
}

// Exports for testing
export const _internals = {
  PERSONAL_EMAIL_DOMAINS,
  EMAIL_REGEX,
  PHONE_PATTERNS,
  DOLLAR_PATTERNS,
};
