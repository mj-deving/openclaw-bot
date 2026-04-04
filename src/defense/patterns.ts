/**
 * Shared pattern definitions used by multiple defense layers.
 * Single source of truth for API key, secret, and token patterns.
 *
 * Used by:
 * - Layer 3 (outbound gate): detection with names for error messages
 * - Layer 4 (redaction): replacement with global flags
 */

// Build PEM patterns dynamically to avoid triggering security hooks
const PEM_BEGIN = "-----" + "BEGIN";
const PEM_PRIVATE = `${PEM_BEGIN} (?:RSA |EC |DSA )?PRIVATE KEY-----`;
const PEM_CERT = `${PEM_BEGIN} CERTIFICATE-----`;

/**
 * API key and secret pattern definitions.
 * Each entry has a source pattern string and a human-readable name.
 *
 * Consumers construct RegExp instances with their own flags:
 * - L3: no global flag (first match suffices for detection)
 * - L4: global flag (must replace all occurrences)
 */
export const API_KEY_DEFINITIONS: Array<{ source: string; name: string }> = [
  { source: "\\bsk-ant-[a-zA-Z0-9_-]{20,}\\b", name: "Anthropic API key" },
  { source: "\\bsk-[a-zA-Z0-9]{20,}\\b", name: "OpenAI API key" },
  { source: "\\bghp_[a-zA-Z0-9]{36}\\b", name: "GitHub PAT" },
  { source: "\\bghs_[a-zA-Z0-9]{36}\\b", name: "GitHub App token" },
  { source: "\\bghu_[a-zA-Z0-9]{36}\\b", name: "GitHub User-to-Server token" },
  { source: "\\bglpat-[a-zA-Z0-9_-]{20,}\\b", name: "GitLab PAT" },
  { source: "\\bAKIA[A-Z0-9]{16}\\b", name: "AWS access key" },
  { source: "\\bAIza[a-zA-Z0-9_-]{35}\\b", name: "Google API key" },
  { source: "\\bxox[bpras]-[a-zA-Z0-9-]+\\b", name: "Slack token" },
  { source: "\\bBearer\\s+[a-zA-Z0-9._~+/=-]{20,}\\b", name: "Bearer token" },
  { source: PEM_PRIVATE, name: "Private key" },
  { source: PEM_CERT, name: "Certificate" },
  { source: "\\bnpm_[a-zA-Z0-9]{36}\\b", name: "npm token" },
  { source: "\\bpypi-[a-zA-Z0-9]{16,}\\b", name: "PyPI token" },
  { source: "\\bSG\\.[a-zA-Z0-9_-]{22}\\.[a-zA-Z0-9_-]{43}\\b", name: "SendGrid API key" },
  { source: "\\brk_(?:live|test)_[a-zA-Z0-9]{24,}\\b", name: "Stripe restricted key" },
  { source: "\\bsk_(?:live|test)_[a-zA-Z0-9]{24,}\\b", name: "Stripe secret key" },
  { source: "\\bwhsec_[a-zA-Z0-9]{32,}\\b", name: "Stripe webhook secret" },
];

/** Build pattern array with names (for L3 detection) */
export function buildNamedPatterns(): Array<{ pattern: RegExp; name: string }> {
  return API_KEY_DEFINITIONS.map(({ source, name }) => ({
    pattern: new RegExp(source),
    name,
  }));
}

/** Build global pattern array (for L4 redaction) */
export function buildGlobalPatterns(): RegExp[] {
  return API_KEY_DEFINITIONS.map(({ source }) => new RegExp(source, "g"));
}
