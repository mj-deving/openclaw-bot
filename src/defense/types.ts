/**
 * Shared types for the 6-layer prompt injection defense system.
 *
 * Layer 1: Deterministic sanitizer
 * Layer 2: LLM frontier scanner
 * Layer 3: Outbound content gate
 * Layer 4: Redaction pipeline
 * Layer 5: Call governor
 * Layer 6: Access control
 */

// ── Layer 1: Sanitizer ──────────────────────────────────────────────

export interface SanitizerStats {
  /** Number of homoglyphs/invisible chars removed */
  unicodeNormalized: number;
  /** Number of base64-encoded payloads detected */
  base64Detected: number;
  /** Number of hex-encoded payloads detected */
  hexDetected: number;
  /** Number of ROT13/Caesar payloads detected */
  rotDetected: number;
  /** Number of HTML/markdown injection tags stripped */
  markupStripped: number;
  /** Number of system prompt override patterns detected */
  systemOverrideDetected: number;
  /** Number of role injection patterns detected */
  roleInjectionDetected: number;
  /** Number of zero-width characters removed */
  zeroWidthRemoved: number;
  /** Number of whitespace/delimiter flooding instances normalized */
  whitespaceNormalized: number;
  /** Number of wallet addresses flagged */
  walletAddressesFlagged: number;
  /** Number of emoji steganography patterns detected */
  emojiStegoDetected: number;
  /** Number of Unicode Private Use Area characters detected */
  unicodePuaDetected: number;
  /** Number of Zalgo/combining diacritical abuse detected */
  zalgoDetected: number;
  /** Number of whitespace steganography patterns detected */
  whitespaceStegoDetected: number;
}

export interface SanitizerResult {
  /** Cleaned text after all sanitization */
  cleaned: string;
  /** Original text before sanitization */
  original: string;
  /** Detection statistics for quarantine decisions */
  stats: SanitizerStats;
  /** Total number of detections across all categories */
  totalDetections: number;
  /** Whether any high-severity patterns were found */
  highSeverity: boolean;
}

/**
 * Safe external result — strips internal detection details.
 * Use this when returning results to untrusted callers (H-4).
 */
export interface ExternalScanResult {
  /** Final verdict */
  verdict: ScanVerdict;
  /** Whether input was flagged */
  flagged: boolean;
  /** Whether input was blocked */
  blocked: boolean;
}

// ── Layer 2: Frontier Scanner ───────────────────────────────────────

export type ScanVerdict = "allow" | "review" | "block";

export type AttackCategory =
  | "prompt_injection"
  | "jailbreak"
  | "role_hijack"
  | "encoding_evasion"
  | "data_exfiltration"
  | "wallet_drain"
  | "social_engineering"
  | "instruction_override"
  | "context_manipulation"
  | "unknown";

export type SourceRisk = "high" | "medium" | "low";

export interface ScannerResult {
  /** Final verdict: allow, review, or block */
  verdict: ScanVerdict;
  /** Risk score 0-100 */
  score: number;
  /** Detected attack categories */
  categories: AttackCategory[];
  /** Human-readable reasoning for the classification */
  reasoning: string;
  /** Specific suspicious fragments found */
  evidence: string[];
  /** Whether the verdict was overridden by score logic */
  overridden: boolean;
}

export interface ScannerConfig {
  /** Function to call the LLM — decoupled for testability */
  llmCall: (prompt: string) => Promise<string>;
  /** Source risk level for error-path handling */
  sourceRisk: SourceRisk;
}

// ── Layer 1+2 Combined Entry Point ──────────────────────────────────

export interface InputScanResult {
  /** Layer 1 sanitizer result */
  sanitizer: SanitizerResult;
  /** Layer 2 scanner result (null if L1 blocked before reaching L2) */
  scanner: ScannerResult | null;
  /** Final verdict combining both layers */
  finalVerdict: ScanVerdict;
  /** Whether the input was blocked before reaching the scanner */
  blockedBySanitizer: boolean;
}

/**
 * Audit log entry for every scan decision (H-5).
 * Integrators persist these for forensic trail.
 */
export interface AuditEntry {
  timestamp: string;
  source: string;
  verdict: ScanVerdict;
  score: number | null;
  totalDetections: number;
  highSeverity: boolean;
  blockedBySanitizer: boolean;
  categories: AttackCategory[];
}

/** Audit callback — integrators provide this to persist scan decisions */
export type AuditCallback = (entry: AuditEntry) => void;

// ── Layer 3: Outbound Content Gate ──────────────────────────────────

export interface OutboundGateResult {
  /** Whether the content passed all checks */
  passed: boolean;
  /** List of violations found */
  violations: OutboundViolation[];
  /** Cleaned content with violations redacted */
  cleaned: string;
}

export interface OutboundViolation {
  type:
    | "leaked_secret"
    | "internal_path"
    | "injection_artifact"
    | "exfil_url"
    | "financial_data";
  /** The matched text */
  match: string;
  /** Description of why this was flagged */
  reason: string;
}

// ── Layer 4: Redaction Pipeline ─────────────────────────────────────

export interface RedactionResult {
  /** Text after redaction */
  redacted: string;
  /** Number of items redacted by category */
  counts: {
    apiKeys: number;
    emails: number;
    phones: number;
    dollars: number;
  };
}

export interface RedactionConfig {
  /** Work email domains to preserve (e.g., ["company.com", "corp.org"]) */
  workDomains: string[];
}

// ── Layer 5: Call Governor ───────────────────────────────────────────

export interface GovernorConfig {
  /** Maximum spend in dollars within the rolling window */
  spendLimitDollars: number;
  /** Rolling window duration in milliseconds */
  spendWindowMs: number;
  /** Maximum total calls within the rolling window */
  volumeLimit: number;
  /** Per-caller volume overrides (callerId → limit) */
  callerOverrides: Map<string, number>;
  /** Absolute maximum calls per process lifetime */
  lifetimeLimit: number;
  /** TTL for duplicate cache entries in milliseconds */
  dedupTtlMs: number;
  /** Circuit breaker: max blocked requests per source before auto-block (H-6) */
  circuitBreakerThreshold?: number;
  /** Circuit breaker window in ms (default: 60_000) */
  circuitBreakerWindowMs?: number;
}

export interface GovernorCallRequest {
  /** Unique identifier for the caller */
  callerId: string;
  /** The prompt text (used for dedup hashing) */
  prompt: string;
  /** Estimated cost of this call in dollars */
  estimatedCostDollars: number;
}

export type GovernorDecision =
  | { allowed: true; cached: false }
  | { allowed: true; cached: true; cachedResult: string }
  | { allowed: false; reason: "spend_limit" | "volume_limit" | "lifetime_limit" | "circuit_breaker" };

// ── Layer 6: Access Control ─────────────────────────────────────────

export interface PathCheckResult {
  allowed: boolean;
  reason?: string;
}

export interface UrlCheckResult {
  allowed: boolean;
  reason?: string;
  /** Resolved IP addresses — use these for the actual connection (C-2 DNS pinning) */
  resolvedIps?: string[];
}

export interface AccessControlConfig {
  /** Directories that file paths must stay within */
  allowedDirectories: string[];
  /** Additional filenames to deny (beyond built-in list) */
  extraDenyFilenames?: string[];
  /** Additional extensions to deny (beyond built-in list) */
  extraDenyExtensions?: string[];
}
