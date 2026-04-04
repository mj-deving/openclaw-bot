/**
 * Layer 1: Deterministic Text Sanitizer
 *
 * Synchronous pipeline that defends against:
 * - Unicode homoglyphs and invisible characters (P4RS3LT0NGV3)
 * - Base64/base64url/hex/ROT13 encoded payloads (P4RS3LT0NGV3)
 * - HTML/markdown injection (L1B3RT4S)
 * - System prompt overrides and role injection (L1B3RT4S)
 * - Zero-width character smuggling (P4RS3LT0NGV3)
 * - Emoji steganography via variation selectors (P4RS3LT0NGV3)
 * - Unicode Private Use Area hidden text (P4RS3LT0NGV3)
 * - Zalgo text / combining diacritical abuse (P4RS3LT0NGV3)
 * - Whitespace steganography (P4RS3LT0NGV3)
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
 * Ethereum, Bitcoin (legacy + segwit), Tron.
 * (H-7: Solana removed — base58 32-44 char regex caused massive false positives)
 */
const WALLET_PATTERNS: RegExp[] = [
  /\b0x[a-fA-F0-9]{40}\b/,                    // Ethereum (40 hex chars)
  /\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b/,      // Bitcoin legacy
  /\bbc1[a-zA-HJ-NP-Z0-9]{25,90}\b/,          // Bitcoin segwit
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
  // (H-3): Match both standard base64 AND URL-safe base64 (- and _ instead of + and /)
  const base64Regex = /\b[A-Za-z0-9+/\-_]{20,}={0,2}\b/g;
  let count = 0;
  const result = text.replace(base64Regex, (match) => {
    try {
      // Try standard base64 first, then URL-safe
      const normalized = match.replace(/-/g, "+").replace(/_/g, "/");
      const decoded = atob(normalized);
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
  // (M-8): Flexible delimiters between hex bytes — supports spaces, dashes, pipes, colons, commas
  const hexRegex = /(?:0x|\\x)?([0-9a-fA-F]{2}(?:[\s\-_|,:]*[0-9a-fA-F]{2}){7,})/g;
  let count = 0;
  const result = text.replace(hexRegex, (match, hexPart) => {
    try {
      const clean = hexPart.replace(/[\s\-_|,:]+/g, "").replace(/^(?:0x|\\x)/, "");
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
  const rot13Markers = /\b(?:rot13|ROT13|ebg13)\b/gi;
  let count = 0;
  let result = text;

  // If there's an explicit ROT13 marker, decode the adjacent text
  if (rot13Markers.test(result)) {
    count++;
    result = result.replace(
      /(?:rot13|ROT13|ebg13)\s*[:\-=]?\s*([A-Za-z\s]{10,})/gi,
      (_match, encoded) => {
        const decoded = rot13Decode(encoded);
        return `[ROT13_DETECTED: ${decoded}]`;
      }
    );
  }

  // (H-2): Also check known ROT13 attack phrases AND sanitize them
  const knownRot13Attacks = [
    "vtaber", "vtaber cerivbhf", "lbh ner abj", "flfgrz cebzcg",
    "wnyvyoernx", "olcnff", "bireevqr",
  ];
  for (const attackRot of knownRot13Attacks) {
    if (result.toLowerCase().includes(attackRot)) {
      count++;
      // Replace the ROT13 attack phrase with decoded marker
      const decoded = rot13Decode(attackRot);
      result = result.replace(
        new RegExp(attackRot.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi"),
        `[ROT13_DETECTED: ${decoded}]`
      );
    }
  }
  stats.rotDetected = count;
  return result;
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
  const result = text;
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
  // (L-13): Collapse runs of 2+ whitespace chars to a single space (lowered from 3)
  let result = text.replace(/[ \t]{2,}/g, " ");
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

// ── New P4RS3LT0NGV3 Encoding Detections (H-1) ─────────────────────

/**
 * (H-1) Emoji steganography detection.
 * P4RS3LT0NGV3 uses variation selectors (U+FE0E text, U+FE0F emoji) after
 * carrier emojis to encode binary data. Detect suspicious density of
 * variation selectors adjacent to emojis.
 */
function detectEmojiStego(text: string, stats: SanitizerStats): string {
  // Count variation selector pairs (FE0E/FE0F) — legitimate text rarely has >2
  const variationSelectorPairs = text.match(/[\uFE0E\uFE0F]{2,}/g);
  // Also detect carrier emojis followed by variation selectors
  const emojiWithSelectors = text.match(/[\u{1F40D}\u{1F409}\u{1F432}\u{1F40A}][\uFE0E\uFE0F]+/gu);

  let count = 0;
  if (variationSelectorPairs && variationSelectorPairs.length > 2) {
    count += variationSelectorPairs.length;
  }
  if (emojiWithSelectors) {
    count += emojiWithSelectors.length;
  }

  if (count > 0) {
    // Strip variation selectors to neutralize the steganographic channel
    const result = text.replace(/[\uFE0E\uFE0F]+/g, "");
    stats.emojiStegoDetected = count;
    return result;
  }
  stats.emojiStegoDetected = 0;
  return text;
}

/**
 * (H-1) Unicode Private Use Area detection.
 * P4RS3LT0NGV3 uses U+E0000-U+E00FF to encode invisible text.
 * These characters have zero visual width and are exclusively PUA.
 */
function detectUnicodePua(text: string, stats: SanitizerStats): string {
  // Tags block: U+E0000-U+E007F (Supplementary Special-purpose Plane)
  const puaRegex = /[\u{E0000}-\u{E007F}]/gu;
  let count = 0;
  const result = text.replace(puaRegex, () => { count++; return ""; });
  stats.unicodePuaDetected = count;
  return result;
}

/**
 * (H-1) Zalgo text detection — combining diacritical mark abuse.
 * Legitimate text rarely has >2 combining marks per character.
 * Zalgo uses 10-50+ combining marks (U+0300-U+036F) to create distorted text.
 */
function detectZalgo(text: string, stats: SanitizerStats): string {
  // Match sequences of 3+ combining diacritical marks
  const zalgoRegex = /[\u0300-\u036F\u0489]{3,}/g;
  let count = 0;
  const result = text.replace(zalgoRegex, () => { count++; return ""; });
  stats.zalgoDetected = count;
  return result;
}

/**
 * (H-1) Whitespace steganography detection.
 * P4RS3LT0NGV3 encodes binary using space=0, tab=1 in 8-char groups.
 * Detect text where >80% of content is spaces/tabs in groups of 8.
 */
function detectWhitespaceSteganography(text: string, stats: SanitizerStats): string {
  // Look for blocks of exactly 8 space/tab characters (binary encoding)
  const stegoPattern = /(?:[ \t]{8}){2,}/g;
  const matches = text.match(stegoPattern);
  if (matches) {
    const stegoChars = matches.reduce((sum, m) => sum + m.length, 0);
    // If stego characters make up >50% of the text, flag it
    if (stegoChars > text.length * 0.5 && text.length > 16) {
      stats.whitespaceStegoDetected = matches.length;
      return text.replace(stegoPattern, "[WHITESPACE_STEGO_DETECTED]");
    }
  }
  stats.whitespaceStegoDetected = 0;
  return text;
}

// ── Main Pipeline ────────────────────────────────────────────────────

/**
 * Run the full sanitization pipeline synchronously.
 * Steps execute in deterministic order:
 * 1. Zero-width character removal
 * 2. Unicode PUA detection (H-1)
 * 3. Emoji steganography detection (H-1)
 * 4. Unicode normalization (homoglyphs)
 * 5. Zalgo/combining diacritical detection (H-1)
 * 6. Base64 detection (including base64url — H-3)
 * 7. Hex detection (flexible delimiters — M-8)
 * 8. ROT13 detection (with sanitization — H-2)
 * 9. Markup stripping
 * 10. System override detection
 * 11. Role injection detection
 * 12. Whitespace steganography detection (H-1)
 * 13. Whitespace normalization
 * 14. Wallet address flagging (tightened Solana — H-7)
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
    emojiStegoDetected: 0,
    unicodePuaDetected: 0,
    zalgoDetected: 0,
    whitespaceStegoDetected: 0,
  };

  // Steps run in deterministic order
  let cleaned = text;
  cleaned = removeZeroWidth(cleaned, stats);                // Step 1
  cleaned = detectUnicodePua(cleaned, stats);               // Step 2 (H-1)
  cleaned = detectEmojiStego(cleaned, stats);               // Step 3 (H-1)
  cleaned = normalizeUnicode(cleaned, stats);               // Step 4
  cleaned = detectZalgo(cleaned, stats);                    // Step 5 (H-1)
  cleaned = detectBase64(cleaned, stats);                   // Step 6 (H-3)
  cleaned = detectHex(cleaned, stats);                      // Step 7 (M-8)
  cleaned = detectRot13(cleaned, stats);                    // Step 8 (H-2)
  cleaned = stripMarkup(cleaned, stats);                    // Step 9
  cleaned = detectSystemOverrides(cleaned, stats);          // Step 10
  cleaned = detectRoleInjection(cleaned, stats);            // Step 11
  cleaned = detectWhitespaceSteganography(cleaned, stats);  // Step 12 (H-1)
  cleaned = normalizeWhitespace(cleaned, stats);            // Step 13
  cleaned = flagWalletAddresses(cleaned, stats);            // Step 14

  const totalDetections = Object.values(stats).reduce((sum, v) => sum + v, 0);

  // High severity if system override, role injection, or wallet addresses detected
  const highSeverity =
    stats.systemOverrideDetected > 0 ||
    stats.roleInjectionDetected > 0 ||
    stats.walletAddressesFlagged > 0 ||
    stats.emojiStegoDetected > 0 ||
    stats.unicodePuaDetected > 0;

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
