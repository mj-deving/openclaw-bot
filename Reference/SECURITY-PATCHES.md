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
