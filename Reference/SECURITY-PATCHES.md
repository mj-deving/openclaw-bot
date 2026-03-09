# Security Patches Reference

> **See also:** [UPGRADE-NOTES.md](UPGRADE-NOTES.md) — comprehensive changelog covering all relevant items (not just security).

Changelog security items from OpenClaw updates that may influence our configuration.
Updated per upgrade cycle. Entries marked with action status.

---

## v2026.2.24

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **Heartbeat DM blocking** (BREAKING) — blocks direct/DM targets for heartbeat delivery | Our heartbeat is `--no-deliver`, unaffected. If we ever enable delivery, must target groups/channels only. | NONE (noted) |
| **Docker namespace-join blocked** (BREAKING) — `network: "container:<id>"` blocked for sandbox | We don't use Docker sandbox. | NONE |
| **Exec env sanitization** — strips `LD_*`, `DYLD_*`, `SSLKEYLOGFILE` from non-sandboxed exec | Reduces env injection risk for `exec.security: "full"` posture. | NONE (auto-applied) |
| **Hook Unicode normalization** — NFKC folding prevents bypass via lookalike prefixes | Closes hook classification bypass vector. | NONE (auto-applied) |
| **Telegram DM auth before media download** — enforces auth before writing inbound media to disk | Prevents unauthorized media writes from unauthenticated senders. | NONE (auto-applied) |
| **Reasoning leakage prevention** — suppresses `Reasoning:` blocks and `<think>` text from channel delivery | Prevents internal reasoning from reaching Telegram users. | NONE (auto-applied) |
| **Gateway `/api/channels` auth** — enforces auth on plugin root path + descendants | Hardens our loopback gateway API. | NONE (auto-applied) |
| **Exec safe-bin trusted dirs** — limits to `/bin`, `/usr/bin` only, requires opt-in for others | Tighter exec allowlist. Our `exec.security: "full"` + `exec.ask: "off"` means bot has autonomous shell anyway. | NOTED — biggest residual risk remains shell bypass of tool deny list |
| **Security trust model heuristic** — `security.trust_model.multi_user_heuristic` flags shared-user ingress | We're single-user. Could enable as canary if co-tenant `dev` user ever interacts with gateway. | CONSIDER |
| **Agent fallback chain fix** — keeps traversing chain instead of collapsing to primary on cooldown | Our fallback chain now works correctly. Previously could dead-end. | BENEFITS US |
| **OpenRouter cooldown bypass** — OpenRouter failures no longer put profiles into local cooldown | Our OpenRouter fallback tier won't get trapped in cooldown loops. | BENEFITS US |
| **Cron in `coding` tool profile** — `cron` added to coding profile via `/tools/invoke` | May mean `tools.allow: ["cron"]` is now redundant. Verify before removing. | INVESTIGATE |

### Security Fixes (Auto-Applied)

- Sandbox media: reject hardlink/symlink alias reads, restrict tmp paths to OpenClaw-managed roots
- Workspace FS: normalize `@`-prefixed paths before boundary checks
- Exec approvals: fail closed on nested `/usr/bin/env` chains exceeding depth cap
- Voice Call: Telnyx webhook replay detection with canonicalized signatures
- Shell env: block `SHELLOPTS`/`PS4`, restrict shell-wrapper env to explicit allowlist

---

## v2026.2.23

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **Browser SSRF policy change** (BREAKING) — defaults to `dangerouslyAllowPrivateNetwork=true` | We don't use browser tool. No impact. | NONE |
| **Bootstrap caching** — caches workspace file snapshots per session key, clears on reset | Reduces prompt-cache invalidations from in-session workspace writes. Cost savings. | BENEFITS US |
| **Per-agent `params` overrides** — agents can now tune `cacheRetention` independently | Enables future per-cron-job cache tuning if needed. | NOTED for future |
| **Session maintenance** — `openclaw sessions cleanup` with disk-budget controls | New maintenance command for transcript cleanup. | NOTED for future |

### Security Fixes (Auto-Applied)

- Config: redact sensitive catchall keys in `config.get` snapshots
- Security/ACP: harden auto-approval to require trusted core tool IDs
- Skills: escape user-controlled values in `openai-image-gen` HTML gallery (XSS fix)
- Skills: harden `skill-creator` packaging against symlink escape
- OTEL: redact API keys/tokens from diagnostics log bodies

---

## v2026.3.2

Covers both v2026.3.1 and v2026.3.2 security items (upgraded directly from v2026.2.26).

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **`tools.allow` → `tools.alsoAllow`** (BREAKING) — `tools.allow` now rejects unknown entries and disables allowlist | Our `tools.allow: ["cron"]` broke on upgrade. Migrated to `tools.alsoAllow`. | APPLIED |
| **TOCTOU symlink race in `writeFileWithinRoot`** (GHSA-x82f-27x3-q89c) — open-without-truncate, `O_EXCL` create, post-open validation, out-of-root cleanup | Critical host filesystem protection fix. Node.js lacks `openat(2)` so fix is defense-in-depth. | BENEFITS US |
| **Sandbox media staging symlink escape** — root-scoped safe writes replace direct copies for local + SCP attachments | Blocks out-of-workspace overwrite via media/inbound alias traversal. | BENEFITS US |
| **Webhook auth-before-body parsing** — BlueBubbles, Google Chat handlers authenticate before reading body; size + timeout budgets | Prevents unauthenticated slow-body DoS. Our Telegram webhook is polling-based, but defense-in-depth. | BENEFITS US |
| **Prompt spoofing hardening** — runtime events routed through trusted system context; `[System Message]` markers neutralized | Directly relevant: Telegram-facing bot gets stronger prompt injection resistance. | BENEFITS US |
| **Gateway canonicalization hardening** — plugin route paths decoded to canonical fixpoint; auth enforced on encoded `/api/channels/*` variants | Prevents auth bypass via encoded path variants on our loopback gateway. | BENEFITS US |
| **Cross-agent sandbox inheritance** — blocks sandboxed→unsandboxed subagent spawning via `sessions_spawn` | Prevents sandbox bypass. We don't use sandbox, but defense-in-depth. | BENEFITS US |
| **Exec approval cwd revalidation** — working directory identity checked before execution, fails closed on drift | Prevents stale approval exploitation in exec operations. | BENEFITS US |
| **Post-compaction audit injection removed** — Layer 3 fake system message referencing `WORKFLOW_AUTO.md` deleted | Was a prompt injection vector. Removed entirely. | BENEFITS US |
| **Config backups 0600** — owner-only permissions on rotated config backups; orphan `.bak.*` cleaned | API keys in backups no longer world-readable. | BENEFITS US |
| **HTTP 529 → rate_limit** — provider overload classified as rate_limit, triggers failover | OpenRouter 529 errors trigger our fallback chain. | BENEFITS US |

### Security Fixes (Auto-Applied)

- Security/fs-safe: same-directory temp writes + atomic rename + post-write inode revalidation
- Security/Browser: fd-verified output writes replacing check-then-rename pattern
- Security/Bootstrap: reject symlink/hardlink alias bootstrap files resolving outside workspace
- Security/ACP sandbox: fail-closed guardrails for `sessions_spawn` with `runtime="acp"`
- Security/Sandbox workspace: read-only `/workspace` bind mounts when `workspaceAccess != rw`
- Security/Docker: explicit `OPENCLAW_SANDBOX` opt-in parsing; deferred docker.sock exposure
- Security/Gateway WS: plaintext `ws://` loopback-only by default; break-glass via `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS`
- Security/Gateway: loopback origin tied to socket address not Host header; bounded regex evaluation
- Security/Plugin HTTP: explicit auth required for route registration; ownership guards on duplicates
- Security/Webhook: exact path matches for voice-call webhooks (not prefix matches)
- Security/Web SSRF: DNS pinning kept for untrusted `web_fetch` when proxy env vars set
- Security/Node camera: SSRF-guarded fetch with redirect checks for `camera.snap`/`camera.clip`
- Security/Exec argv: approval-bound wrapper argv semantics preserved post-hardening
- Security/Exec allowlist: regex metacharacters escaped in path-pattern literals (fixes `/usr/bin/g++` crash)
- Security/Skills archive: unified tar safety checks, compressed-size limits, TOCTOU detection
- Security/Skills workspace: `symlink_escape` warning in `openclaw security audit`
- Security/Prompt: stop injecting runtime events into user-role prompt text
- Security/Webchat: filter `NO_REPLY` tokens from `chat.history` responses
- Security/macOS: `Umask=077` in LaunchAgent plists
- Security/Config: owner-only permissions on config backup rotation
- Security/Feishu: webhook rate-limiting with stale-window pruning; reaction verification hardened
- Security/Docker: container path permissions normalized to 755/644

---

## v2026.2.22

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **Google Antigravity removed** (BREAKING) — `google-antigravity/*` model refs broken | We don't use it. | NONE |
| **Tool failure details hidden** (BREAKING) — raw errors require `/verbose on` | Good default for security. Use `/verbose on` when debugging. | NOTED |
| **DM scope per-channel-peer** (BREAKING) — new default for CLI onboarding | Existing setup unaffected. Only new onboard flows. | NONE |
| **Device-auth v1 removed** (BREAKING) — nonce-less connects rejected | We upgraded to full operator scope with v2 signatures. | VERIFIED SAFE |
| **Config prototype pollution fix** — blocks `__proto__`, `constructor`, `prototype` traversal | Critical fix for config mutation security. | NONE (auto-applied) |
| **Auth profile cooldown fix** — cooldown windows immutable across retries, can't extend indefinitely | Prevents cron/inbound retry loops from trapping gateway. | BENEFITS US |
| **OpenRouter cache_control injection** — adds `cache_control` on system prompts for OR Anthropic models | Improves prompt-cache reuse on OpenRouter. | BENEFITS US |
| **Cron auth propagation** — auth-profile resolution propagated to isolated cron sessions | Our cron jobs (Haiku) get proper auth now. | BENEFITS US |
| **Cron max concurrent runs** — honors `cron.maxConcurrentRuns` | Enables parallel cron if we add more jobs. | NOTED for future |

### Security Fixes (Auto-Applied)

- Security/CLI: redact sensitive values in `config get` output
- Security/Exec: detect obfuscated commands before exec allowlist decisions
- Security/Elevated: match `allowFrom` against sender IDs only (not recipient)
- Security/Exec env: block `HOME`/`ZDOTDIR` overrides in exec sanitizers
- Security/Shell env: validate login-shell paths, block dangerous startup vars
- Security/Config: fail closed on empty `allowFrom` for chat allowlist
- Security/Archive: block zip symlink escapes during extraction
- Channels/Security: fail closed on missing group policy config (defaults to `allowlist`)
- Gateway/Security: startup warning for dangerous config flags (e.g., `dangerouslyDisableDeviceAuth`)

---

## v2026.3.3–3.8

Covers security items across v2026.3.3 through v2026.3.8 (upgraded directly from v2026.3.2).

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **Fail-closed config loading** (v2026.3.4) — invalid configs abort gateway startup instead of degrading | Critical operational change. Must run `openclaw config validate` before every restart/upgrade. | APPLIED (validate is part of our upgrade procedure) |
| **Stale-socket restart guards** (v2026.3.4) — protection against hung connections during restart | More reliable `systemctl restart openclaw`. | BENEFITS US |
| **Telegram cron announce delivery fix** (v2026.3.8) — routes text-only jobs through real outbound adapters | Fixes silent cron delivery failures. Resolves KNOWN-BUGS 1.4. Does NOT fix non-cron dupe causes (1.1-1.3). | BENEFITS US |
| **Bundled plugin priority** (v2026.3.8) — bundled plugins preferred over npm-installed copies | Prevents plugin shadowing attacks via npm. | BENEFITS US |
| **ContextEngine lifecycle isolation** (v2026.3.7) — scoped subagent runtime via AsyncLocalStorage | Stronger isolation for subagent operations. | BENEFITS US |
| **Memory/QMD index isolation** (v2026.3.7) — memory index separated per-agent | Prevents cross-agent memory index contamination. | BENEFITS US |
| **ACP Provenance** (v2026.3.8) — `openclaw acp --provenance off\|meta\|meta+receipt` | New identity verification feature. Opt-in. | CONSIDER |
| **`openclaw backup create/verify`** (v2026.3.8) — native state archive with manifest validation | Backup integrity verification. | BENEFITS US |

### Security Fixes (Auto-Applied)

- Security/Config: fail-closed loading aborts on invalid keys (v2026.3.4)
- Security/Socket: stale-socket guards prevent hung connection inheritance (v2026.3.4)
- Security/SecretRef: gateway auth handling hardened (v2026.3.3)
- Security/ContextEngine: lifecycle hooks scoped via AsyncLocalStorage (v2026.3.7)
- Security/Memory: QMD index isolation per-agent (v2026.3.7)
- Security/Plugin: bundled plugin priority prevents npm shadowing (v2026.3.8)
- Security/ACP: provenance metadata capture with opt-in receipt injection (v2026.3.8)
- Security/Backup: manifest/payload validation for archive integrity (v2026.3.8)

---

## How To Use This File

- **Before each upgrade:** Read the new version's changelog, extract security-relevant items here
- **BENEFITS US:** Changes that improve our posture automatically
- **INVESTIGATE:** Items that may let us simplify or harden our config
- **CONSIDER:** Optional hardening we might enable
- **NOTED:** Awareness items for future reference
- **NONE:** No action needed, but documented for completeness

## Config Decisions Influenced

| Decision | Source | Status |
|----------|--------|--------|
| `tools.allow: ["cron"]` may be redundant | v2026.2.24 — cron in coding profile | INVESTIGATE |
| `security.trust_model.multi_user_heuristic` | v2026.2.24 — shared-user detection | CONSIDER |
| Fallback chain now reliable | v2026.2.24 — traversal fix | APPLIED |
| Per-agent cache params possible | v2026.2.23 — `params` overrides | FUTURE |
| Session cleanup available | v2026.2.23 — `sessions cleanup` | FUTURE |
| `tools.allow` → `tools.alsoAllow` migration | v2026.3.2 — allowlist key renamed | APPLIED |
| Monitor compaction loop regression (#32106) | v2026.3.1 — `softThresholdTokens=4000` | INVESTIGATE |
| `openclaw config validate` as pre-restart check | v2026.3.2 — config validation CLI | APPLIED |
| ACP dispatch now default-on | v2026.3.2 — set `false` if unwanted | NOTED |
| Fail-closed config loading — validate before every restart | v2026.3.4 — config abort on invalid keys | APPLIED |
| `openclaw backup create` for pre-upgrade snapshots | v2026.3.8 — native backup command | INVESTIGATE |
| ACP provenance for agent identity | v2026.3.8 — `acp --provenance meta` | CONSIDER |
| Telegram cron delivery fix — remove streaming workarounds? | v2026.3.8 — announce adapter fix | INVESTIGATE |
