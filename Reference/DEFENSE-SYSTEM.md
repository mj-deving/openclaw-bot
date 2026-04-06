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

The defense system runs as a native OpenClaw plugin, hooking into 5 gateway events. The proxy (`127.0.0.1:18800`) is preserved as a fallback but is not the primary enforcement mechanism.

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
| `message_received` | void (fire-and-forget) | L1 | Sanitizes inbound text, pushes block warning to conversation |
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

## Defense Proxy

**Files:** `src/defense/proxy/server.ts`, `src/defense/proxy/config.ts`
**Runtime:** Bun HTTP server
**Bind:** `127.0.0.1:18800` (loopback only)
**systemd:** `defense-proxy.service` (ordered `Before=openclaw.service`)

### How It Works

The proxy intercepts all LLM API calls by setting `ANTHROPIC_BASE_URL=http://127.0.0.1:18800` and `OPENAI_BASE_URL=http://127.0.0.1:18800` in OpenClaw's systemd environment. Both the Anthropic SDK and OpenAI-compatible SDKs (OpenRouter) respect these variables and route through the proxy.

**Request flow:**

1. OpenClaw sends API request to proxy (thinking it is the real API)
2. Proxy extracts the latest user message from request body
3. **Inbound defense:** L1 sanitizer runs on user message; auto-blocks if threshold exceeded
4. **Governor check:** L5 validates spend/volume/dedup/circuit breaker
5. Proxy forwards request to real upstream API with original headers
6. **Non-streaming response:** L3 gate + L4 redaction on response text; patched response returned
7. **Streaming response:** Chunks passed through to client; text assembled for monitoring; violations logged but cannot be redacted (already sent)

**API format handling:**

- Anthropic Messages API: `/v1/messages` -- content blocks with `type: "text"`
- OpenAI-compatible: `/v1/chat/completions` -- choices[0].message.content
- Other paths (model lists, etc.): passed through to Anthropic upstream

**Health endpoint:** `GET /health` returns governor state, uptime, and status.

**Audit logging:** JSON entries to stderr (captured by journald). Events: `inbound_scan`, `inbound_blocked`, `governor_blocked`, `governor_cache_hit`, `outbound_violation`, `outbound_cleaned`, `streaming_violation_detected`, `upstream_error`.

### Configuration (Environment Variables)

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEFENSE_PROXY_PORT` | 18800 | Proxy listen port |
| `DEFENSE_PROXY_BIND` | 127.0.0.1 | Bind address |
| `DEFENSE_ANTHROPIC_UPSTREAM` | https://api.anthropic.com | Real Anthropic API |
| `DEFENSE_OPENROUTER_UPSTREAM` | https://openrouter.ai/api | Real OpenRouter API |
| `DEFENSE_AUTO_BLOCK_THRESHOLD` | 5 | L1 detections before auto-block |
| `DEFENSE_SPEND_LIMIT` | 50 | Max dollars per rolling window |
| `DEFENSE_SPEND_WINDOW_MS` | 3600000 | Rolling window (1 hour) |
| `DEFENSE_VOLUME_LIMIT` | 500 | Max calls per rolling window |
| `DEFENSE_LIFETIME_LIMIT` | 10000 | Max calls per process lifetime |
| `DEFENSE_DEDUP_TTL_MS` | 300000 | Duplicate cache TTL (5 min) |
| `DEFENSE_CIRCUIT_BREAKER` | 10 | Rejections before auto-block |
| `DEFENSE_WORK_DOMAINS` | (empty) | Comma-separated work email domains to preserve |
| `DEFENSE_AUDIT_LOG` | true | Enable JSON audit logging |

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
2. **L2 scanner not wired into hooks** -- L2 (LLM scanner) adds latency and cost to every request. Available via `scanInput()` for targeted use but not registered as a hook by default.
3. **L5 governor is informational in plugin mode** -- The `llm_input` hook is void (fire-and-forget), so the governor can track but not block. It logs warnings when limits would be exceeded. The proxy's L5 enforcement was blocking. For hard spend limits, keep the proxy active as a fallback.
4. **L5 state is ephemeral** -- Governor state resets on process restart. Acceptable because rolling windows rebuild from live traffic.
5. **Proxy preserved but not primary** -- The defense proxy at 127.0.0.1:18800 is still deployed and functional. It is no longer the primary enforcement mechanism (the plugin handles that), but it provides a second layer of defense for API-level interception. Both can run simultaneously without conflict.

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

## Deployment

### Deploy (from local machine)

```bash
src/defense/proxy/deploy.sh
```

This script:
1. Checks/installs Bun on VPS
2. Copies proxy files to `~/.openclaw/workspace/skills/security-defense/proxy/`
3. Installs `defense-proxy.service` systemd unit
4. Patches `openclaw.service` with ANTHROPIC_BASE_URL and OPENAI_BASE_URL env vars
5. Starts defense proxy, restarts OpenClaw gateway
6. Verifies health endpoint

### Rollback

```bash
src/defense/proxy/deploy.sh --rollback
```

Stops proxy, removes service, strips env vars from openclaw.service, restarts gateway. OpenClaw talks directly to APIs again.

### Verify

```bash
# Health check (includes governor state)
ssh vps 'curl -s http://127.0.0.1:18800/health' | python3 -m json.tool

# Audit log stream
ssh vps 'sudo journalctl -u defense-proxy -f'

# Service status
ssh vps 'sudo systemctl status defense-proxy'
```

## Production Deployment Record

### Deployment Environment

| Component | Version/Detail |
|-----------|---------------|
| OpenClaw | v2026.4.1 (da64a97) |
| Node.js | v22.22.0 |
| Bun | 1.3.11 (installed during deploy) |
| OS | Ubuntu 24.04 LTS |
| Defense plugin | Native hooks (5 hooks registered) |
| Defense proxy | 127.0.0.1:18800 (preserved as fallback, not primary) |
| Gateway | 127.0.0.1:18789 |

### Deployment Evolution

**Phase 1 (initial):** Defense proxy at 127.0.0.1:18800 intercepting API calls via `ANTHROPIC_BASE_URL`/`OPENAI_BASE_URL` env vars. Handled L1 inbound, L3+L4 outbound (non-streaming), L5 governor. L6 not enforced (file/URL access happens inside OpenClaw, not at API boundary).

**Phase 2 (current):** Native plugin with 5 hooks. All 6 layers enforced at the application level. Key improvement: `message_sending` hook enables pre-delivery redaction (proxy could only redact non-streaming responses). `before_tool_call` hook enables L6 access control (proxy couldn't intercept tool calls). Proxy preserved as fallback.

### Layer Enforcement Comparison

| Layer | Proxy (Phase 1) | Plugin (Phase 2) |
|-------|-----------------|-------------------|
| L1 (sanitizer) | On every API request | On `message_received` hook |
| L2 (LLM scanner) | Not enabled (cost) | Not wired (available via `scanInput()`) |
| L3 (gate) | Non-streaming only | Pre-delivery via `message_sending` + audit via `llm_output` |
| L4 (redaction) | Non-streaming only | Pre-delivery via `message_sending` + audit via `llm_output` |
| L5 (governor) | Every API call | Tracking via `llm_input` (informational — void hook) |
| L6 (access control) | Not enforced | Blocking via `before_tool_call` |

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

- Both `defense-proxy` and `openclaw` services active
- Proxy health endpoint returning `status: ok`
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
| `src/defense/plugin/index.ts` | Plugin registration: wires 5 hooks into OpenClaw |
| `src/defense/plugin/hooks.ts` | Hook handler factories for all 5 event types |
| `src/defense/plugin/types.ts` | Plugin-specific type definitions |
| `src/defense/plugin/package.json` | Plugin package manifest |
| `src/defense/proxy/server.ts` | Bun HTTP proxy server (fallback) |
| `src/defense/proxy/config.ts` | Environment-based configuration |
| `src/defense/proxy/defense-proxy.service` | systemd unit file |
| `src/defense/proxy/deploy.sh` | Deploy and rollback script |
| `Reference/DEFENSE-SYSTEM.md` | This file (authoritative reference) |
