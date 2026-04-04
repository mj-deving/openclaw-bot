/**
 * Layer 1: Deterministic Text Sanitizer
 *
 * Synchronous pipeline that defends against:
 * - Unicode homoglyphs and invisible characters (P4RS3LT0NGV3)
 * - Base64/hex/ROT13 encoded payloads (P4RS3LT0NGV3)
 * - HTML/markdown injection (L1B3RT4S)
 * - System prompt overrides and role injection (L1B3RT4S)
 * - Zero-width character smuggling (P4RS3LT0NGV3)
 * - Whitespace/delimiter flooding
 * - Wallet address patterns (TOKEN80M8/TOKENADE)
 *
 * Returns detection stats alongside cleaned text for quarantine decisions.
 */

import type { SanitizerResult, SanitizerStats } from "./types";

// ── Constants ────────────────────────────────────────────────────────

/** Maximum input length to prevent ReDoS — 100KB */
const MAX_INPUT_LENGTH = 100_000;

/**
 * Zero-width and invisible Unicode characters used for token smuggling.
 * Covers: ZWSP, ZWNJ, ZWJ, LRM, RLM, BOM, soft hyphen, word joiner,
 * invisible times/separator, and variation selectors.
 */
const ZERO_WIDTH_REGEX =
  /[\u200B\u200C\u200D\u200E\u200F\uFEFF\u00AD\u2060\u2061\u2062\u2063\u2064\uFE00-\uFE0F\u180E\u034F\u17B4\u17B5\u2028\u2029\u202A-\u202E\u2066-\u2069]/g;

/**
 * Unicode confusable/homoglyph character map.
 * Maps visually similar Unicode chars to their ASCII equivalents.
 * Covers Cyrillic, Greek, and other scripts commonly used for homoglyph attacks.
 */
const HOMOGLYPH_MAP: Record<string, string> = {
  // Cyrillic lookalikes
  "\u0410": "A", "\u0430": "a", "\u0412": "B", "\u0435": "e",
  "\u0415": "E", "\u041D": "H", "\u043D": "h", "\u041A": "K",
  "\u043A": "k", "\u041C": "M", "\u043C": "m", "\u041E": "O",
  "\u043E": "o", "\u0420": "P", "\u0440": "p", "\u0421": "C",
  "\u0441": "c", "\u0422": "T", "\u0442": "t", "\u0425": "X",
  "\u0445": "x", "\u0443": "y", "\u0423": "Y",
  // Greek lookalikes
  "\u0391": "A", "\u0392": "B", "\u0395": "E", "\u0397": "H",
  "\u0399": "I", "\u039A": "K", "\u039C": "M", "\u039D": "N",
  "\u039F": "O", "\u03A1": "P", "\u03A4": "T", "\u03A5": "Y",
  "\u03A7": "X", "\u03B1": "a", "\u03BF": "o", "\u03C1": "p",
  // Fullwidth Latin
  "\uFF21": "A", "\uFF22": "B", "\uFF23": "C", "\uFF24": "D",
  "\uFF25": "E", "\uFF26": "F", "\uFF27": "G", "\uFF28": "H",
  "\uFF29": "I", "\uFF2A": "J", "\uFF2B": "K", "\uFF2C": "L",
  "\uFF2D": "M", "\uFF2E": "N", "\uFF2F": "O", "\uFF30": "P",
  "\uFF31": "Q", "\uFF32": "R", "\uFF33": "S", "\uFF34": "T",
  "\uFF35": "U", "\uFF36": "V", "\uFF37": "W", "\uFF38": "X",
  "\uFF39": "Y", "\uFF3A": "Z",
  "\uFF41": "a", "\uFF42": "b", "\uFF43": "c", "\uFF44": "d",
  "\uFF45": "e", "\uFF46": "f", "\uFF47": "g", "\uFF48": "h",
  "\uFF49": "i", "\uFF4A": "j", "\uFF4B": "k", "\uFF4C": "l",
  "\uFF4D": "m", "\uFF4E": "n", "\uFF4F": "o", "\uFF50": "p",
  "\uFF51": "q", "\uFF52": "r", "\uFF53": "s", "\uFF54": "t",
  "\uFF55": "u", "\uFF56": "v", "\uFF57": "w", "\uFF58": "x",
  "\uFF59": "y", "\uFF5A": "z",
  // Mathematical/special lookalikes
  "\u2010": "-", "\u2011": "-", "\u2012": "-", "\u2013": "-",
  "\u2014": "-", "\u2015": "-",
  "\u2018": "'", "\u2019": "'", "\u201C": '"', "\u201D": '"',
};

/**
 * System prompt override patterns from L1B3RT4S jailbreak catalog.
 * Case-insensitive matching. These catch the most common injection vectors.
 */
const SYSTEM_OVERRIDE_PATTERNS: RegExp[] = [
  /ignore\s+(?:all\s+)?(?:previous|prior|above|earlier)\s+(?:instructions?|prompts?|rules?|guidelines?)/i,
  /forget\s+(?:all\s+)?(?:previous|prior|above|earlier)\s+(?:instructions?|prompts?|rules?)/i,
  /disregard\s+(?:all\s+)?(?:previous|prior|above|earlier)\s+(?:instructions?|prompts?|rules?)/i,
  /you\s+are\s+now\s+(?:a|an|the|my)\s+/i,
  /new\s+(?:system\s+)?(?:instructions?|prompt|rules?|persona)\s*:/i,
  /override\s+(?:system|safety|content)\s+(?:prompt|instructions?|filters?|policy)/i,
  /(?:system|developer)\s*(?:mode|prompt)\s*(?:enabled|activated|on)/i,
  /entering\s+(?:developer|admin|debug|sudo|root|god)\s+mode/i,
  /\bDAN\b.*(?:do\s+anything|now\s+you)/i,
  /jailbreak|jail\s*break/i,
  /bypass\s+(?:safety|content|ethical|moderation)\s+(?:filters?|checks?|guidelines?|restrictions?)/i,
  /pretend\s+(?:you\s+(?:are|have)|there\s+(?:are|is))\s+no\s+(?:rules?|restrictions?|guidelines?|limits?)/i,
  /(?:act|behave|respond)\s+(?:as\s+if|like)\s+(?:you\s+)?(?:have\s+)?no\s+(?:rules?|restrictions?|filters?)/i,
  /\[(?:system|SYSTEM)\]\s*:/,
  /<<\s*(?:SYS|SYSTEM|INST)\s*>>/,
  /\bhuman\s*:\s*[\s\S]*\bassistant\s*:/i,
];

/**
 * Role injection patterns — attempts to inject fake conversation turns.
 * From L1B3RT4S and P4RS3LT0NGV3 role-play exploitation techniques.
 */
const ROLE_INJECTION_PATTERNS: RegExp[] = [
  /^(?:assistant|system|human|user|ai|bot|claude|gpt)\s*:/im,
  /\[(?:INST|\/INST|SYS|\/SYS)\]/i,
  /\|(?:im_start|im_end)\|/i,
  /<\|(?:system|user|assistant|endoftext|pad)\|>/i,
  /###\s*(?:System|User|Assistant|Human|Response)\s*:/i,
  /\bEND_TURN\b/i,
  /\[SYSTEM_PROMPT\]/i,
  /BEGIN\s+(?:SYSTEM|PROMPT|INSTRUCTION)/i,
];

/**
 * Wallet address patterns from TOKEN80M8/TOKENADE repos.
 * Ethereum, Bitcoin (legacy + segwit), Solana, and common token patterns.
 */
const WALLET_PATTERNS: RegExp[] = [
  /\b0x[a-fA-F0-9]{40}\b/,                    // Ethereum
  /\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b/,      // Bitcoin legacy
  /\bbc1[a-zA-HJ-NP-Z0-9]{25,90}\b/,          // Bitcoin segwit
  /\b[1-9A-HJ-NP-Za-km-z]{32,44}\b/,          // Solana (base58, 32-44 chars)
  /\bT[a-zA-Z0-9]{33}\b/,                      // Tron TRC20
];

/**
 * HTML/Markdown injection patterns.
 */
const MARKUP_PATTERNS: RegExp[] = [
  /<\s*script[^>]*>/gi,
  /<\s*\/\s*script\s*>/gi,
  /<\s*iframe[^>]*>/gi,
  /<\s*object[^>]*>/gi,
  /<\s*embed[^>]*>/gi,
  /<\s*link[^>]*>/gi,
  /<\s*style[^>]*>/gi,
  /<\s*img[^>]*\s+(?:on\w+|src\s*=\s*["']?javascript:)[^>]*>/gi,
  /!\[(?:[^\]]*)\]\(javascript:/gi,
  /\[(?:[^\]]*)\]\(javascript:/gi,
];

// ── Pipeline Steps ───────────────────────────────────────────────────

function removeZeroWidth(text: string, stats: SanitizerStats): string {
  let count = 0;
  const result = text.replace(ZERO_WIDTH_REGEX, () => { count++; return ""; });
  stats.zeroWidthRemoved = count;
  return result;
}

function normalizeUnicode(text: string, stats: SanitizerStats): string {
  // NFKC normalization first — handles fullwidth, compatibility chars
  let result = text.normalize("NFKC");

  // Then apply homoglyph map for chars that survive NFKC
  let count = 0;
  const chars = Array.from(result);
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i]!;
    const replacement = HOMOGLYPH_MAP[ch];
    if (replacement) {
      chars[i] = replacement;
      count++;
    }
  }
  stats.unicodeNormalized = count;
  return chars.join("");
}

function detectBase64(text: string, stats: SanitizerStats): string {
  // Match base64 strings of 20+ chars (to avoid short false positives)
  const base64Regex = /\b[A-Za-z0-9+/]{20,}={0,2}\b/g;
  let count = 0;
  const result = text.replace(base64Regex, (match) => {
    try {
      const decoded = atob(match);
      // Only flag if decoded content looks like text (printable ASCII)
      if (/^[\x20-\x7E\n\r\t]+$/.test(decoded) && decoded.length >= 8) {
        count++;
        return `[BASE64_DETECTED: ${decoded.slice(0, 50)}${decoded.length > 50 ? "..." : ""}]`;
      }
    } catch {
      // Not valid base64, leave as-is
    }
    return match;
  });
  stats.base64Detected = count;
  return result;
}

function detectHex(text: string, stats: SanitizerStats): string {
  // Match hex strings with common prefixes or long hex sequences
  const hexRegex = /(?:0x|\\x)?([0-9a-fA-F]{2}(?:\s*[0-9a-fA-F]{2}){7,})/g;
  let count = 0;
  const result = text.replace(hexRegex, (match, hexPart) => {
    try {
      const clean = hexPart.replace(/\s+/g, "").replace(/^(?:0x|\\x)/, "");
      const bytes = clean.match(/.{2}/g);
      if (bytes) {
        const decoded = bytes.map((b: string) => String.fromCharCode(parseInt(b, 16))).join("");
        if (/^[\x20-\x7E\n\r\t]+$/.test(decoded) && decoded.length >= 4) {
          count++;
          return `[HEX_DETECTED: ${decoded.slice(0, 50)}${decoded.length > 50 ? "..." : ""}]`;
        }
      }
    } catch {
      // Not valid hex, leave as-is
    }
    return match;
  });
  stats.hexDetected = count;
  return result;
}

function detectRot13(text: string, stats: SanitizerStats): string {
  // Look for ROT13 markers or common ROT13 encoded instruction words
  const rot13Markers = /\b(?:rot13|ROT13|ebg13)\b/gi;
  let count = 0;

  // If there's an explicit ROT13 marker, decode the adjacent text
  if (rot13Markers.test(text)) {
    count++;
    stats.rotDetected = count;
    // Decode any text after the marker
    return text.replace(
      /(?:rot13|ROT13|ebg13)\s*[:\-=]?\s*([A-Za-z\s]{10,})/gi,
      (_match, encoded) => {
        const decoded = rot13Decode(encoded);
        return `[ROT13_DETECTED: ${decoded}]`;
      }
    );
  }

  // Also check if the whole text looks like ROT13 of known attack phrases
  const knownRot13Attacks = [
    "vtaber", "vtaber cerivbhf", "lbh ner abj", "flfgrz cebzcg",
    "wnyvyoernx", "olcnff", "bireevqr",
  ];
  for (const attackRot of knownRot13Attacks) {
    if (text.toLowerCase().includes(attackRot)) {
      count++;
    }
  }
  stats.rotDetected = count;
  return text;
}

function rot13Decode(text: string): string {
  return text.replace(/[A-Za-z]/g, (c) => {
    const base = c <= "Z" ? 65 : 97;
    return String.fromCharCode(((c.charCodeAt(0) - base + 13) % 26) + base);
  });
}

function stripMarkup(text: string, stats: SanitizerStats): string {
  let count = 0;
  let result = text;
  for (const pattern of MARKUP_PATTERNS) {
    result = result.replace(pattern, () => { count++; return "[MARKUP_STRIPPED]"; });
  }
  stats.markupStripped = count;
  return result;
}

function detectSystemOverrides(text: string, stats: SanitizerStats): string {
  let count = 0;
  let result = text;
  for (const pattern of SYSTEM_OVERRIDE_PATTERNS) {
    if (pattern.test(result)) {
      count++;
    }
  }
  stats.systemOverrideDetected = count;
  // Don't strip — just flag. The quarantine layer decides what to do.
  return result;
}

function detectRoleInjection(text: string, stats: SanitizerStats): string {
  let count = 0;
  for (const pattern of ROLE_INJECTION_PATTERNS) {
    if (pattern.test(text)) {
      count++;
    }
  }
  stats.roleInjectionDetected = count;
  return text;
}

function normalizeWhitespace(text: string, stats: SanitizerStats): string {
  const original = text;
  // Collapse runs of 3+ whitespace chars to a single space
  let result = text.replace(/[ \t]{3,}/g, " ");
  // Collapse runs of 3+ newlines to double newline
  result = result.replace(/\n{3,}/g, "\n\n");
  // Remove delimiter flooding (e.g., ------, ======, ******)
  result = result.replace(/([=\-*_~#]{5,})/g, (match) => match.charAt(0).repeat(3));

  if (result !== original) {
    stats.whitespaceNormalized = 1;
  }
  return result;
}

function flagWalletAddresses(text: string, stats: SanitizerStats): string {
  let count = 0;
  for (const pattern of WALLET_PATTERNS) {
    const matches = text.match(pattern);
    if (matches) count += matches.length;
  }
  stats.walletAddressesFlagged = count;
  // Don't remove — just flag for quarantine layer
  return text;
}

// ── Main Pipeline ────────────────────────────────────────────────────

/**
 * Run the full sanitization pipeline synchronously.
 * Steps execute in deterministic order:
 * 1. Zero-width character removal
 * 2. Unicode normalization (homoglyphs)
 * 3. Base64 detection
 * 4. Hex detection
 * 5. ROT13 detection
 * 6. Markup stripping
 * 7. System override detection
 * 8. Role injection detection
 * 9. Whitespace normalization
 * 10. Wallet address flagging
 */
export function sanitize(input: string): SanitizerResult {
  // Enforce length limit to prevent ReDoS
  const text = input.length > MAX_INPUT_LENGTH
    ? input.slice(0, MAX_INPUT_LENGTH)
    : input;

  const stats: SanitizerStats = {
    unicodeNormalized: 0,
    base64Detected: 0,
    hexDetected: 0,
    rotDetected: 0,
    markupStripped: 0,
    systemOverrideDetected: 0,
    roleInjectionDetected: 0,
    zeroWidthRemoved: 0,
    whitespaceNormalized: 0,
    walletAddressesFlagged: 0,
  };

  // Steps run in deterministic order
  let cleaned = text;
  cleaned = removeZeroWidth(cleaned, stats);         // Step 1
  cleaned = normalizeUnicode(cleaned, stats);         // Step 2
  cleaned = detectBase64(cleaned, stats);             // Step 3
  cleaned = detectHex(cleaned, stats);                // Step 4
  cleaned = detectRot13(cleaned, stats);              // Step 5
  cleaned = stripMarkup(cleaned, stats);              // Step 6
  cleaned = detectSystemOverrides(cleaned, stats);    // Step 7
  cleaned = detectRoleInjection(cleaned, stats);      // Step 8
  cleaned = normalizeWhitespace(cleaned, stats);      // Step 9
  cleaned = flagWalletAddresses(cleaned, stats);      // Step 10

  const totalDetections = Object.values(stats).reduce((sum, v) => sum + v, 0);

  // High severity if system override, role injection, or wallet addresses detected
  const highSeverity =
    stats.systemOverrideDetected > 0 ||
    stats.roleInjectionDetected > 0 ||
    stats.walletAddressesFlagged > 0;

  return {
    cleaned,
    original: input,
    stats,
    totalDetections,
    highSeverity,
  };
}

// Exports for testing
export const _internals = {
  rot13Decode,
  SYSTEM_OVERRIDE_PATTERNS,
  ROLE_INJECTION_PATTERNS,
  WALLET_PATTERNS,
  ZERO_WIDTH_REGEX,
  HOMOGLYPH_MAP,
};
