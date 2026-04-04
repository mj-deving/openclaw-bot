/**
 * Layer 3: Outbound Content Gate
 *
 * Scans text leaving the system for:
 * - Leaked API keys and secrets
 * - Internal file paths
 * - Prompt injection artifacts that survived into output
 * - Data exfiltration via embedded image URLs
 * - Financial data (card numbers, bank accounts)
 *
 * All checks are instant pattern matching — zero API calls.
 */

import type { OutboundGateResult, OutboundViolation } from "./types";
import { buildNamedPatterns } from "./patterns";

// ── Secret Patterns ──────────────────────────────────────────────────

/** Built from shared pattern definitions — single source of truth */
const SECRET_PATTERNS = buildNamedPatterns();

// ── Internal Path Patterns ───────────────────────────────────────────

const INTERNAL_PATH_PATTERNS: RegExp[] = [
  // Unix home directories
  /(?:\/home\/[a-z_][a-z0-9_-]*|~\/)[^\s'">)}\]]{3,}/g,
  // /etc config paths
  /\/etc\/(?:passwd|shadow|sudoers|ssh|ssl|nginx|apache|systemd)[^\s'">)}\]]*/g,
  // /var paths
  /\/var\/(?:log|lib|run|spool)\/[^\s'">)}\]]{3,}/g,
  // /tmp with sensitive-looking content
  /\/tmp\/[^\s'">)}\]]*(?:key|secret|token|pass|cred|auth)[^\s'">)}\]]*/gi,
  // (M-2) Windows paths — any drive letter with backslash path
  /[A-Z]:\\(?:[a-zA-Z0-9._\-]+\\)+[^\s'">)}\]]{1,}/g,
  // (M-2) UNC paths (\\server\share\...)
  /\\\\[a-zA-Z0-9.\-]+\\[^\s'">)}\]]{3,}/g,
  // .dotfile paths
  /(?:\/|~\/)\.[a-z]+\/[^\s'">)}\]]{3,}/g,
];

// ── Injection Artifact Patterns ──────────────────────────────────────

const INJECTION_ARTIFACT_PATTERNS: RegExp[] = [
  // Leaked system prompt markers (L-21: expanded with space tolerance)
  /\[\s*(?:SYSTEM|INST|\/INST|SYS|\/SYS)\s*\]/gi,
  /<<\s*(?:SYS|SYSTEM)\s*>>/gi,
  /<\|(?:system|endoftext|im_start|im_end)\|>/gi,
  // (L-21) Prompt injection fragments — expanded verb forms
  /ignor(?:e|ing)\s+(?:all\s+)?previous\s+(?:instructions?|rules?)/gi,
  /you\s+are\s+(?:now\s+)?(?:a|an|the|being|acting\s+as)/gi,
  /disregard\s+(?:all\s+)?(?:previous|prior|above)/gi,
  // Role labels that shouldn't appear in output
  /^(?:Human|Assistant|System|User)\s*:/gm,
];

// ── Exfiltration URL Patterns ────────────────────────────────────────

const EXFIL_URL_PATTERNS: RegExp[] = [
  // Image URLs with query params that could carry exfiltrated data
  /!\[(?:[^\]]*)\]\(https?:\/\/[^\s)]+\?[^\s)]*(?:data|token|key|secret|prompt|system|password)=[^\s)]+\)/gi,
  // Markdown images with suspicious domains
  /!\[(?:[^\]]*)\]\(https?:\/\/(?:[a-z0-9-]+\.)*(?:ngrok|webhook\.site|requestbin|pipedream|burp|interact\.sh)[^\s)]*\)/gi,
  // HTML images with exfil params
  /<img[^>]+src\s*=\s*["']https?:\/\/[^"']+\?[^"']*(?:data|token|key|secret|prompt)[^"']*["'][^>]*>/gi,
  // General tracking pixels / beacons
  /!\[(?:[ ]?)\]\(https?:\/\/[^\s)]+\)/g,  // Zero-content images (tracking pixels)
];

// ── Financial Data Patterns ──────────────────────────────────────────

const FINANCIAL_PATTERNS: Array<{ pattern: RegExp; name: string }> = [
  // Credit card numbers (Luhn-plausible ranges)
  { pattern: /\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b/, name: "Credit card number" },
  // Bank account + routing numbers
  { pattern: /\b[0-9]{9,18}\b(?=\s*(?:routing|account|iban|swift|bic|aba))/gi, name: "Bank account number" },
  // IBAN
  { pattern: /\b[A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}(?:[A-Z0-9]{0,16})\b/, name: "IBAN" },
  // SWIFT/BIC
  { pattern: /\b[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}(?:[A-Z0-9]{3})?\b(?=\s*(?:swift|bic|code))/gi, name: "SWIFT/BIC code" },
  // SSN-like patterns
  { pattern: /\b\d{3}-\d{2}-\d{4}\b/, name: "SSN-like number" },
];

// ── Gate Implementation ──────────────────────────────────────────────

function checkSecrets(text: string): OutboundViolation[] {
  const violations: OutboundViolation[] = [];
  for (const { pattern, name } of SECRET_PATTERNS) {
    const match = text.match(pattern);
    if (match) {
      violations.push({
        type: "leaked_secret",
        match: match[0].slice(0, 10) + "***",
        reason: `Detected ${name}`,
      });
    }
  }
  return violations;
}

function checkPaths(text: string): OutboundViolation[] {
  const violations: OutboundViolation[] = [];
  for (const pattern of INTERNAL_PATH_PATTERNS) {
    pattern.lastIndex = 0;
    const match = pattern.exec(text);
    if (match) {
      violations.push({
        type: "internal_path",
        match: match[0],
        reason: "Internal file path detected in output",
      });
    }
  }
  return violations;
}

function checkInjectionArtifacts(text: string): OutboundViolation[] {
  const violations: OutboundViolation[] = [];
  for (const pattern of INJECTION_ARTIFACT_PATTERNS) {
    pattern.lastIndex = 0;
    const match = pattern.exec(text);
    if (match) {
      violations.push({
        type: "injection_artifact",
        match: match[0],
        reason: "Prompt injection artifact survived into output",
      });
    }
  }
  return violations;
}

function checkExfilUrls(text: string): OutboundViolation[] {
  const violations: OutboundViolation[] = [];
  for (const pattern of EXFIL_URL_PATTERNS) {
    pattern.lastIndex = 0;
    const match = pattern.exec(text);
    if (match) {
      violations.push({
        type: "exfil_url",
        match: match[0].slice(0, 80) + (match[0].length > 80 ? "..." : ""),
        reason: "Potential data exfiltration via embedded URL",
      });
    }
  }
  return violations;
}

function checkFinancialData(text: string): OutboundViolation[] {
  const violations: OutboundViolation[] = [];
  for (const { pattern, name } of FINANCIAL_PATTERNS) {
    pattern.lastIndex = 0;
    const match = pattern.exec(text);
    if (match) {
      violations.push({
        type: "financial_data",
        match: match[0].slice(0, 4) + "****",
        reason: `Detected ${name}`,
      });
    }
  }
  return violations;
}

// ── Public API ────────────────────────────────────────────────────────

/**
 * Scan outbound text for leaked secrets, paths, injection artifacts,
 * exfiltration URLs, and financial data.
 *
 * All checks are instant pattern matching — zero API calls.
 */
export function gate(text: string): OutboundGateResult {
  const violations: OutboundViolation[] = [
    ...checkSecrets(text),
    ...checkPaths(text),
    ...checkInjectionArtifacts(text),
    ...checkExfilUrls(text),
    ...checkFinancialData(text),
  ];

  // Redact all violation types from cleaned output
  let cleaned = text;
  if (violations.length > 0) {
    for (const { pattern } of SECRET_PATTERNS) {
      cleaned = cleaned.replace(pattern, "[REDACTED_SECRET]");
    }
    for (const pattern of INTERNAL_PATH_PATTERNS) {
      pattern.lastIndex = 0;
      cleaned = cleaned.replace(pattern, "[REDACTED_PATH]");
    }
    for (const pattern of INJECTION_ARTIFACT_PATTERNS) {
      pattern.lastIndex = 0;
      cleaned = cleaned.replace(pattern, "[REDACTED_ARTIFACT]");
    }
    for (const pattern of EXFIL_URL_PATTERNS) {
      pattern.lastIndex = 0;
      cleaned = cleaned.replace(pattern, "[REDACTED_URL]");
    }
    for (const { pattern } of FINANCIAL_PATTERNS) {
      pattern.lastIndex = 0;
      cleaned = cleaned.replace(pattern, "[REDACTED_FINANCIAL]");
    }
  }

  return {
    passed: violations.length === 0,
    violations,
    cleaned,
  };
}

// Exports for testing
export const _internals = {
  SECRET_PATTERNS,
  INTERNAL_PATH_PATTERNS,
  INJECTION_ARTIFACT_PATTERNS,
  EXFIL_URL_PATTERNS,
  FINANCIAL_PATTERNS,
};
