# Defense System Reference

> Authoritative reference for the 6-layer prompt injection defense system.
> For quick overview, see the Defense System section in CLAUDE.md.
> For deployment status and operational notes, see MEMORY.md.

## Motivation

A vanilla OpenClaw install has no app-level defense against prompt injection. The model's own safety training is the only barrier between untrusted input and tool execution. Our infrastructure hardening (systemd sandbox, auditd, egress filtering, 4-layer tool permissions) provides strong kernel-level containment, but nothing inspects or sanitizes content before it reaches the LLM or after the LLM generates a response.

This system fills that gap with a 6-layer defense architecture based on [Matthew Berman's design](https://x.com/MatthewBerman/status/2030423565355676100), informed by studying real attack techniques from Pliny the Prompter's repositories:

- **L1B3RT4S** -- jailbreak catalog: system prompt overrides, role injection patterns
- **P4RS3LT0NGV3** -- 79+ encoding evasion techniques: base64, hex, ROT13, Unicode tricks
- **TOKEN80M8/TOKENADE** -- wallet-draining payloads: ETH, BTC, Tron address injection

## Architecture

The defense system runs as a native OpenClaw plugin, hooking into 5 gateway events.

```
                     OpenClaw Gateway (:18789)
                              |
  ┌──────────────────────────���┼───────────────────────────────┐
  │                    Plugin Hook Runner                      │
  │                                                            │
  │  ┌─ message_received (void) ────────────────────────────┐  │
  │  │  L1: Sanitizer → block if highSeverity + threshold   │  │
  │  └──────────────────────────────────────────────────────┘  │
  │                           │                                │
  │  ┌─ llm_input (void) ──────────────────────────────────┐  │
  │  │  L5: Governor tracking → log spend/volume warnings   │  │
  │  └──────────────────────────────────────────────────────┘  │
  │                           │                                │
  │          ~~~~~~~~ LLM processes input ~~~~~~~~             │
  │                           │                                │
  │  ┌─ llm_output (void) ─────────────────────────────────┐  │
  │  │  L3+L4: Audit gate → log violations in raw response  │  │
  │  └──────────────────────────────────────────────────────┘  │
  │                           │                                │
  │  ┌─ before_tool_call (modifying) ──────────────────────┐  │
  │  │  L6: Access control → block sensitive paths/URLs     │  │
  │  └──────────────────────────────────────────────────────┘  │
  │                           │                                │
  │  ┌─ message_sending (modifying) ───────────────────────┐  │
  │  │  L3: Gate + L4: Redaction → modify/cancel outbound   │  │
  │  └──────────────────────────────────────────────────────┘  │
  │                                                            │
  └────────────────────────────────────────────────────────────┘
                              │
                    Response delivered to user
```

### Hook-to-Layer Mapping

| Hook | Type | Layers | What It Does |
|------|------|--------|-------------|
| `message_received` | void (fire-and-forget) | L1, L2 | L1: sanitizes inbound text (always). L2: LLM scanner fires conditionally on high-risk (non-Telegram) channels when L1 detects something but doesn't auto-block. Auto-activates via plugin runtime when Anthropic auth is available. |
| `message_sending` | modifying (sequential) | L3, L4 | Gates outbound content, redacts secrets/PII before delivery, can cancel |
| `before_tool_call` | modifying (sequential) | L6 | Checks file paths and URLs against access control, blocks denied |
| `llm_input` | void (fire-and-forget) | L5 | Tracks spend/volume via governor, logs rate limit warnings |
| `llm_output` | void (fire-and-forget) | L3, L4 | Audits raw LLM response for violations (catches tool-generated content) |

## Layer Details

### L1: Deterministic Text Sanitizer

**File:** `src/defense/layer1-sanitizer.ts`
**Type:** Synchronous, instant, zero API cost
**Input limit:** 100KB (ReDoS prevention)

Detections and sanitizations performed:

| Category | What It Does | Pattern Count |
|----------|-------------|---------------|
| Unicode normalization | NFKC normalization + manual homoglyph map | ~50 homoglyphs |
| Base64 decoding | Detects and decodes base64 and base64url payloads | 2 variants |
| Hex decoding | Flexible delimiter support (0x, \x, space, colon) | 4 delimiters |
| ROT13 detection | Detects ROT13-encoded text with common trigger words | Decode + detect |
| HTML/Markdown stripping | Removes injected HTML tags and markdown formatting | Tag patterns |
| System prompt overrides | Detects "ignore previous instructions" and variants | 16 patterns |
| Role injection | Detects fake assistant/system/user role markers | 8 patterns |
| Zero-width characters | Removes U+200B, U+200C, U+200D, U+FEFF, etc. | Unicode ranges |
| Emoji steganography | Detects variation selectors used to hide data in emoji | VS15/VS16 |
| Unicode PUA | Detects hidden text in Private Use Area (U+E0000-U+E007F) | Tag range |
| Zalgo abuse | Detects excessive combining diacritical marks | Threshold-based |
| Whitespace steganography | Detects space/tab binary encoding patterns | Ratio analysis |
| Wallet addresses | Flags ETH (0x...), BTC (1/3/bc1...), Tron (T...) addresses | 3 patterns |

**Output:** `SanitizerResult` with cleaned text, per-category stats, totalDetections count, and highSeverity flag.

**Key property:** If `highSeverity && totalDetections > AUTO_BLOCK_THRESHOLD` (default 5), the combined `scanInput()` function blocks without calling L2, saving LLM cost.

### L2: LLM Frontier Scanner

**File:** `src/defense/layer2-scanner.ts`
**Type:** Asynchronous, requires one LLM API call
**Security:** Nonce-delimited classification prompt using `crypto.randomUUID()` to prevent prompt injection against the classifier itself.

The scanner sends a dedicated classification prompt to the LLM with the input text wrapped in unique nonce delimiters. The LLM returns structured JSON:

```typescript
interface ScannerResult {
  verdict: "allow" | "review" | "block";
  score: number;        // 0-100 risk score
  categories: AttackCategory[];  // prompt_injection, jailbreak, encoding_evasion, etc.
  reasoning: string;    // Human-readable explanation
  evidence: string[];   // Suspicious fragments
  overridden: boolean;  // Whether score-verdict logic changed the LLM's verdict
}
```

**Symmetric score-verdict override:** If the LLM says "allow" but score >= 70, verdict becomes "review". If score >= 90, verdict becomes "block". Conversely, if the LLM says "block" but score < 30, verdict becomes "review". This prevents both false negatives and false positives from LLM judgment errors.

**Error handling:** On LLM call failure, blocks high-risk sources and allows low-risk sources (fail-closed for untrusted input, fail-open for trusted).

**Integration:** Decoupled via `llmCall` function in `ScannerConfig` -- integrators provide their own LLM calling function, choosing model and provider.

### L3: Outbound Content Gate

**File:** `src/defense/layer3-outbound.ts`
**Type:** Synchronous, instant, zero API cost
**Shared patterns:** Uses `patterns.ts` for secret detection (18 API key/token patterns)

Checks performed on LLM response text before delivery:

| Check | What It Catches | Action |
|-------|----------------|--------|
| Leaked secrets | 18 API key patterns (Anthropic, OpenAI, GitHub, AWS, Google, Slack, npm, PyPI, SendGrid, Stripe, Bearer tokens, PEM keys/certs) | Redact with `[REDACTED: type]` |
| Internal paths | Unix absolute paths, Windows any-drive paths, UNC paths | Redact with `[REDACTED: internal path]` |
| Injection artifacts | Expanded verb forms of prompt manipulation ("ignore all previous", etc.) | Redact with `[REDACTED: injection artifact]` |
| Exfil URLs | Embedded image URLs and tracking pixels for data exfiltration | Redact with `[REDACTED: exfil URL]` |
| Financial data | Credit card numbers, IBAN, SSN | Redact with `[REDACTED: financial data]` |

**Key property:** All violation types are redacted, not just detected. The gate returns cleaned text with type-specific redaction markers.

### L4: Redaction Pipeline

**File:** `src/defense/layer4-redaction.ts`
**Type:** Synchronous, instant, chained single-pass pipeline
**Shared patterns:** Uses `patterns.ts` for API key patterns (global flag for replace-all)

Redaction categories:

| Category | Coverage | Replacement |
|----------|---------|-------------|
| API keys/tokens | All 18 patterns from patterns.ts | `[REDACTED: API_KEY]` |
| Personal emails | 50+ provider domains (gmail, yahoo, outlook, proton, etc.) | `[REDACTED: EMAIL]` |
| Work emails | Preserved (including subdomain matches like `team.company.com`) | Not redacted |
| Phone numbers | US format + international with country codes | `[REDACTED: PHONE]` |
| Dollar amounts | `$X`, `$X.XX`, `$X,XXX.XX` formats | `[REDACTED: AMOUNT]` |

**Configuration:** `RedactionConfig.workDomains` -- array of email domains to preserve (work emails pass through unredacted).

### L5: Call Governor

**File:** `src/defense/layer5-governor.ts`
**Type:** Synchronous, stateful (in-memory), per-request check
**Clock:** Uses `performance.now()` (monotonic) to prevent system clock manipulation.

Controls:

| Control | Default | Purpose |
|---------|---------|---------|
| Spend limit | $50/hour | Rolling window, blocks when cumulative estimated cost exceeds limit |
| Volume limit | 500/hour | Rolling window, per-caller overrides via `callerOverrides` map |
| Lifetime limit | 10,000 | Absolute maximum calls per process lifetime |
| Duplicate detection | 5 min TTL | SHA-256 hash of callerId + prompt, caller-scoped to prevent cross-caller cache poisoning |
| Circuit breaker | 10 rejections/60s | Auto-blocks a caller after N rejections within window |

**Caller scoping (CRITICAL fix):** Dedup cache keys include callerId to prevent one caller from poisoning another caller's cache. Without this, an attacker could pre-populate cache entries that would be served to legitimate callers.

**State:** In-memory only. Resets on process restart. Acceptable tradeoff -- governor rebuilds state from live traffic within one rolling window period.

### L6: Access Control

**File:** `src/defense/layer6-access.ts`
**Type:** Synchronous (paths) + Asynchronous (URLs, due to DNS resolution)

**Path guards:**

- 30+ denied filenames: `.env`, `.git/config`, `id_rsa`, `shadow`, `passwd`, `authorized_keys`, `.aws/credentials`, `.docker/config.json`, `openclaw.json`, `auth-profiles.json`, `known_hosts`, etc.
- 18 denied extensions: `.pem`, `.key`, `.p12`, `.pfx`, `.jks`, `.keystore`, `.sqlite`, `.db`, `.sql`, `.dump`, etc.
- Directory containment: paths must resolve within allowed directories (no `../` escape)

**URL safety:**

- Scheme validation: only `http://` and `https://` allowed
- Private IP detection for IPv4: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16
- Private IP detection for IPv6: ::1, fe80::/10, fc00::/7, 2001:db8::/32 (RFC 3849 documentation prefix), ff00::/8 (multicast)
- DNS resolution with 3-second timeout
- Returns resolved IP addresses for DNS pinning (prevents TOCTOU attacks where DNS changes between check and connection)

## STRIDE Threat Model Summary

A STRIDE analysis was performed on the defense system. All findings were fixed before completion.

### Critical (3 fixed)

1. **L2 nonce delimiter injection** -- An attacker could inject the nonce delimiter into input text to break out of the classification sandbox. Fixed: nonce generated with `crypto.randomUUID()` per request, making prediction infeasible.
2. **L6 DNS pinning TOCTOU** -- DNS could resolve to a safe IP during check but a malicious IP during actual connection. Fixed: `checkUrl()` returns `resolvedIps[]` for the caller to pin the connection to.
3. **L5 cross-caller cache poisoning** -- Dedup cache was keyed on prompt hash alone; one caller could poison another's cache. Fixed: cache keys include callerId (SHA-256 of callerId + prompt).

### High (7 fixed)

- 4 new encoding detectors added: emoji steganography, Unicode PUA, Zalgo diacritical abuse, whitespace steganography
- ROT13 sanitization (was detect-only, now decodes)
- Base64url variant support
- Circuit breaker added to L5 governor
- Audit entry types expanded
- ExternalScanResult type added (strips internal details from untrusted callers)
- Solana address pattern removed (too many false positives)

### Medium (6 fixed)

- Symmetric score-verdict override in L2
- Windows and UNC path detection in L3
- IPv6 private ranges including RFC 3849 documentation prefix
- Email subdomain matching for work domains
- DNS timeout (3 seconds) to prevent slow-resolution DoS
- Monotonic clock (performance.now()) to prevent system clock manipulation

### Low (4 fixed)

- Whitespace normalization threshold tuning
- Injection artifact pattern expansion
- Hex delimiter flexibility
- Exfiltration URL pattern expansion

## Known Limitations

1. **Cryptocurrency address false positives** -- ETH (0x + 40 hex chars), BTC, and Tron patterns can match non-address strings. Solana pattern was removed entirely due to excessive false positives. Current patterns flag but do not block.
2. **L2 scanner conditional on channel trust** -- L2 (LLM scanner) is wired into the `message_received` hook but fires only on untrusted channels (email, webhooks, pipeline, web — not Telegram paired DMs) and only when L1 found detections > 0 but didn't auto-block. Auto-activates via plugin runtime when Anthropic auth is available. Adds 200-800ms latency and ~$0.001 per call when it fires.
3. **L5 governor is informational** -- The `llm_input` hook is void (fire-and-forget), so the governor can track but not block. It logs warnings when limits would be exceeded. Use external spend monitoring for hard limits.
4. **L5 state is ephemeral** -- Governor state resets on process restart. Acceptable because rolling windows rebuild from live traffic.

## Test Coverage

162 tests across 6 test files. All passing.

| Test File | Tests | Coverage |
|-----------|-------|----------|
| layer1.test.ts | ~40 | Unicode, encoding, injection patterns, steganography, wallets |
| layer2.test.ts | ~20 | Classification, nonce security, score override, error handling |
| layer3.test.ts | ~30 | Secrets, paths, injection artifacts, exfil URLs, financial data |
| layer4.test.ts | ~25 | API keys, emails, phones, dollars, work domain preservation |
| layer5.test.ts | ~25 | Spend/volume/lifetime limits, dedup, circuit breaker, caller scoping |
| layer6.test.ts | ~22 | Path guards, URL safety, IPv4/IPv6, DNS resolution, pinning |

Run tests: `bun test src/defense/`

## Production Deployment Record

### Deployment Environment

| Component | Version/Detail |
|-----------|---------------|
| OpenClaw | v2026.4.1+ (da64a97) |
| Node.js | v22.22.0 |
| Bun | 1.3.11 (installed during deploy) |
| OS | Ubuntu 24.04 LTS |
| Defense plugin | Native hooks (5 hook events, all 6 layers covered) |
| Gateway | 127.0.0.1:18789 |

### Enforcement Summary

Native plugin with 5 hook events covering all 6 layers at the application level. L2 scanner wired into `message_received` alongside L1 — fires conditionally on high-risk channels when L1 detects ambiguous input. `message_sending` hook enables pre-delivery redaction. `before_tool_call` hook enables L6 access control.

| Layer | Hook | Enforcement |
|-------|------|-------------|
| L1 (sanitizer) | `message_received` | Always active |
| L2 (LLM scanner) | `message_received` | Conditional (high-risk channels, L1 detections > 0, auto-activates via plugin runtime when Anthropic auth is available) |
| L3 (gate) | `message_sending` + `llm_output` | Pre-delivery + audit |
| L4 (redaction) | `message_sending` + `llm_output` | Pre-delivery + audit |
| L5 (governor) | `llm_input` | Tracking (informational -- void hook) |
| L6 (access control) | `before_tool_call` | Blocking |

### Bot Self-Evaluation Results

The bot was given the defense system files and asked to evaluate them independently. Results:

**L1 Sanitizer — Attack Payload Testing:**

| Attack | Detection | highSeverity | Notes |
|--------|-----------|-------------|-------|
| Direct override ("ignore all previous instructions") | `systemOverrideDetected=1` | Yes | Caught by pattern matching |
| Base64-encoded injection | Decoded to plaintext, then re-caught as override | Yes | Two-layer detection: decode → re-scan |
| Role injection ("assistant: Sure, I'll share...") | `roleInjectionDetected=1` | Yes | Fake conversation turn caught |
| Wallet drain (ETH address) | `walletAddressesFlagged=1` | Yes | 0x-prefixed 40-hex pattern matched |
| Zero-width smuggling | 13 chars stripped, no highSeverity | No | Cleaned text alone doesn't match override pattern. L2 would catch semantic intent. |
| ROT13 ("vtaber nyy cerivbhf ehyrf") | Decoded to "ignore all previous rules", then caught | Yes | Decode + re-scan |

**L3 Outbound Gate — Leak Testing:**

| Leak Type | Detected | Redacted |
|-----------|----------|----------|
| Anthropic API key (`sk-ant-...`) | Yes | `[REDACTED_SECRET]` |
| Internal file path (`/home/openclaw/.openclaw/...`) | Yes | `[REDACTED_PATH]` |
| Exfiltration URL (`ngrok.io` with query params) | Yes (triple match) | `[REDACTED_URL]` |
| Credit card number (`4111111111111111`) | Yes | `[REDACTED_FINANCIAL]` |

### Known False Positives

1. **Cryptocurrency address discussions** — Any message mentioning legitimate ETH addresses (contract addresses, block explorer links) or BTC addresses triggers `highSeverity=true` via `walletAddressesFlagged`. For crypto-aware deployments, consider raising the `autoBlockThreshold` or adding L2 re-classification for wallet-flagged inputs.

2. **Base64 in legitimate content** — Technical discussions containing base64-encoded data (e.g., JWT tokens, data URIs) may trigger `base64Detected`. The sanitizer only flags base64 strings that decode to printable ASCII text ≥8 chars, which reduces false positives but doesn't eliminate them.

3. **Code snippets with injection patterns** — Messages containing example code like `"assistant:"` or `[SYSTEM]` markers (e.g., discussing LLM prompt formats) trigger role injection and injection artifact detection. This is by design — the defense can't distinguish discussion-about-injection from actual injection without semantic understanding (which is L2's job).

### Current Operational State (as of deployment)

- `openclaw` service active with defense plugin loaded
- Governor state: 0 lifetime calls (freshly deployed)
- Audit logging enabled (stderr → journald)
- First production traffic expected on next cron heartbeat (every 30m)

## File Inventory

| File | Purpose |
|------|---------|
| `src/defense/layer1-sanitizer.ts` | L1: Deterministic text sanitizer |
| `src/defense/layer2-scanner.ts` | L2: LLM frontier scanner |
| `src/defense/layer3-outbound.ts` | L3: Outbound content gate |
| `src/defense/layer4-redaction.ts` | L4: Redaction pipeline |
| `src/defense/layer5-governor.ts` | L5: Call governor |
| `src/defense/layer6-access.ts` | L6: Access control |
| `src/defense/patterns.ts` | Shared API key/secret patterns (18 definitions) |
| `src/defense/types.ts` | Shared TypeScript types for all layers |
| `src/defense/index.ts` | Entry point: scanInput(), re-exports all layers |
| `src/defense/__tests__/*.test.ts` | 162 tests across 6 files |
| `src/defense/plugin/index.ts` | Plugin registration: wires 5 hook events (all 6 layers) into OpenClaw |
| `src/defense/plugin/hooks.ts` | Hook handler factories for all 5 event types (L1+L2 share `message_received`) |
| `src/defense/plugin/types.ts` | Plugin-specific type definitions |
| `src/defense/plugin/package.json` | Plugin package manifest |
| `src/defense/proxy/` | Defense proxy (inactive, code preserved in repo) |
| `Reference/DEFENSE-SYSTEM.md` | This file (authoritative reference) |
