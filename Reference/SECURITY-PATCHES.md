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

## v2026.3.11–3.12

Covers v2026.3.11 (March 12) and v2026.3.12 (March 13). Upgraded directly from v2026.3.8.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **WebSocket browser origin validation** (v2026.3.11) — enforces origin check for all browser-originated connections, closes cross-site WebSocket hijacking in trusted-proxy mode | Our gateway is loopback-only, not directly exploitable. Defense-in-depth. | NONE (auto-applied) |
| **Cron isolated delivery tightened** (v2026.3.11, BREAKING) — prevents ad hoc notifies and fallback summaries in isolated cron sessions | Requires `openclaw doctor --fix` migration. Applied on upgrade. | APPLIED |
| **Device pairing: short-lived bootstrap tokens** (v2026.3.12) — replaces embedded shared credentials with ephemeral tokens | Significant improvement. Closes credential replay class for device pairing flow. | NONE (auto-applied) |
| **Workspace plugin auto-load disabled** (v2026.3.12) — plugins in workspace dirs no longer auto-execute without explicit enablement | Closes unauthorized code execution from workspace files. Directly relevant to Gregor's workspace. | NONE (auto-applied) |
| **Invisible Unicode escaping in approval prompts** (v2026.3.12) — escapes invisible Unicode in tool approval displays | Closes prompt injection via invisible characters. | NONE (auto-applied) |
| **Unicode normalization before obfuscation checks** (v2026.3.12) — normalizes Unicode before exec obfuscation detection | Closes Unicode-based exec bypass. Strengthens our `exec.security: "full"` posture. | NONE (auto-applied) |
| **Sender ownership for `/config` and `/debug`** (v2026.3.12) — requires sender ownership verification | Prevents unauthorized config access even in shared contexts. | NONE (auto-applied) |
| **Hooks fail-closed on unresolvable paths** (v2026.3.12) — hook loader fails closed instead of skipping | Prevents hook bypass via path manipulation. | NONE (auto-applied) |
| **POSIX case sensitivity in allowlist** (v2026.3.12) — preserves case sensitivity in allowlist patterns | Prevents case-based allowlist bypass on Linux. | NONE (auto-applied) |
| **Cron isolated sends excluded from resend queue** (v2026.3.12) — prevents duplicate delivery from resend queue | Another duplicate message root cause closed. Keep `streamMode: "off"` for remaining causes. | BENEFITS US |
| **Agent text sanitization** (v2026.3.11) — strips leaked model control tokens from delivery | Prevents GLM-5/DeepSeek delimiters from reaching Telegram users. | NONE (auto-applied) |
| **`node-llama-cpp` peer dependency** (v2026.3.12) — now a peer dep instead of optional | Requires manual install for global npm setups: `cd ~/.npm-global/lib/node_modules/openclaw && npm install node-llama-cpp@3.16.2` | APPLIED |

### Security Fixes (Auto-Applied)

- Security/WebSocket: browser origin validation for all browser-originated connections (v2026.3.11)
- Security/Device: short-lived bootstrap tokens replace embedded shared credentials (v2026.3.12)
- Security/Plugins: disabled implicit workspace plugin auto-load (v2026.3.12)
- Security/Unicode: invisible character escaping in approval prompts (v2026.3.12)
- Security/Unicode: normalization before obfuscation checks (v2026.3.12)
- Security/Commands: sender ownership required for `/config` and `/debug` (v2026.3.12)
- Security/Scopes: unbound scope clearing on shared-token WebSocket connects (v2026.3.12)
- Security/Browser: persistent browser profile operations blocked from write-scoped requests (v2026.3.12)
- Security/Agents: public spawned-run lineage fields rejected (v2026.3.12)
- Security/Sandbox: session-tree visibility enforced in `session_status` (v2026.3.12)
- Security/Hooks: fail-closed on unresolvable paths (v2026.3.12)
- Security/Hooks: agent delivery deduplication by idempotency key (v2026.3.12)
- Security/Allowlist: POSIX case sensitivity preserved in patterns (v2026.3.12)

---

## v2026.3.13

Released 2026-03-14. Auto-updated from v2026.3.12, then **rolled back** due to CLI WS regression. Security items documented for reference.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **CLI→gateway WS RPC broken** (REGRESSION) — CLI WS handshake fails on `cron list`, `cron runs`, gateway probe. Root cause: missing device token auth path. Issues #45560, #46716, #47103 | Cannot manage cron via CLI. Telegram and internal cron execution unaffected. | ROLLED BACK to v2026.3.12 |
| **Plugin command/runtime hardening** — validates and normalizes plugin specs at registration boundaries; guards Telegram menu normalization | Prevents startup crashes from malformed plugin specs. | NONE (auto-applied) |
| **Webhook auth pre-validation** — validates secret BEFORE reading request bodies | Prevents resource exhaustion from unauthenticated webhook requests. | NONE (auto-applied) |
| **Telegram media SSRF hardening** — SSRF-guarded file fetches with IPv4 fallback | Hardens media download path. | NONE (auto-applied) |
| **macOS exec approval trust binding** — trust bound to name AND resolved path | macOS-specific. Prevents same-basename trust inheritance. | NONE (macOS only) |
| **Cron isolated session deadlock fix** — nested work routed to nested lane | Prevents cron hangs during compaction. Important for isolated sessions. | BENEFITS US |

### Security Fixes (Auto-Applied)

- Security/Telegram: plugin command spec validation at registration boundaries (v2026.3.13)
- Security/Telegram: media download SSRF-guarded with IPv4 fallback (v2026.3.13)
- Security/Telegram: webhook secret validated before body parsing (v2026.3.13)
- Security/Telegram: duplicate-token check guarding prevents startup crashes (v2026.3.13)
- Security/macOS: exec approval trust bound to name + resolved path (v2026.3.13)
- Security/Gateway: shared token auth preserved on plain-HTTP connections (v2026.3.13)

---

## v2026.3.22 / v2026.3.23

Upgrade from v2026.3.12 → v2026.3.23 (skipping v2026.3.14–v2026.3.22). Installed 2026-03-24.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **CLI WS RPC regression FIXED** (PR #50101) — operator scope preservation during device-auth bypass | `cron list`, `cron runs`, gateway memory probe all work again. Unblocks PARA cron monitoring. | APPLIED (upgrade) |
| **Auth-profile credential reversion fix** (v2026.3.23) — gateway no longer overwrites auth-profiles.json with stale in-memory OAuth tokens | Fixes the exact auth issue we hit on 2026-03-21 where OAuth profiles silently reverted. | BENEFITS |
| **Plugin SDK migration** — `openclaw/extension-api` → `openclaw/plugin-sdk/*` | External plugins (LCM) may need path updates. Verify LCM loads. | INVESTIGATE |
| **ClawHub default plugin store** — resolution prefers ClawHub before npm | Risk of namespace squatting. LCM installed via explicit spec, low risk. | NOTED |
| **Device pairing codes bound to profile** — stricter auth enforcement | Device-pair disabled for us. Tighter security posture. | BENEFITS |
| **Pluggable sandbox backends** — SSH and OpenShell (NemoClaw) support | Future hardening path. See Reference/NEMOCLAW.md. | CONSIDER |

### Security Fixes (Auto-Applied)

- Security/Media: block `file://` URLs and UNC paths before resolution (prevents SMB credential handshake)
- Security/Gateway: CSP hardening — SHA-256 hashes for inline script blocks in Control UI
- Security/Plugins: enhanced manifest validation against marketplace sources
- Security/Exec: JVM and dependency resolution injection hardening in sandbox
- Security/Webhook: body limits and timeouts before auth checks (defense-in-depth)
- Security/Auth: device token enforcement for `operator.read` scope (CLI WS RPC fix)
- Security/Auth: credential reversion prevention — no more stale in-memory token overwrites
- Security/Gateway: cold start hardening — faster initialization reduces exposure window
- Security/Telegram: threading context correctly populated (prevents context confusion)
- Security/OpenRouter: auto-pricing recursion fix (prevents infinite loop DoS)
- Security/Packaging: bundled plugin sidecars and Control UI restored (v2026.3.23)

### Security Evolution (v2026.2.22 → v2026.3.23)

Cumulative security hardening across all versions we've tracked:

| Category | Controls Added | Version |
|----------|---------------|---------|
| **Exec sandbox** | env sanitization (LD_*, DYLD_*), safe-bin dirs, nested env chain cap, JVM injection hardening | v2026.2.24, v2026.3.22 |
| **Auth** | hook Unicode normalization, agent fallback chain fix, device bootstrap tokens, credential reversion fix | v2026.2.24, v2026.3.12, v2026.3.23 |
| **Telegram** | DM auth before media, SSRF-guarded downloads, webhook pre-auth, plugin command validation | v2026.2.24, v2026.3.13, v2026.3.22 |
| **Gateway** | /api/channels auth, shared token on plain HTTP, CSP hardening, cold start hardening | v2026.2.24, v2026.3.13, v2026.3.22 |
| **Plugins** | workspace auto-load disabled, manifest validation, SDK migration | v2026.3.12, v2026.3.22 |
| **Media** | sandbox reject hardlink/symlink, file:// URL blocking, UNC path blocking | v2026.2.24, v2026.3.22 |
| **Config** | fail-closed loading, config validate CLI, per-agent reasoning defaults | v2026.3.4, v2026.3.2, v2026.3.22 |

## v2026.3.28 / v2026.3.31 / v2026.4.1

Upgrade from v2026.3.24 → v2026.4.1 (skipping v2026.3.28 and v2026.3.31). Installed 2026-04-02 via manual upgrade with safe stop/start procedure.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **GHSA-3qpv-xf3v-mm45** (HIGH) — workspace `.env` overrides `OPENCLAW_BUNDLED_HOOKS_DIR` | Attacker `.env` in workspace could load malicious hook code. Our `ReadOnlyPaths` on workspace mitigates, but fix is definitive. | APPLIED (v2026.4.1) |
| **GHSA-qcj9-wwgw-6gm8** (HIGH) — workspace `.env` overrides `OPENCLAW_BUNDLED_PLUGINS_DIR` | Attacker could substitute plugin trust root. Similar mitigation via our hardening. | APPLIED (v2026.4.1) |
| **GHSA-7ggg-pvrf-458v** (HIGH) — `PIP_INDEX_URL`/`UV_INDEX_URL` bypass exec env sanitization | Relevant with `exec.security: full` — pip/uv installs could pull from attacker index. | APPLIED (v2026.4.1) |
| **GHSA-g8xp-qx39-9jq9** (MEDIUM) — compiler binary substitution via `CC`/`CXX` env overrides | Build commands could use attacker compiler binaries. | APPLIED (v2026.4.1) |
| **GHSA-g5cg-8x5w-7jpm** (CRITICAL) — heartbeat `senderIsOwner` sandbox escalation | **Most critical for our deployment.** Heartbeat context inheritance bypassed sandbox, granting owner-level permissions to heartbeat sessions. Our heartbeat runs every 30 minutes. | APPLIED (v2026.4.1) |
| **Plugin install fail-closed** (v2026.3.31 BREAKING) — plugins with critical scan findings blocked | LCM has `potential-exfiltration` warning (not critical severity). Still installs. | NOTED |
| **Cron tool allowlists** (`--tools` flag) — per-job tool restrictions for cron jobs | Can lock down PARA crons to memory-only tools, removing shell access. | CONSIDER |
| **`auto-update.sh` fixed** — now stops gateway before `npm install -g` | Prevents in-place dist/ overwrite crash (issue #54790). | APPLIED (script deployed) |
| **Compaction model resolution** — `agents.defaults.compaction.model` consistent everywhere | Our Haiku compaction config now works reliably across all compaction paths. | BENEFITS |

### Security Fixes (Auto-Applied)

- Security/Exec: `OPENCLAW_PINNED_PYTHON` blocked from workspace `.env` override
- Security/Exec: additional host env override pivots blocked (package roots, runtimes, credentials)
- Security/Exec: `PIP_INDEX_URL`, `UV_INDEX_URL` stripped from host exec env
- Security/Exec: compiler binary env vars (`CC`, `CXX`, etc.) sanitized
- Security/Webhooks: timing-safe secret comparison for Telegram and other handlers
- Security/Sandbox: media dispatch bypass (`mediaUrl`/`fileUrl` alias) closed
- Security/Heartbeat: `senderIsOwner` escalation via heartbeat context fixed
- Security/Plugins: install scan failures fail closed (critical findings block plugin)
- Security/Agents: `sensitive` stop reason handled gracefully (no crash)
- Security/Telegram: whitespace-only replies no longer cause GrammyError 400 crashes
- Security/Auth: rate-limit cooldowns scoped per model (not per auth profile)
- Security/Auth: misplaced SecretRef objects coerced safely (prevents `.trim()` crash)
- Security/Memory: session indexing fixed — reindexes no longer skip transcripts
- Security/Gateway: startup config writes no longer trigger restart loops
- Security/Gateway: per-channel boot isolation — single broken channel doesn't block others

### Security Evolution (v2026.3.23 → v2026.4.1)

| Category | Controls Added | Version |
|----------|---------------|---------|
| **Exec sandbox** | `.env` injection family (hooks, plugins, pip, compilers, python, runtimes) | v2026.3.31, v2026.4.1 |
| **Heartbeat** | `senderIsOwner` sandbox escalation fixed | v2026.3.31 |
| **Auth** | rate-limit scoping per model, SecretRef coercion, profile rotation cap | v2026.3.28, v2026.4.1 |
| **Telegram** | whitespace crash fix, long message split fix, timing-safe webhooks, error policy | v2026.3.28, v2026.4.1 |
| **Plugins** | install scan fail-closed, media dispatch bypass fixed | v2026.3.31, v2026.4.1 |
| **Memory** | session indexing fix, QMD mask fix, compaction model resolution | v2026.3.28, v2026.4.1 |

---

## v2026.4.2

Auto-updated on Gregor from v2026.4.1 (weekly cron). Security-focused point release.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **CVE-2026-34425** (HIGH) — Exec script preflight validation skipped on complex invocations (pipes, chained interpreters) | Closes shell bypass vector for `exec.security: "full"` deployments. Crafted pipe chains could skip approval. | BENEFITS (auto-applied) |
| **CVE-2026-34426** (MEDIUM-HIGH) — Approval bypass via unvalidated environment variables | Env var injection could skip tool approval checks. | BENEFITS (auto-applied) |
| **CVE-2026-33580** (MEDIUM) — Nextcloud Talk webhook missing rate limiting | We don't use Nextcloud Talk. | NONE |

### Security Fixes (Auto-Applied)

- Exec: complex interpreter pipeline validation (pipes, subshells, heredocs)
- Exec: env var approval bypass closed
- Config: startup atomic rename stability improvements (reduces EBUSY risk)

---

## v2026.4.5

Fresh install on Dismas (2026-04-06). Major feature + security release. Significant breaking changes.

### Critical / Config-Relevant

| Item | Impact | Our Action |
|------|--------|------------|
| **`tools.allow` whitelist behavior** (BREAKING) — `tools.allow` now replaces profile defaults instead of adding to them. Setting `["cron"]` disables read/write/edit/shell. | Broke Dismas file tools. Must use `tools.alsoAllow` (additive) instead. | APPLIED — switched to `tools.alsoAllow` |
| **`plugins.allow` whitelist behavior** (BREAKING) — blocks bundled plugins (Telegram, browser) from loading. Silent failure, no log entries. | Broke Dismas Telegram channel. No error visible. | APPLIED — removed `plugins.allow` entirely |
| **Fail-closed `before_tool_call` hooks** — crashing hooks now block tool calls instead of silently passing | Critical for defense plugin: if L6 access control crashes, tool call is blocked. Previously would pass through. | BENEFITS (auto-applied) |
| **Browser SSRF redirect bypass blocked** — redirect chains can no longer escape SSRF protections | Hardens browser tool (enabled on both bots). | BENEFITS (auto-applied) |
| **Claude Code env overrides cleared** — `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_PLUGIN_*` stripped | Prevents env-based config injection from inherited shells. | BENEFITS (auto-applied) |
| **Loopback auth throttling per origin** — rate limiting scoped by client, not global | Better brute-force protection on gateway API. | BENEFITS (auto-applied) |
| **Serialized async shared-secret auth** — concurrent auth attempts serialized per client | Prevents race condition in webhook auth. | BENEFITS (auto-applied) |
| **Legacy config aliases removed** — `talk.voiceId`, `talk.apiKey`, `agents.*.sandbox.perSession`, `browser.ssrfPolicy.allowPrivateNetwork` | Not in our config. Run `doctor --fix` to check. | NONE |

### Security Fixes (Auto-Applied)

- Exec: fail-closed hook error handling for `before_tool_call`
- Browser: SSRF redirect chain bypass blocked
- Auth: loopback throttling per normalized origin
- Auth: serialized async shared-secret auth attempts
- Env: Claude Code plugin env vars stripped from gateway process
- Config: legacy key deprecation (talk, sandbox, browser.ssrfPolicy)

### Security Evolution (v2026.4.1 → v2026.4.5)

| Category | Controls Added | Version |
|----------|---------------|---------|
| **Exec sandbox** | Complex interpreter pipeline validation (CVE-2026-34425), env approval bypass (CVE-2026-34426) | v2026.4.2 |
| **Hooks** | Fail-closed error handling for tool guard hooks | v2026.4.5 |
| **Browser** | SSRF redirect chain bypass blocked | v2026.4.5 |
| **Auth** | Per-origin loopback throttling, serialized shared-secret auth | v2026.4.5 |
| **Config** | Legacy alias removal, env override stripping | v2026.4.5 |
| **Whitelist behavior** | `tools.allow` and `plugins.allow` now restrictive (breaking) | v2026.4.5 |

### Upgrade Warning for Gregor (v2026.4.2 → v2026.4.5)

Before upgrading Gregor, these changes MUST be applied first:
1. Switch `tools.alsoAllow` (already done — was `alsoAllow` on Gregor)
2. Verify `plugins.allow` includes all bundled plugins OR remove it
3. Update `streaming` config format (remove legacy `blockStreaming`)
4. Test with `openclaw doctor --fix` post-upgrade

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
| Device pairing bootstrap tokens — credential replay class closed | v2026.3.12 — short-lived tokens | BENEFITS |
| Workspace plugin auto-load disabled — execution risk closed | v2026.3.12 — implicit load disabled | BENEFITS |
| `node-llama-cpp` peer dep — manual install on global upgrades | v2026.3.12 — dependency restructure | APPLIED |
| Cron resend queue dupe fix — another root cause closed | v2026.3.12 — isolated send exclusion | BENEFITS |
| CLI WS RPC regression — rolled back to v2026.3.12 | v2026.3.13 — upstream auth bug | ROLLED BACK |
| Auto-update disabled until CLI fix | v2026.3.13 — pinned to v2026.3.12 | APPLIED |
| Cron isolated session deadlock fix | v2026.3.13 — nested lane routing | BENEFITS |
