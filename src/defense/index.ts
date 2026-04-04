/**
 * Prompt Injection Defense System — 6-Layer Architecture
 *
 * Entry point that chains all layers and provides the scanInput() function
 * combining Layer 1 (deterministic sanitizer) and Layer 2 (LLM frontier scanner).
 *
 * Layer 1: Deterministic text sanitizer (sync, instant)
 * Layer 2: LLM-based frontier scanner (async, requires LLM call)
 * Layer 3: Outbound content gate (sync, pattern matching)
 * Layer 4: Redaction pipeline (sync, chained filters)
 * Layer 5: Call governor (sync, in-memory state)
 * Layer 6: Access control (path: sync, URL: async for DNS)
 */

import { sanitize } from "./layer1-sanitizer";
import { scan } from "./layer2-scanner";
import { gate } from "./layer3-outbound";
import { redact } from "./layer4-redaction";
import { createGovernor, CallGovernor } from "./layer5-governor";
import { checkPath, checkUrl } from "./layer6-access";

import type {
  SanitizerResult,
  ScannerResult,
  ScannerConfig,
  InputScanResult,
  OutboundGateResult,
  RedactionResult,
  RedactionConfig,
  GovernorConfig,
  GovernorCallRequest,
  GovernorDecision,
  PathCheckResult,
  UrlCheckResult,
  AccessControlConfig,
  ScanVerdict,
} from "./types";

// ── Combined Entry Point: L1 + L2 ───────────────────────────────────

/**
 * Threshold for auto-blocking by sanitizer alone.
 * If total detections exceed this, L2 scanner is skipped.
 */
const AUTO_BLOCK_THRESHOLD = 5;

/**
 * Combined input scanning: Layer 1 sanitization → Layer 2 classification.
 *
 * If L1 detects high-severity patterns above the auto-block threshold,
 * the input is blocked without invoking L2 (saves LLM cost).
 *
 * @param input - Raw untrusted input text
 * @param scannerConfig - L2 scanner config (LLM call function + source risk)
 * @returns Combined result from both layers with final verdict
 */
export async function scanInput(
  input: string,
  scannerConfig: ScannerConfig
): Promise<InputScanResult> {
  // Layer 1: Deterministic sanitization (always runs)
  const sanitizerResult = sanitize(input);

  // Auto-block if sanitizer found overwhelming evidence
  if (sanitizerResult.highSeverity && sanitizerResult.totalDetections > AUTO_BLOCK_THRESHOLD) {
    return {
      sanitizer: sanitizerResult,
      scanner: null,
      finalVerdict: "block",
      blockedBySanitizer: true,
    };
  }

  // Layer 2: LLM frontier scanner on the cleaned text
  const scannerResult = await scan(sanitizerResult.cleaned, scannerConfig);

  // Final verdict: take the more restrictive of L1 inference and L2 verdict
  let finalVerdict: ScanVerdict = scannerResult.verdict;
  if (sanitizerResult.highSeverity && finalVerdict === "allow") {
    finalVerdict = "review";
  }

  return {
    sanitizer: sanitizerResult,
    scanner: scannerResult,
    finalVerdict,
    blockedBySanitizer: false,
  };
}

// ── Re-exports ───────────────────────────────────────────────────────

export {
  // Layer 1
  sanitize,
  // Layer 2
  scan,
  // Layer 3
  gate,
  // Layer 4
  redact,
  // Layer 5
  createGovernor,
  CallGovernor,
  // Layer 6
  checkPath,
  checkUrl,
};

// Re-export types
export type {
  SanitizerResult,
  ScannerResult,
  ScannerConfig,
  InputScanResult,
  OutboundGateResult,
  RedactionResult,
  RedactionConfig,
  GovernorConfig,
  GovernorCallRequest,
  GovernorDecision,
  PathCheckResult,
  UrlCheckResult,
  AccessControlConfig,
  ScanVerdict,
};
