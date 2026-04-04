/**
 * Layer 6: Access Control
 *
 * Two mechanisms:
 * 1. Path guards — deny list of sensitive filenames and extensions,
 *    enforce that file paths stay within allowed directories
 * 2. URL safety — only allow http/https, check that hostnames don't
 *    resolve to internal or private network addresses
 */

import type {
  PathCheckResult,
  UrlCheckResult,
  AccessControlConfig,
} from "./types";
import { resolve, basename, extname } from "node:path";
import { resolve4 } from "node:dns/promises";

// ── Path Guard ───────────────────────────────────────────────────────

/** Sensitive filenames that should never be accessible */
const DENY_FILENAMES = new Set([
  ".env",
  ".env.local",
  ".env.production",
  ".env.development",
  ".env.staging",
  ".env.test",
  ".htpasswd",
  ".htaccess",
  ".npmrc",
  ".pypirc",
  ".netrc",
  ".gitconfig",
  ".git-credentials",
  "id_rsa",
  "id_ed25519",
  "id_ecdsa",
  "id_dsa",
  "authorized_keys",
  "known_hosts",
  "shadow",
  "passwd",
  "sudoers",
  "master.key",
  "credentials.yml.enc",
  "database.yml",
  "secrets.yml",
  "secrets.json",
  "service-account.json",
  "keystore.jks",
  "truststore.jks",
  ".docker/config.json",
  "kubeconfig",
  "terraform.tfstate",
  "terraform.tfvars",
  "vault-token",
]);

/** Sensitive file extensions */
const DENY_EXTENSIONS = new Set([
  ".pem",
  ".key",
  ".p12",
  ".pfx",
  ".jks",
  ".keystore",
  ".cer",
  ".crt",
  ".der",
  ".pkcs12",
  ".pkcs8",
  ".kdb",
  ".kdbx",      // KeePass databases
  ".asc",       // GPG keys
  ".gpg",
  ".pgp",
  ".sqlite",    // Could contain credentials
  ".db",        // Depending on context
]);

/**
 * Check if a file path is allowed.
 * - Must resolve within one of the allowed directories
 * - Must not match deny-listed filenames or extensions
 */
export function checkPath(
  filePath: string,
  config: AccessControlConfig
): PathCheckResult {
  // Resolve to absolute path to prevent traversal
  const resolved = resolve(filePath);
  const name = basename(resolved);
  const ext = extname(resolved).toLowerCase();

  // Check deny-listed filenames
  const allDenyFilenames = new Set(
    Array.from(DENY_FILENAMES).concat(config.extraDenyFilenames ?? [])
  );
  if (allDenyFilenames.has(name)) {
    return { allowed: false, reason: `Denied filename: ${name}` };
  }

  // Check deny-listed extensions
  const allDenyExtensions = new Set(
    Array.from(DENY_EXTENSIONS).concat(config.extraDenyExtensions ?? [])
  );
  if (ext && allDenyExtensions.has(ext)) {
    return { allowed: false, reason: `Denied extension: ${ext}` };
  }

  // Check directory containment
  const withinAllowed = config.allowedDirectories.some((allowedDir) => {
    const resolvedDir = resolve(allowedDir);
    return resolved.startsWith(resolvedDir + "/") || resolved === resolvedDir;
  });

  if (!withinAllowed) {
    return {
      allowed: false,
      reason: `Path ${resolved} is outside allowed directories`,
    };
  }

  return { allowed: true };
}

// ── URL Safety ───────────────────────────────────────────────────────

/**
 * Private/internal IP ranges per RFC 1918, RFC 5737, RFC 4193, RFC 6598.
 * These must never be resolved to by external URLs.
 */
function isPrivateIp(ip: string): boolean {
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some((p) => isNaN(p) || p < 0 || p > 255)) {
    // Could be IPv6 — check common private IPv6 patterns
    const lower = ip.toLowerCase();
    return (
      lower === "::1" ||                          // IPv6 loopback
      lower.startsWith("fc") ||                   // RFC 4193 unique local
      lower.startsWith("fd") ||                   // RFC 4193 unique local
      lower.startsWith("fe80:") ||                // Link-local
      lower === "::ffff:127.0.0.1" ||            // IPv4-mapped loopback
      lower.startsWith("::ffff:10.") ||          // IPv4-mapped private
      lower.startsWith("::ffff:192.168.") ||     // IPv4-mapped private
      lower.startsWith("::ffff:172.")            // IPv4-mapped private (partial)
    );
  }

  const a = parts[0]!;
  const b = parts[1]!;
  const c = parts[2]!;
  return (
    a === 10 ||                                    // 10.0.0.0/8 (RFC 1918)
    (a === 172 && b >= 16 && b <= 31) ||          // 172.16.0.0/12 (RFC 1918)
    (a === 192 && b === 168) ||                   // 192.168.0.0/16 (RFC 1918)
    a === 127 ||                                   // 127.0.0.0/8 (loopback)
    (a === 169 && b === 254) ||                   // 169.254.0.0/16 (link-local)
    a === 0 ||                                     // 0.0.0.0/8
    (a === 100 && b >= 64 && b <= 127) ||         // 100.64.0.0/10 (RFC 6598 CGN)
    (a === 192 && b === 0 && c === 2) ||          // 192.0.2.0/24 (RFC 5737 TEST-NET-1)
    (a === 198 && b === 51 && c === 100) ||       // 198.51.100.0/24 (RFC 5737 TEST-NET-2)
    (a === 203 && b === 0 && c === 113) ||        // 203.0.113.0/24 (RFC 5737 TEST-NET-3)
    (a >= 224)                                     // 224.0.0.0+ (multicast + reserved)
  );
}

/** Hostnames that are always localhost/internal */
const LOCALHOST_HOSTNAMES = new Set([
  "localhost",
  "localhost.localdomain",
  "ip6-localhost",
  "ip6-loopback",
  "0.0.0.0",
  "127.0.0.1",
  "::1",
  "[::1]",
]);

/**
 * Check if a URL is safe to access.
 * - Only http:// and https:// schemes allowed
 * - Hostname must not resolve to private/internal IP
 * - Hostname must not be localhost/loopback
 *
 * DNS resolution is async because Bun.dns.resolve() is async.
 */
export async function checkUrl(url: string): Promise<UrlCheckResult> {
  // Parse URL
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return { allowed: false, reason: `Invalid URL: ${url}` };
  }

  // Scheme check
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return {
      allowed: false,
      reason: `Disallowed scheme: ${parsed.protocol} (only http/https allowed)`,
    };
  }

  // Hostname check — static localhost/loopback
  const hostname = parsed.hostname.toLowerCase();
  if (LOCALHOST_HOSTNAMES.has(hostname)) {
    return {
      allowed: false,
      reason: `Hostname ${hostname} is localhost/loopback`,
    };
  }

  // Check if hostname is a literal IP
  if (isPrivateIp(hostname)) {
    return {
      allowed: false,
      reason: `IP address ${hostname} is private/internal`,
    };
  }

  // DNS resolution check — resolve hostname and check all IPs
  try {
    // Try to resolve the hostname
    const addresses = await resolveHostname(hostname);
    for (const addr of addresses) {
      if (isPrivateIp(addr)) {
        return {
          allowed: false,
          reason: `Hostname ${hostname} resolves to private IP ${addr}`,
        };
      }
    }
  } catch {
    // DNS resolution failed — conservative: allow (might be offline or new domain)
    // The caller can decide to block on resolution failure based on context
  }

  return { allowed: true };
}

/**
 * Resolve hostname to IPv4 addresses.
 * Uses node:dns/promises for compatibility.
 */
async function resolveHostname(hostname: string): Promise<string[]> {
  try {
    return await resolve4(hostname);
  } catch {
    return [];
  }
}

// Exports for testing
export const _internals = {
  DENY_FILENAMES,
  DENY_EXTENSIONS,
  isPrivateIp,
  LOCALHOST_HOSTNAMES,
};
