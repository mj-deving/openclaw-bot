# OpenClaw Upgrade Notes

> **See also:** [SECURITY-PATCHES.md](SECURITY-PATCHES.md) — security-only subset of these notes, organized by severity and action status.

All changelog items from OpenClaw updates relevant to our setup, guide, and config decisions.
Filtered to our operational surface: Telegram, cron, heartbeat, Anthropic/OpenRouter providers,
memory, context pruning, compaction, exec, gateway, CLI, auth profiles, and config mechanics.

Updated per upgrade cycle. Items not relevant to our platform (Discord, Slack, WhatsApp, macOS app,
Windows, iOS, iMessage, Signal, Matrix, etc.) are excluded unless they have cross-cutting implications.

**Action tags:** APPLIED (config change made) | BENEFITS (auto-applied, improves our posture) |
INVESTIGATE (may simplify/harden config) | CONSIDER (optional adoption) | NOTED (awareness) |
GUIDE (needs guide update) | NONE (no action, documented for reference)

---

## v2026.2.24

Upgraded 2026-02-25 from v2026.2.21-2. Gateway restarted, cron jobs verified.

### Breaking Changes

1. **Heartbeat DM blocking** — Heartbeat delivery blocks direct/DM targets (Telegram user chat IDs, etc.). Runs still execute, but DM delivery is skipped. Only group/channel targets receive outbound heartbeat messages.
   - **Impact:** Our heartbeat is `--no-deliver`, so delivery is already disabled. No impact.
   - **Guide:** Phase 8 heartbeat section should note this if delivery is ever enabled. **GUIDE**

2. **Docker namespace-join blocked** — `network: "container:<id>"` blocked by default for sandbox containers.
   - **Impact:** We don't use Docker sandbox. **NONE**

### Heartbeat & Cron

3. **Heartbeat delivery default → `none`** — Implicit heartbeat delivery target switched from `last` to `none` (opt-in). Internal-only prompt wording when delivery disabled.
   - **Impact:** Aligns with our `--no-deliver` pattern. Background checks won't nudge user-facing behavior. **BENEFITS**

4. **Heartbeat queueing fix** — Drops heartbeat runs when session already has active run, preventing duplicate heartbeat branches.
   - **Impact:** Prevents double heartbeats if we're mid-conversation when heartbeat fires. **BENEFITS**

5. **Cron/Heartbeat thread isolation** — Stops inheriting cached `lastThreadId` for heartbeat-mode target resolution, keeping deliveries on top-level destinations.
   - **Impact:** If we ever enable cron delivery, it won't leak into conversation threads. **BENEFITS**

6. **Cron in `coding` tool profile** — `cron` included in coding profile via `/tools/invoke` when explicitly allowed by gateway policy.
   - **Impact:** Investigated: `tools.allow: ["cron"]` is **NOT redundant**. Official docs confirm `group:automation` tools (cron, gateway) are outside all profiles including `"full"`. The .24 change only means the coding profile can *surface* cron via tool-invoke if the gateway policy already allows it — the explicit `tools.allow` is still what grants access. **RESOLVED — keep current config**

7. **Messaging tool dedupe** — Fixes duplicate Telegram sends from `delivery-mirror` transcript entries in proactive runs (heartbeat/cron/exec-event).
   - **Impact:** Our cron jobs won't produce duplicate Telegram messages if delivery is enabled. **BENEFITS**

### Telegram

8. **Telegram reply fallback** — When markdown renders to empty HTML, retries with plain text. Fails loud when both are empty.
   - **Impact:** Prevents silent message drops from Gregor. **BENEFITS**

9. **Telegram IPv4 priority** — Prioritizes IPv4 in SSRF pinned DNS for media downloads on hosts with broken IPv6.
   - **Impact:** Our VPS has IPv6 (`2a02:c207:3018:496::1`), but IPv4 fallback improves reliability. **BENEFITS**

10. **Telegram outbound undici fix** — Replaces Node 22's global undici dispatcher for `autoSelectFamily` decisions.
    - **Impact:** Fixes potential outbound fetch failures. **BENEFITS**

11. **Telegram DM auth before media** — Enforces DM authorization before media download/write, preventing unauthorized media disk writes.
    - **Impact:** Hardens our Telegram bot against unauthorized media from unknown senders. **BENEFITS**

12. **Telegram onboarding resilience** — Core channel onboarding available even without plugin registry.
    - **Impact:** Future re-onboarding won't break if plugins aren't loaded. **NOTED**

### Model Fallback & Routing

13. **Fallback chain traversal fix** — When on a fallback model, keeps traversing the chain instead of collapsing to primary-only. Prevents dead-end failures when primary stays in cooldown.
    - **Impact:** Our new chain (Sonnet → Sonnet-OR → Auto-OR → Free-OR) actually works correctly now. This was the key bug. **APPLIED**

14. **Model allowlist synthesis** — Honors explicit `agents.defaults.models` allowlist refs even when bundled catalog is stale. No false `model not allowed` errors.
    - **Impact:** Our OpenRouter model refs (`openrouter/auto`, `openrouter/free`) won't get rejected if catalog is outdated. **BENEFITS**

15. **Fallback input inheritance** — Control UI inherits `agents.defaults.model.fallbacks` in Overview when no per-agent entry exists.
    - **Impact:** If we ever use Control UI, fallbacks display correctly. **NOTED**

### Providers (Anthropic & OpenRouter)

16. **OpenRouter cooldown bypass** — Provider failures no longer put OpenRouter profiles into local cooldown. Stale legacy cooldown markers ignored.
    - **Impact:** Our OpenRouter fallback tiers won't get trapped in cooldown loops. **BENEFITS**

17. **Anthropic 500 failover** — `type: "api_error"` + `"Internal server error"` treated as transient failover-eligible errors.
    - **Impact:** Anthropic 500s now trigger our fallback chain instead of retrying same target. **BENEFITS**

18. **HTTP 502/503/504 failover** — These status codes now trigger fallback chain instead of retrying same failing target.
    - **Impact:** Upstream outages at Anthropic/OpenRouter trigger graceful degradation. **BENEFITS**

### Auth Profiles

19. **Auth profile cooldown immutability** — Active cooldown/disabled windows can't be extended by mid-window retries. Only recomputed after previous deadline expires.
    - **Impact:** Prevents cron/inbound retry loops from trapping gateway. Critical for our cron reliability. **BENEFITS**

20. **Auth profile timeout handling** — Timeout failures in embedded runner rotation don't poison fallback model selection.
    - **Impact:** Timeouts won't put our Anthropic profile into cooldown incorrectly. **BENEFITS**

### Agents & Sessions

21. **Typing keepalive** — Refreshes typing indicators during long replies, clears on idle.
    - **Impact:** Telegram shows "typing..." throughout long Gregor responses. Better UX. **BENEFITS**

22. **Tool dispatch ordering** — Awaits block-reply flush before tool execution for correct message ordering.
    - **Impact:** Gregor's tool-call replies appear in correct order. **BENEFITS**

23. **Tool-result guard** — No synthetic `toolResult` for aborted/error turns, preventing orphaned tool-use ID errors.
    - **Impact:** Reduces API validation errors in failed sessions. **BENEFITS**

24. **Billing classification fix** — Long text no longer misclassified as billing failures.
    - **Impact:** Gregor won't incorrectly report billing errors on verbose responses. **BENEFITS**

25. **Compaction safeguard restored** — Context-pruning extension loading fixed in production.
    - **Impact:** Our `contextPruning.mode: "cache-ttl"` works correctly with compaction. **BENEFITS**

### CLI

26. **Memory search syntax** — `openclaw memory search` now accepts `--query <text>` in addition to positional.
    - **Impact:** Both syntaxes work for memory debugging. **NOTED**

27. **Doctor hints corrected** — Points to valid commands: `openclaw gateway status --deep` and `openclaw configure --section model`.
    - **Impact:** Doctor output is actionable. **GUIDE**

### Gateway & Config

28. **Config meta coercion** — Accepts numeric `meta.lastTouchedAt` and coerces to ISO strings.
    - **Impact:** Agent edits using `Date.now()` won't corrupt config. **BENEFITS**

29. **Reset hooks guaranteed** — `/new` and `/reset` always emit command/reset hooks.
    - **Impact:** If we add hooks, they fire reliably on session reset. **NOTED**

30. **Hook slug model resolution** — Resolves session slug from effective model (including fallbacks), not just primary config.
    - **Impact:** Session slugs correct when on fallback model. **BENEFITS**

### Security

31. **Exec env sanitization** — Strips `LD_*`, `DYLD_*`, `SSLKEYLOGFILE` from non-sandboxed exec runs.
    - **Impact:** Reduces env injection surface for our `exec.security: "full"` posture. **BENEFITS**

32. **Hook Unicode normalization** — NFKC folding prevents bypass via lookalike Unicode prefixes.
    - **Impact:** Closes hook classification bypass vector. **BENEFITS**

33. **Gateway `/api/channels` auth** — Enforces auth on plugin API root path.
    - **Impact:** Hardens our loopback gateway API. **BENEFITS**

34. **Exec safe-bin trusted dirs** — Limited to `/bin`, `/usr/bin` only. User bin paths need explicit opt-in via `tools.exec.safeBinTrustedDirs`.
    - **Impact:** Tighter exec surface. Our `exec.security: "full"` + `exec.ask: "off"` means bot has autonomous shell anyway, but the default is now safer. **NOTED**

35. **Trust model heuristic** — New `security.trust_model.multi_user_heuristic` flags shared-user ingress.
    - **Impact:** We're single-user. Could enable as canary for VPS co-tenant detection. **CONSIDER**

36. **Auto-reply stop phrases** — Expanded standalone stop phrases, multilingual support.
    - **Impact:** Users can stop Gregor mid-response more easily in Telegram. **BENEFITS**

### New Config Keys

- `security.trust_model.multi_user_heuristic` — Multi-user detection
- `tools.exec.safeBinTrustedDirs` — Explicit safe-bin trusted directories
- `agents.defaults.sandbox.docker.dangerouslyAllowContainerNamespaceJoin` — Docker namespace break-glass

---

## v2026.2.23

### Breaking Changes

1. **Browser SSRF policy** — Defaults to `dangerouslyAllowPrivateNetwork=true`. Config key renamed.
   - **Impact:** We don't use browser tool. **NONE**

### Providers

2. **Kilo Gateway provider** — New first-class `kilocode` provider support.
   - **Impact:** New provider option if we want to explore. **NOTED**

3. **Vercel AI Gateway** — Claude shorthand model refs normalized for Vercel routing.
   - **Impact:** Alternative routing option. **NOTED**

### Agents & Sessions

4. **Per-agent `params` overrides** — Agents can tune `cacheRetention` independently via merged `params`.
   - **Impact:** Enables per-cron-job cache tuning. Could set different retention for daily-report vs pipeline-check. **CONSIDER**

5. **Bootstrap file caching** — Caches workspace file snapshots per session key, clears on reset. Reduces prompt-cache invalidations from in-session `AGENTS.md`/`MEMORY.md` writes.
   - **Impact:** Fewer cache misses when Gregor writes to workspace files mid-session. Cost savings. **BENEFITS**

6. **Context pruning extended** — `cache-ttl` eligibility extended to Moonshot/Kimi and ZAI/GLM providers (including OpenRouter refs).
   - **Impact:** Our `contextPruning.mode: "cache-ttl"` would work on more provider fallbacks if we route through them. **NOTED**

### Memory

7. **Doctor memory probe** — Queries gateway-side embedding readiness instead of inferring from health.
   - **Impact:** `openclaw doctor` gives better memory diagnostics. **BENEFITS**

### Telegram

8. **Telegram reactions** — Soft-fails reaction errors, accepts snake_case `message_id`, uses inbound message-id fallback.
   - **Impact:** Telegram reactions more reliable. **BENEFITS**

9. **Telegram polling isolation** — Scopes polling offsets to bot identity, prevents cross-token offset bleed.
   - **Impact:** Prevents polling issues if bot token ever changes. **BENEFITS**

10. **Telegram reasoning suppression** — When `/reasoning off`, suppresses reasoning-only segments and blocks raw `Reasoning:`/`<think>` fallback text.
    - **Impact:** Prevents internal reasoning leakage in Telegram messages. **BENEFITS**

### Cron

11. **Session maintenance** — New `openclaw sessions cleanup` with per-agent targeting and disk-budget controls (`session.maintenance.maxDiskBytes` / `highWaterBytes`).
    - **Impact:** New tool for transcript cleanup. Our sessions will accumulate over time. **CONSIDER**
    - **Guide:** Phase 14 should mention session maintenance. **GUIDE**

### Gateway

12. **Session store canonicalization** — Mixed-case session keys migrated to lowercase, preventing duplicates.
    - **Impact:** Cleaner session history. **BENEFITS**

13. **HTTP security headers** — Optional `gateway.http.securityHeaders.strictTransportSecurity` for HTTPS deployments.
    - **Impact:** Our gateway is loopback HTTP, not applicable. But good to know for future. **NOTED**

### Agents

14. **Reasoning overflow fix** — Reasoning-required errors no longer misclassified as context overflows.
    - **Impact:** Prevents spurious compaction when reasoning is active. **BENEFITS**

15. **Model config codified** — `agents.defaults.model` formally accepts `string | {primary, fallbacks}` shape.
    - **Impact:** Our config shape is officially supported. **NOTED**

16. **Compaction auth scoping** — Manual `/compact` scoped to active agent's auth profile.
    - **Impact:** Compaction uses correct API keys. **BENEFITS**

17. **Compaction safeguard** — Cancels compaction when summary generation fails, preserving history instead of truncating.
    - **Impact:** Prevents data loss from failed compactions. **BENEFITS**

18. **Overflow detection expanded** — More error shapes route through compaction/recovery, including localized errors.
    - **Impact:** Better automatic recovery from context overflow. **BENEFITS**

### Security

19. **Config `config.get` redaction** — Redacts sensitive dynamic catchall keys before output.
    - **Impact:** `openclaw config get` output safer in terminal. **BENEFITS**

20. **Prompt caching docs** — Official docs for `cacheRetention`, per-agent `params` merge, Bedrock/OpenRouter behavior.
    - **Impact:** Authoritative reference for our caching config. **GUIDE**

### New Config Keys

- `agents.defaults.params` — Per-agent model parameter overrides (including `cacheRetention`)
- `session.maintenance.maxDiskBytes` / `highWaterBytes` — Session disk budgets
- `gateway.http.securityHeaders.strictTransportSecurity` — HSTS header

---

## v2026.2.22

### Breaking Changes

1. **Google Antigravity removed** — `google-antigravity/*` model/profile configs broken.
   - **Impact:** We don't use it. **NONE**

2. **Tool failure details hidden** — Raw error details require `/verbose on` or `/verbose full`.
   - **Impact:** Gregor's error messages to Marius will be shorter by default. Use `/verbose on` when debugging. **NOTED**
   - **Guide:** Note in Phase 5 (commands) that `/verbose on` reveals tool errors. **GUIDE**

3. **DM scope per-channel-peer** — CLI onboarding defaults `session.dmScope` to `per-channel-peer`.
   - **Impact:** Only affects NEW onboard flows. Our existing config preserved. **NONE**

4. **Channel streaming config unified** — `channels.<channel>.streaming` with enum values `off | partial | block | progress`.
   - **Impact:** If we ever configure Telegram streaming, use the new key. Legacy keys still read via `doctor --fix`. **NOTED**

5. **Device-auth v1 removed** — Nonce-less connects rejected. Must use v2 signatures.
   - **Impact:** We recently upgraded device scopes. Verified on v2 signatures. **NONE**

### Providers (OpenRouter)

6. **OpenRouter cache_control injection** — Adds `cache_control` on system prompts for OpenRouter Anthropic models.
   - **Impact:** Better prompt-cache reuse on our OpenRouter Sonnet fallback. **BENEFITS**

7. **OpenRouter reasoning defaults** — Reasoning enabled by default when model advertises `reasoning: true`.
   - **Impact:** OpenRouter Sonnet fallback gets reasoning automatically. **BENEFITS**

8. **OpenRouter reasoning mapping** — `/think` levels mapped to `reasoning.effort` in embedded runs.
   - **Impact:** Reasoning control works on OpenRouter. **BENEFITS**

9. **OpenRouter provider preservation** — Stored session provider preserved for vendor-prefixed model IDs.
   - **Impact:** Follow-up turns on OpenRouter don't accidentally route to direct Anthropic. **BENEFITS**

10. **OpenRouter prefix preservation** — Required `openrouter/` prefix preserved during normalization.
    - **Impact:** Our `openrouter/auto` and `openrouter/free` refs stay intact. **BENEFITS**

11. **OpenRouter provider routing params** — Pass-through `params.provider` to request payloads.
    - **Impact:** Can configure provider routing preferences if needed. **NOTED**

### Anthropic Provider

12. **Context-1m beta skip** — Skips `context-1m-*` beta injection for OAuth/subscription tokens.
    - **Impact:** Prevents 401 errors if we ever use subscription tokens. **NOTED**

### Cron (major improvements)

13. **Cron max concurrent runs** — Honors `cron.maxConcurrentRuns` in timer loop.
    - **Impact:** If we add more cron jobs, they can run in parallel. **NOTED**

14. **Cron manual run timeout** — Same per-job timeout for manual `cron.run` as timer-driven runs. Abort propagation for isolated jobs.
    - **Impact:** Our `openclaw cron run` usage now has proper timeout enforcement. **BENEFITS**

15. **Cron manual run outside lock** — Manual runs execute outside cron lock so `cron.list`/`cron.status` stay responsive.
    - **Impact:** `openclaw cron list` won't hang during long forced runs. **BENEFITS**

16. **Cron fresh session IDs** — Isolated runs force fresh session IDs, never reuse prior context.
    - **Impact:** Each pipeline-check and daily-report gets a clean session. **BENEFITS**

17. **Cron auth propagation** — Auth-profile resolution propagated to isolated cron sessions.
    - **Impact:** Our cron jobs (Haiku) get proper auth. Fixes potential 401 errors. **BENEFITS**

18. **Cron status split** — Execution outcome (`lastRunStatus`) split from delivery outcome (`lastDeliveryStatus`).
    - **Impact:** Better diagnostics when a cron run succeeds but delivery fails. **BENEFITS**

19. **Cron schedule fix** — `every` jobs prefer `lastRunAtMs + everyMs` after restarts for consistent cadence.
    - **Impact:** Heartbeat (every 55m) timing more consistent across restarts. **BENEFITS**

20. **Cron watchdog timer** — Scheduler keeps polling even if a due-run tick stalls.
    - **Impact:** Cron jobs won't miss firing windows during stalled runs. **BENEFITS**

21. **Cron startup catch-up timeout** — Timeout guards for catch-up replay runs.
    - **Impact:** Missed jobs during restart won't hang indefinitely. **BENEFITS**

22. **Cron run log hygiene** — Cleans up settled queue entries, hardens path resolution.
    - **Impact:** Less memory leak from long-running cron uptime. **BENEFITS**

23. **Cron gateway responsiveness** — `cron.list`/`cron.status` responsive during startup catch-up.
    - **Impact:** CLI management works during gateway boot. **BENEFITS**

24. **Cron delivered state** — Persists `delivered` state so delivery failures visible in status/logs.
    - **Impact:** Better cron monitoring. **BENEFITS**

### Auth Profiles

25. **Auth profile cooldown fix** — Cooldown windows immutable across retries. Prevents retry loops trapping gateways.
    - **Impact:** Critical fix. Our cron jobs won't get stuck in cooldown loops. **BENEFITS**

### Memory

26. **Memory embedding cap** — 8k per-input safety cap before batching, 2k fallback for local providers.
    - **Impact:** Our local embeddinggemma-300m won't fail on oversized chunks during sync. **BENEFITS**

27. **Memory source-set change detection** — Detects memory source changes and triggers reindex without `--force`.
    - **Impact:** If we enable session indexing, automatic reindex on source change. **BENEFITS**

### Gateway

28. **Gateway restart fixes** — Stale-process kill prevention, lock reacquisition, health verification after restart.
    - **Impact:** `sudo systemctl restart openclaw` more reliable. **BENEFITS**

29. **Gateway lock improvement** — Port reachability as primary stale-lock signal.
    - **Impact:** Fewer false "already running" lockouts after unclean exits. **BENEFITS**

30. **Gateway config reload** — Structural comparison for array-valued paths, retry on missing snapshots.
    - **Impact:** Config changes don't trigger false restart-required reloads. **BENEFITS**

31. **Config prototype pollution fix** — Blocks `__proto__`, `constructor`, `prototype` traversal during config merge.
    - **Impact:** Critical security fix for config mutation flows. **BENEFITS**

32. **Config path traversal hardening** — Rejects prototype-key segments in `config get/set/unset`.
    - **Impact:** Hardened config CLI. **BENEFITS**

### Telegram (additional fixes)

33. **Telegram media error replies** — User-facing reply when media download fails (non-size errors).
    - **Impact:** Gregor tells user when media download fails instead of silently dropping. **BENEFITS**

34. **Telegram webhook keepalive** — Monitors alive until gateway abort, prevents false channel exits.
    - **Impact:** Telegram connection more stable. **BENEFITS**

35. **Telegram polling improvements** — Retry recoverable failures, clear webhooks before polling, safe offset watermark.
    - **Impact:** Polling mode more resilient to network hiccups. **BENEFITS**

36. **Telegram forward bursts** — Coalesces forwarded text+media through debounce window.
    - **Impact:** Forwarded media handled as group, not individual messages. **BENEFITS**

37. **Telegram streaming fixes** — Correct preview mapping, clean stale reasoning bubbles.
    - **Impact:** Multi-message streaming more reliable. **BENEFITS**

38. **Telegram reply dedupe** — Scoped to same-target only, normalizes media path variants.
    - **Impact:** Cross-target tool sends won't suppress final replies. **BENEFITS**

39. **Telegram WSL2** — Disables `autoSelectFamily` on WSL2, memoizes detection.
    - **Impact:** Not running WSL2 on VPS, but noted. **NONE**

40. **Telegram DNS ordering** — Defaults to `ipv4first` on Node 22+. Configurable via `channels.telegram.network.dnsResultOrder`.
    - **Impact:** Reduces IPv6 fetch failures. New config key available. **BENEFITS**

41. **Telegram native commands** — Sets `ctx.Provider="telegram"` for slash commands.
    - **Impact:** `/elevated` and provider-gated commands work correctly. **BENEFITS**

42. **Telegram `fetch failed` recovery** — Classifies undici `TypeError: fetch failed` as recoverable.
    - **Impact:** Transient network failures don't kill polling. **BENEFITS**

### Agents & Compaction

43. **Compaction count accuracy** — Only counts after completed auto-compactions.
    - **Impact:** `compactionCount` accurate. **BENEFITS**

44. **Compaction stale usage stripping** — Strips pre-compaction usage snapshots from replay, preventing immediate re-trigger.
    - **Impact:** No more destructive follow-up compactions after compaction. **BENEFITS**

45. **Session resilience** — Ignores invalid `sessionFile` metadata, falls back to safe path.
    - **Impact:** Sessions recover from corrupt metadata. **BENEFITS**

46. **Exec background timeout** — Background sessions no longer killed by default exec timeout.
    - **Impact:** Long-running background jobs work correctly. **BENEFITS**

### Security

47. **CLI config redaction** — Redacts sensitive values in `openclaw config get` terminal output.
    - **Impact:** API keys don't appear in terminal history. **BENEFITS**

48. **Exec obfuscation detection** — Detects obfuscated commands before allowlist decisions.
    - **Impact:** Obfuscated shell commands require explicit approval. **BENEFITS**

49. **Shell env hardening** — Validates login-shell paths, blocks `HOME`/`ZDOTDIR`/`SHELLOPTS`/`PS4` overrides.
    - **Impact:** Prevents shell startup-file injection attacks. **BENEFITS**

50. **Logging cap** — `logging.maxFileBytes` defaults to 500 MB.
    - **Impact:** Prevents disk exhaustion from error storms. **BENEFITS**

51. **Security audit command** — New findings for open group policies, dangerous node commands.
    - **Impact:** `openclaw security audit` more comprehensive. **NOTED**

52. **Gateway pairing fixes** — `operator.admin` satisfies all `operator.*` scope checks. Auto-approve loopback scope-upgrade. Read/write in default scope bundles.
    - **Impact:** Our full operator scope works correctly now. No more pairing loops. **BENEFITS**

### New Features

53. **Auto-updater** — Optional `update.auto.*` config, default-off.
    - **Impact:** Could enable auto-updates for non-breaking patches. **CONSIDER**

54. **Update dry-run** — `openclaw update --dry-run` previews actions.
    - **Impact:** Safe pre-update check. **NOTED**

55. **Control UI cron** — Full web cron editor with run history.
    - **Impact:** If we SSH-tunnel Control UI, can manage cron visually. **NOTED**

56. **Mistral provider** — New provider support including memory embeddings.
    - **Impact:** New provider option. **NOTED**

57. **Web search Gemini** — Grounded Gemini provider for web search tool.
    - **Impact:** New web search option. **NOTED**

### New Config Keys

- `update.auto.*` — Auto-updater configuration
- `channels.<channel>.streaming` — Unified streaming enum
- `channels.telegram.webhookPort` — Telegram webhook port
- `channels.telegram.network.dnsResultOrder` — DNS ordering override
- `logging.maxFileBytes` — Log file size cap (default 500 MB)
- `session.maintenance.maxDiskBytes` / `highWaterBytes` — Session disk budgets
- `cron.maxConcurrentRuns` — Parallel cron execution limit

---

## v2026.3.2

Upgraded 2026-03-03 from v2026.2.26 (skipping v2026.3.1). Gateway restarted, Telegram connection verified via doctor.

### Breaking Changes

1. **`tools.allow` renamed to `tools.alsoAllow`** — The `tools.allow` allowlist key now rejects unknown entries and disables the allowlist entirely. Must migrate to `tools.alsoAllow` for additive tool enablement (e.g., `cron` outside the profile).
   - **Impact:** Our `tools.allow: ["cron"]` broke on upgrade — gateway logged `tools.allow allowlist contains unknown entries (cron)`. Migrated to `tools.alsoAllow: ["cron"]`. **APPLIED**

2. **`tools.profile` default → `messaging`** — New installs default to `messaging` profile instead of broad coding/system access.
   - **Impact:** Our existing `tools.profile: "full"` is preserved. Only affects new onboarding. **NONE**

3. **ACP dispatch enabled by default** — `acp.dispatch.enabled` now defaults to `true`.
   - **Impact:** We don't use ACP. No immediate impact, but set `acp.dispatch.enabled: false` if ACP dispatch causes unexpected behavior. **NOTED**

4. **Plugin SDK `registerHttpHandler()` removed** — Replaced by `registerHttpRoute()`.
   - **Impact:** We use no custom plugins. **NONE**

### Telegram

5. **Telegram streaming default → `partial`** — New installs get live preview streaming out of the box.
   - **Impact:** Existing config with explicit streaming value unaffected. If we ever re-onboard, streaming will default to `partial`. **NOTED**

6. **Telegram restart polling teardown** — Stops Telegram bot instance when polling cycle exits so SIGUSR1 restarts fully tear down old long-poll loops. Reduces post-restart `getUpdates` 409 conflict storms.
   - **Impact:** Our restarts should have fewer 409 conflicts. **BENEFITS**

7. **Telegram plugin command validation** — Validates and normalizes plugin command name/description at registration. Guards native menu normalization preventing crashes from malformed specs.
   - **Impact:** More robust command registration. **BENEFITS**

8. **Telegram models picker compact callbacks** — Falls back to compact callback payloads for long model buttons, avoiding Telegram 64-byte callback truncation.
   - **Impact:** Model selection buttons work reliably. **BENEFITS**

### Cron & Heartbeat

9. **Cron session reaper reliability** — Moves cron session reaper sweeps into `onTimer` `finally` block. Keeps pruning active even when timer ticks fail.
   - **Impact:** Prevents stale isolated cron sessions from accumulating — directly relevant to our compaction loop prevention. **BENEFITS**

10. **Cron `HEARTBEAT_OK` suppression** — Two separate fixes (#32093, #32131) suppress `HEARTBEAT_OK` ack noise from reaching user chat in isolated announce mode.
    - **Impact:** If heartbeat delivery is ever enabled, internal ack tokens won't leak to Telegram. **BENEFITS**

11. **Cron store migration** — Normalizes legacy cron jobs with string schedules and old-format fields on load.
    - **Impact:** Prevents schedule-error loops from old persisted stores. **BENEFITS**

12. **Cron delivery mode `none` disables messaging tool** — When `delivery.mode` is `"none"`, the agent messaging tool is disabled. Cron editor sends explicit `delivery: { mode: "none" }` for both add and update.
    - **Impact:** Cron runs with `none` delivery can't accidentally send messages. **BENEFITS**

13. **Heartbeat model hot-reload** — `models.*` and `agents.defaults.model` config changes are now heartbeat hot-reload triggers.
    - **Impact:** Can change Gregor's model without full gateway restart. **BENEFITS**

14. **Lightweight bootstrap for automation** — Opt-in `--light-context` for cron and `agents.*.heartbeat.lightContext` for heartbeat. Heartbeat keeps only `HEARTBEAT.md`, cron skips bootstrap-file injection.
    - **Impact:** Can reduce token cost for heartbeat/cron runs. **CONSIDER**

### Providers (OpenRouter)

15. **HTTP 529 → rate_limit classification** — Provider overload (HTTP 529, common with Anthropic-compatible APIs) now classified as `rate_limit`, triggering model failover.
    - **Impact:** OpenRouter 529 errors (overload) now trigger our fallback chain instead of hard failure. **BENEFITS**

16. **OpenRouter x-ai compatibility** — Skips `reasoning.effort` injection for `x-ai/*` models (e.g., Grok) on OpenRouter.
    - **Impact:** If we ever route through Grok, reasoning params won't break. **NOTED**

### Memory & Context

17. **Ollama memory embeddings** — `memorySearch.provider` and `memorySearch.fallback` now accept `"ollama"`.
    - **Impact:** Alternative to our local `embeddinggemma-300m`. Could simplify memory config. **CONSIDER**

18. **Bootstrap file refactoring** — New truncation strategy: 70/20/10 split (head/tail/marker) for oversized files. Documented caps: `bootstrapMaxChars` (20k/file), `bootstrapTotalMaxChars` (150k total).
    - **Impact:** Better handling of large workspace files in context. **BENEFITS**

19. **Task continuity across compaction** — New `TASKS.md` ledger for task state persistence across compaction boundaries with post-compaction recovery.
    - **Impact:** Agent tasks survive compaction. **BENEFITS**

20. **Compaction identifier preservation policy** — New policy for preserving identifiers through compaction.
    - **Impact:** Key context identifiers survive compaction. **BENEFITS**

### Agents & Sessions

21. **Claude 4.6 adaptive thinking default** — `adaptive` is now the default thinking level for Claude 4.6 models. Other reasoning-capable models stay at `low`.
    - **Impact:** If we route through Anthropic Claude directly, thinking adapts to task complexity. Not relevant for OpenRouter Sonnet. **NOTED**

22. **Thinking fallback retry** — When providers reject unsupported thinking levels, retries with `think=off` instead of hard failing.
    - **Impact:** Prevents agent hangs during model/provider fallback chains. **BENEFITS**

23. **Subagent completion typed events** — Ad-hoc completion handoff replaced with typed `task_completion` events, rendered consistently across surfaces.
    - **Impact:** Internal change. More reliable subagent completion. **BENEFITS**

24. **Session lifecycle redesign** — TTL model replaced with broader lifecycle management. `idleHours` + `maxAgeHours` model.
    - **Impact:** Session management improved internally. **BENEFITS**

25. **Subagent input validation** — Rejects malformed `agentId` inputs (error messages, path-like strings) preventing synthetic agent IDs.
    - **Impact:** Prevents ghost workspace paths from bad inputs. **BENEFITS**

### CLI

26. **`openclaw config validate`** — New command validates config before gateway startup. Reports detailed invalid-key paths.
    - **Impact:** Catches the exact class of misconfiguration that previously caused crashes (e.g., `context` vs `agents.defaults.contextPruning`). **BENEFITS**
    - **Guide:** Phase 14 should mention as a pre-restart check. **GUIDE**

27. **`openclaw config file`** — Prints the active config file path.
    - **Impact:** Useful for debugging which config is active. **NOTED**

### Gateway

28. **Health/readiness endpoints** — New `/health`, `/healthz`, `/ready`, `/readyz` endpoints for Docker/K8s probes.
    - **Impact:** Our VPS setup doesn't need these, but confirms gateway is reachable. **NOTED**

29. **Gateway WS flood protection** — Closes repeated unauthorized WS request floods, samples duplicate rejection logs.
    - **Impact:** Reduces log spam from unauthorized connection attempts. **BENEFITS**

30. **Config backups hardened** — Owner-only (`0600`) permissions on rotated config backups. Orphan `.bak.*` files cleaned.
    - **Impact:** API keys in config backups no longer world-readable. **BENEFITS**

### Tools

31. **Native PDF analysis tool** — First-class `pdf` tool with Anthropic and Google provider support. Configurable via `agents.defaults.pdfModel`, `pdfMaxBytesMb`, `pdfMaxPages`.
    - **Impact:** Gregor can now analyze PDFs natively. **BENEFITS**

32. **SecretRef expanded coverage** — 64 credential targets now support SecretRef. Unresolved refs fail fast on active surfaces.
    - **Impact:** If we ever move to SecretRef for API keys, coverage is comprehensive. **NOTED**

### Security

33. **TOCTOU symlink race fix in `writeFileWithinRoot`** — Opens files without truncation, creates with `O_EXCL`, defers truncation until post-open validation, removes out-of-root artifacts on blocked races. Regression tests added.
    - **Impact:** Critical fix for host filesystem protection. **BENEFITS**

34. **Sandbox media staging symlink escape blocked** — Replaces direct copies with root-scoped safe writes for both local and SCP-staged attachments.
    - **Impact:** Blocks out-of-workspace file overwrite via media alias traversal. **BENEFITS**

35. **Webhook auth-before-body parsing** — BlueBubbles and Google Chat webhook handlers now authenticate before reading request body. Size + timeout budgets enforced.
    - **Impact:** Prevents unauthenticated slow-body DoS on webhook endpoints. **BENEFITS**

36. **Prompt spoofing hardening** — Runtime events routed through trusted system context. Inbound `[System Message]` and `System:` markers neutralized.
    - **Impact:** Directly relevant for Telegram-facing bot — reduces prompt injection surface. **BENEFITS**

37. **Gateway canonicalization hardening** — Plugin route paths decoded to canonical fixpoint. Fails closed on anomalies. Auth enforced on encoded `/api/channels/*` variants.
    - **Impact:** Prevents auth bypass via encoded path variants. **BENEFITS**

38. **Plugin HTTP hardening** — Explicit auth required for route registration. Ownership guards on duplicate registrations.
    - **Impact:** Stronger plugin isolation. **BENEFITS**

39. **Cross-agent sandbox inheritance** — Blocks sandboxed sessions from spawning unsandboxed cross-agent subagents.
    - **Impact:** Prevents sandbox bypass via `sessions_spawn`. **BENEFITS**

40. **Exec approval cwd revalidation** — Working directory identity revalidated before execution. Fails closed on drift.
    - **Impact:** Prevents stale approval exploitation. **BENEFITS**

41. **Exec approval argv semantics preserved** — Wrapper argv semantics maintained during approval hardening.
    - **Impact:** Approved commands can't drift into different runtime shapes. **BENEFITS**

42. **Config validation security** — Invalid keys now reported with detailed paths in startup errors.
    - **Impact:** Combined with `openclaw config validate`, catches misconfiguration before crash. **BENEFITS**

43. **Post-compaction audit injection removed** — Layer 3 fake system message (referencing non-existent `WORKFLOW_AUTO.md`) deleted. Was a prompt injection vector.
    - **Impact:** Removes a prompt injection surface. **BENEFITS**

44. **Sandbox workspace mount read-only** — `/workspace` bind mounts default to read-only when `workspaceAccess` is not `rw`.
    - **Impact:** Stronger sandbox isolation. **BENEFITS**

45. **Skills archive extraction hardened** — Tar safety checks unified, size limits enforced, TOCTOU detection between preflight and extraction.
    - **Impact:** Prevents skill install attacks. **BENEFITS**

46. **Loopback origin enforcement** — Dev mode allowance tied to actual socket address, not Host header claims.
    - **Impact:** Hardens our loopback gateway against spoofed Host headers. **BENEFITS**

### Known Regressions in v2026.3.1 (carried into 3.2)

47. **Aggressive compaction loop (Issue #32106)** — All agents compact every 2-3 minutes regardless of conversation length. Root cause: auto-enable OpenAI Responses compaction + `softThresholdTokens` defaulting to 4000. Our `contextPruning` config may mitigate, but monitor post-upgrade.
    - **Impact:** Watch for excessive compaction in Gregor's logs. **INVESTIGATE**

### New Config Keys

- `tools.alsoAllow` — Replaces `tools.allow` for additive tool enablement
- `agents.defaults.pdfModel` / `pdfMaxBytesMb` / `pdfMaxPages` — PDF tool configuration
- `agents.*.heartbeat.lightContext` — Lightweight bootstrap for heartbeat runs
- `cli.banner.taglineMode` — Startup tagline control (`random`/`default`/`off`)
- `acp.dispatch.enabled` — ACP dispatch toggle (now defaults `true`)
- `memorySearch.provider` / `memorySearch.fallback` — Now accept `"ollama"`
- `tools.media.audio.echoTranscript` / `echoFormat` — Audio transcript echo
- `agents.defaults.bootstrapMaxChars` / `bootstrapTotalMaxChars` — Bootstrap injection caps
- `channels.telegram.dmPolicy` — DM access policy (`pairing`/`allowlist`/`open`/`disabled`)
- `disableAudioPreflight` — Per-group/topic voice mention preflight skip
- `params.openaiWsWarmup` — Per-model WebSocket warm-up toggle

---

## v2026.3.3

### Telegram & ACP

1. **Telegram topic-to-agent routing** — Durable ACP channel/topic bindings route text-only jobs to correct channels.
   - **Impact:** If we ever use topic-based routing, bindings persist across restarts. **NOTED**

2. **ContextEngine plugin slot** — New compaction lifecycle hooks: bootstrap, ingest, assemble, compact, afterTurn, prepareSubagentSpawn, onSubagentEnded.
   - **Impact:** Opt-in plugin interface. No change if no context engine plugin configured. Zero behavior change for existing setups. **NOTED**

3. **Web search improvements** — Perplexity Search API integration, richer locale/time filters.
   - **Impact:** If web search tool is enabled, better results. We don't currently use it. **NOTED**

4. **SecretRef hardening** — Gateway auth handling improvements for SecretRef expansion.
   - **Impact:** Improved SecretRef robustness. **BENEFITS**

---

## v2026.3.4

### Routing & Startup

1. **Durable ACP bindings for Discord channels** — Topic-level agentId overrides for reply routing precision.
   - **Impact:** Discord-specific. **NONE**

2. **Fail-closed config loading** — Invalid configs abort gateway startup instead of degrading silently.
   - **Impact:** Critical change. If our config has ANY invalid keys, gateway won't start. Must run `openclaw config validate` before restart. **INVESTIGATE**

3. **Stale-socket restart guards** — Protection against hung socket connections during restart.
   - **Impact:** More reliable restarts. **BENEFITS**

4. **Safer onboarding defaults** — Reduces silent failure modes during initial setup.
   - **Impact:** Only affects new onboarding. **NONE**

---

## v2026.3.7

### ContextEngine & Lifecycle

1. **Full ContextEngine lifecycle hooks** — Complete plugin interface with bootstrap, ingest, assemble, compact, afterTurn, prepareSubagentSpawn, onSubagentEnded.
   - **Impact:** Zero behavior change when no context engine plugin configured. LegacyContextEngine wrapper auto-enabled for backward compatibility. **NOTED**

2. **Scoped subagent runtime** — AsyncLocalStorage-based runtime scoping for subagents.
   - **Impact:** Internal reliability improvement. **BENEFITS**

3. **Gateway sessions.get method** — New method for session retrieval.
   - **Impact:** Internal API improvement. **NOTED**

### Fixes & Improvements

4. **xAI web-search collision guard** — Prevents tool name collision between native web-search and xAI provider.
   - **Impact:** We don't use xAI. **NONE**

5. **TUI token copy-safety** — Rendering enhancements for token display.
   - **Impact:** Terminal rendering improvement. **NOTED**

6. **Agent compaction continuity** — Improved compaction behavior across agent sessions.
   - **Impact:** Better compaction reliability. May help with the #32106 compaction loop regression. **BENEFITS**

7. **Memory/QMD index isolation** — Memory index separated per-agent.
   - **Impact:** Cleaner memory index management. **BENEFITS**

---

## v2026.3.8

Upgrading 2026-03-09 from v2026.3.2.

### Major Features

1. **`openclaw backup create` & `openclaw backup verify`** — Native local state archive commands.
   - Options: `--only-config` (config-only), `--no-include-workspace` (exclude workspace files)
   - Manifest/payload validation via `verify` subcommand
   - Better archive naming for date sorting
   - Pre-upgrade/destructive flow guidance
   - **Impact:** Potential replacement for our custom `backup.sh`. Test both and compare coverage. **INVESTIGATE**

2. **ACP Provenance Metadata** — `openclaw acp --provenance off|meta|meta+receipt`.
   - Optional ACP ingress metadata capture, visible receipt injection, session trace ID retention.
   - **Impact:** New security feature for agent identity verification. Opt-in. **CONSIDER**

3. **Telegram cron announce delivery fix** — Routes text-only jobs through real outbound adapters.
   - Fixes: cron no longer reports `delivered: true` when message never reached Telegram.
   - Resolves longstanding "silent failure" for announce jobs.
   - **Impact:** Fixes KNOWN-BUGS.md root cause 1.4 (Cron announce-mode injection). Does NOT fix root causes 1.1-1.3, 1.5-1.7 which are separate bugs. Keep `streamMode: "off"` workaround for non-cron dupes. **BENEFITS**

4. **Bundled plugin priority** — Plugin onboarding prefers bundled plugins over npm-installed copies with same ID.
   - Clears discovery cache before reload after plugin install.
   - **Impact:** Prevents shadowing of bundled plugins (Matrix, Feishu, etc.). **BENEFITS**

5. **CLI short git commit hash** — `openclaw --version` now includes git commit hash.
   - **Impact:** Better version identification. **BENEFITS**

### Security Fixes

6. **12+ security fixes** — Aggregate of fixes across v2026.3.3-3.8 including:
   - Fail-closed config loading (3.4)
   - Stale-socket restart guards (3.4)
   - SecretRef hardening (3.3)
   - ContextEngine lifecycle isolation (3.7)
   - Memory/QMD index isolation (3.7)
   - Bundled plugin priority prevents shadowing (3.8)
   - **Impact:** All auto-applied on upgrade. **BENEFITS**

### New Config Keys

- `acp.provenance` — ACP provenance level (`off`/`meta`/`meta+receipt`)

### New CLI Commands

- `openclaw backup create [--only-config] [--no-include-workspace] [--output path]`
- `openclaw backup verify <archive>`
- `openclaw acp --provenance <level>`

---

## v2026.3.11

Released 2026-03-12. Security fix + cron breaking change.

### Breaking Changes

1. **Cron/doctor: tightened isolated delivery** — Prevents ad hoc notifies and fallback summaries in isolated cron sessions. Requires `openclaw doctor --fix --non-interactive` migration.
   - **Impact:** Our cron jobs run in isolated sessions. Doctor migration applied on upgrade. **APPLIED**

### Security

2. **WebSocket browser origin validation** — Enforces browser origin validation for all browser-originated connections regardless of proxy headers. Closes cross-site WebSocket hijacking in trusted-proxy mode.
   - **Impact:** Our gateway is loopback-only so not directly exploitable, but defense-in-depth. **BENEFITS**

### Agents & Context

3. **Agent text sanitization** — Strips leaked model control tokens (GLM-5, DeepSeek internal delimiters) from assistant text before delivery.
   - **Impact:** If Gregor ever routes through providers that leak control tokens, they won't reach Telegram. **BENEFITS**

4. **Context pruning improvements** — Prunes image-only results, aligns coverage.
   - **Impact:** Better context management for image-heavy sessions. **BENEFITS**

5. **Agents/billing recovery** — Probes single-provider cooldowns on existing throttle. Treats HTTP 499 as transient, recognizes Venice/Poe billing errors.
   - **Impact:** Better fallback chain resilience. **BENEFITS**

6. **Agents/cooldowns** — Defaults unknown failures to "unknown" instead of "rate_limit". Resets expired error counters before computing backoff.
   - **Impact:** More accurate cooldown behavior. **BENEFITS**

7. **Agents/memory flush** — Forwards flush write paths through embedded runs.
   - **Impact:** Memory flush more reliable in subagent contexts. **BENEFITS**

### Telegram

8. **Telegram outbound HTML chunking** — Chunks long messages, preserves fallback params.
   - **Impact:** Long Gregor responses won't fail on Telegram's message size limits. **BENEFITS**

9. **Telegram final preview delivery** — Splits lifecycle from cleanup retention.
   - **Impact:** Streaming preview messages handled more cleanly. **BENEFITS**

### Memory

10. **Multimodal memory indexing** — Opt-in image/audio indexing with Gemini `gemini-embedding-2-preview`.
    - **Impact:** New capability. Would require Gemini API key. **CONSIDER**

### New Features

11. **Exec/child `OPENCLAW_CLI` env var** — Subprocesses can detect when launched from OpenClaw CLI.
    - **Impact:** Scripts spawned by Gregor can detect OpenClaw context. **NOTED**

12. **`sessions_yield` for orchestrators** — ACP subagents can end turns and skip queued tool work via `sessions_spawn resumeSessionId`.
    - **Impact:** Future orchestration capability. **NOTED**

### Fixes

13. **iOS/macOS gateway foreground recovery** — Immediate reconnect after stale sockets teardown.
    - **Impact:** Platform-specific. **NONE**

14. **Gateway config errors surfaced** — Up to three validation issues with details.
    - **Impact:** Better error messages on config problems. **BENEFITS**

15. **Sessions/reset model** — Clears stale metadata before recompute.
    - **Impact:** More reliable model switching. **BENEFITS**

---

## v2026.3.12

Upgraded 2026-03-13 from v2026.3.8. Gateway restarted, Telegram verified, `doctor --fix` applied. `node-llama-cpp` peer dependency manually installed (npm doesn't auto-install global peer deps).

### Security (Major — 12+ fixes)

1. **Device pairing: short-lived bootstrap tokens** — Replaces embedded shared credentials with short-lived bootstrap tokens for device pairing.
   - **Impact:** Significant hardening of the pairing flow. Our DM pairing is already locked, but this closes a class of credential replay attacks. **BENEFITS**

2. **Disabled implicit workspace plugin auto-load** — Plugins in workspace directories no longer auto-execute without explicit enablement.
   - **Impact:** Prevents unauthorized code execution from workspace files. Directly relevant — Gregor's workspace could theoretically contain malicious plugin files. **BENEFITS**

3. **Invisible Unicode escaping in approval prompts** — Escapes invisible Unicode characters in tool approval prompts.
   - **Impact:** Prevents prompt injection via invisible characters in tool call displays. **BENEFITS**

4. **Unicode normalization before obfuscation checks** — Normalizes Unicode before checking for obfuscated commands.
   - **Impact:** Closes Unicode-based exec obfuscation bypass. **BENEFITS**

5. **Sender ownership for `/config` and `/debug`** — Requires sender ownership verification for config and debug slash commands.
   - **Impact:** Prevents unauthorized config access even in shared chat contexts. **BENEFITS**

6. **Unbound scope clearing on shared-token WebSocket** — Clears unbound scopes on shared-token WebSocket connects.
   - **Impact:** Prevents scope escalation via stale WebSocket sessions. **BENEFITS**

7. **Persistent browser profile blocking** — Blocks persistent browser profile operations from write-scoped requests.
   - **Impact:** Prevents browser state persistence attacks. **BENEFITS**

8. **Public spawned-run lineage rejection** — Rejects public spawned-run lineage fields.
   - **Impact:** Prevents lineage spoofing in agent runs. **BENEFITS**

9. **Sandbox session-tree visibility** — Enforces sandbox session-tree visibility in `session_status`.
   - **Impact:** Sandboxed sessions can't inspect parent session state. **BENEFITS**

10. **Hooks: fail-closed on unresolvable paths** — Hook loader fails closed when paths can't be resolved.
    - **Impact:** Prevents hook bypass via path manipulation. **BENEFITS**

11. **POSIX case sensitivity in allowlist patterns** — Preserves POSIX case sensitivity in allowlist patterns.
    - **Impact:** Prevents case-based allowlist bypass on case-sensitive filesystems. **BENEFITS**

12. **Hook delivery deduplication** — Agent deliveries deduped by optional idempotency key.
    - **Impact:** Prevents duplicate hook-triggered actions. **BENEFITS**

### Telegram

13. **Telegram model picker persistence** — Persistent inline model selections and proper fallback handling.
    - **Impact:** Model selection via Telegram inline keyboard now survives restarts. **BENEFITS**

14. **Cron isolated sends excluded from resend queue** — Isolated cron sends no longer enter the resend queue, preventing duplicates.
    - **Impact:** Another duplicate message fix (KNOWN-BUGS.md). Our `streamMode: "off"` stays, but this fixes one more root cause. **BENEFITS**

15. **TUI duplicate assistant message fix** — Fixed duplicate rendering in streaming runs.
    - **Impact:** TUI-specific. **NONE**

16. **Mattermost duplicate fix** — Block streaming deduplication for Mattermost.
    - **Impact:** Platform-specific. **NONE**

### Agents & Subagents

17. **Subagent completion timeout raised to 90s** — Stops retrying gateway timeouts for completion announces.
    - **Impact:** Complex subagent tasks get more time to announce completion. **BENEFITS**

18. **Ollama/vLLM/SGLang → provider-plugin architecture** — Moved to plugin-based provider registration.
    - **Impact:** If we ever add local Ollama, it's now a plugin. Architecture change. **NOTED**

19. **GPT-5.4 and Anthropic Claude fast mode** — `/fast` toggle maps to Anthropic `service_tier` requests. Session-level toggles.
    - **Impact:** New speed/cost option if Anthropic supports `service_tier` for our tier. **CONSIDER**

20. **Slack Block Kit support** — Agent replies support Block Kit messages.
    - **Impact:** Platform-specific. **NONE**

### Gateway & Infrastructure

21. **Control UI dashboard-v2** — Modular views (overview, chat, config, agent, session), command palette, mobile bottom tabs.
    - **Impact:** If we SSH-tunnel the Control UI, significant UX upgrade. **NOTED**

22. **Kubernetes deployment manifests** — Raw K8s manifests and Kind setup documentation for containerized gateway deployment.
    - **Impact:** Alternative deployment model. We use VPS + systemd. **NOTED** (see separate research)

### Fixes

23. **Gateway session discovery** — Fixed disk-only and retired ACP session store discovery.
    - **Impact:** Session recovery more robust. **BENEFITS**

24. **Plugins/env-scoped roots** — Fixed discovery caches and provenance tracking.
    - **Impact:** Plugin management reliability. **BENEFITS**

25. **Models/OpenRouter canonicalization** — Canonicalized native model keys across operations.
    - **Impact:** More reliable OpenRouter model handling. **BENEFITS**

26. **Sandbox/write stdin preservation** — Preserved stdin to prevent empty file creation.
    - **Impact:** Sandbox write reliability. **BENEFITS**

### New Config Keys

- `service_tier` — Anthropic fast mode toggle (via `/fast`)

### Operational Notes

- `node-llama-cpp` is now a `peerDependency` (was optional). Global npm install doesn't auto-install peer deps — must manually install: `cd ~/.npm-global/lib/node_modules/openclaw && npm install node-llama-cpp@3.16.2`
- Upgrade removed 131 packages, added 20, changed 536 — significant dependency restructuring
- Startup time: 27s (normal range for restart)

---

## v2026.3.13

Released 2026-03-14 (auto-updated from v2026.3.12). **Rolled back to v2026.3.12** due to CLI→gateway WS RPC regression. Auto-update disabled until CLI fix lands.

> **Note:** The CLI WS regression exists on v2026.3.12 as well (discovered during rollback testing). It affects WS-based RPC commands (`cron list`, `cron runs`, gateway memory probe) but NOT simpler commands (`doctor`, `memory status`, `models list`, `config validate`). Telegram, cron execution, and all bot functionality are unaffected. Tracked upstream: #45560, #46716, #46117, #46100, #47103, #45222.

### Known Issues

1. **CLI→gateway WebSocket RPC broken** — CLI connects, receives `connect.challenge`, but connection closes with code 1000 "normal closure". Root cause: CLI not using paired device token for RPC calls, falls into scope-less auth path. Missing auth files (`auth-profiles.json`, `device-auth.json`, `.paired`).
   - **Impact:** Cannot run `openclaw cron list`, `openclaw cron runs`, or gateway memory probe from CLI. All other CLI commands work. Telegram and internal cron execution unaffected. **UPSTREAM BUG**

### New Features

2. **Browser automation** — Live Chrome session attachment via Chrome DevTools remote debugging. Batched actions, selector targeting, delayed clicks.
   - **Impact:** New capability. Would need browser installed on VPS and Chrome DevTools config. **CONSIDER**

3. **`OPENCLAW_TZ` env var for Docker** — Pins gateway and CLI containers to a chosen IANA timezone.
   - **Impact:** Docker-specific. **NONE**

### Telegram

4. **Plugin command/runtime hardening** — Validates and normalizes plugin command name/description at registration; guards Telegram native menu normalization so malformed specs can't crash startup.
   - **Impact:** Prevents startup crashes from malformed plugin specs. **BENEFITS**

5. **Telegram media download SSRF hardening** — Media downloads use the same direct/proxy transport policy into SSRF-guarded file fetches; IPv4 fallback for IPv6-broken hosts.
   - **Impact:** Fixes potential media download failures on our VPS. **BENEFITS**

6. **Telegram model picker persistence** — Inline model selections persist correctly, clears overrides when selecting default, validates fallback models.
   - **Impact:** Improved from 3.12 — model picker now fully persistent. **BENEFITS**

7. **Webhook auth hardening** — Validates webhook secret BEFORE reading/parsing request bodies. Unauthenticated requests rejected immediately.
   - **Impact:** If we ever enable webhooks, this prevents resource exhaustion from unauth requests. **BENEFITS**

8. **Guard duplicate-token checks** — Guards Telegram token normalization when account tokens are missing. Prevents `token.trim()` crashes.
   - **Impact:** Prevents edge-case startup crashes. **BENEFITS**

### Cron

9. **Isolated session deadlock fix** — Nested cron-triggered embedded runner work routed onto the nested lane so isolated cron jobs no longer deadlock when compaction or queued inner work runs.
   - **Impact:** Fixes a class of cron hangs during compaction. Our isolated cron sessions benefit. **BENEFITS**

10. **Doctor cron storage migration** — Adds `openclaw doctor --fix` migration for legacy cron storage and legacy notify/webhook delivery metadata.
    - **Impact:** Should run after upgrade. **APPLIED** (via doctor --fix)

### Security

11. **macOS exec approval trust binding** — Skill auto-allow trust bound to both executable name AND resolved path. Same-basename binaries no longer inherit trust.
    - **Impact:** macOS-specific. **NONE**

### Gateway

12. **Gateway status `--require-rpc`** — Clearer failure reporting for Linux non-interactive daemon-install.
    - **Impact:** Better diagnostics for service detection. **NOTED**

13. **Shared token auth on plain HTTP** — Preserves explicit shared token and password auth on plain-HTTP Control UI connects so LAN/reverse-proxy sessions don't drop auth before first WS handshake.
    - **Impact:** We use loopback + token auth. Could be related to CLI WS issue. **INVESTIGATE**

### Agents & Models

14. **Context engine plugin interface** — Full lifecycle hooks for context engine plugins.
    - **Impact:** Framework change. **NOTED**

15. **OpenAI-compatible compat overrides** — Respects explicit user `models[].compat` opt-ins for non-native openai-completions endpoints.
    - **Impact:** Relevant if using OpenRouter models that need compatibility overrides. **NOTED**

### Fixes

16. **Plugin-SDK bundling** — Shared build pass prevents duplicating chunks. Reduces memory.
    - **Impact:** Lower memory usage from plugins. **BENEFITS**

---

## v2026.3.22 / v2026.3.23

**Upgrade: v2026.3.12 → v2026.3.23-2** (skipping v2026.3.14–v2026.3.22 — no releases exist for those versions; jumped directly from v2026.3.13-1 to v2026.3.22). Installed 2026-03-24. v2026.3.22 had packaging bugs (bundled plugins and Control UI missing from npm tarball); v2026.3.23 fixes those; v2026.3.23-2 is a same-day hotfix patch. Documented together as a single upgrade.

> **CLI WS RPC regression: FIXED.** The blocker from v2026.3.13 (#45560, #46716, #47103) is resolved. PR #50101 fixed operator scope preservation during device-auth bypass. `openclaw cron list`, `cron runs`, and gateway memory probe all work again.

### Breaking Changes

1. **Plugin SDK migration** — `openclaw/extension-api` → `openclaw/plugin-sdk/*`. Custom and external plugins may need path updates.
   - **Impact:** LCM (lossless-claw) is an external plugin. Must verify it loads correctly post-upgrade. **INVESTIGATE**

2. **Chrome MCP extension relay removed** — Browser extension-based MCP relay replaced with `existing-session` mode.
   - **Impact:** Run `openclaw doctor --fix` to migrate. We don't use browser MCP. **APPLIED** (via doctor --fix)

3. **Legacy env vars removed** — `CLAWDBOT_*`, `MOLTBOT_*` prefixes removed. Must use `OPENCLAW_*`.
   - **Impact:** We already use `OPENCLAW_*` env vars. No impact. **NONE**

4. **ClawHub becomes default plugin store** — Plugin resolution prefers ClawHub before npm for discovery.
   - **Impact:** LCM installed via explicit npm spec (`@martian-engineering/lossless-claw`), not discovery. Low risk but watch for namespace squatting. **NOTED**

5. **Image generation standardized** — Legacy image gen tools replaced with core `image_generate`.
   - **Impact:** We don't use image generation in Gregor. **NONE**

6. **Plugin message discovery** — Tools must implement `ChannelMessageActionAdapter.describeMessageTool(...)`.
   - **Impact:** Affects plugin developers. LCM may need update if it uses message tools. **INVESTIGATE**

7. **Device pairing binding** — Pairing codes now bound to intended profile.
   - **Impact:** Tighter auth. Device-pair is disabled for us. **BENEFITS**

### Security (30+ improvements)

8. **File URL blocking** — Blocks `file://` media URLs and UNC paths before resolution. Prevents SMB credential handshakes on Windows.
   - **Impact:** Cross-platform security hardening. **BENEFITS**

9. **CSP hardening** — SHA-256 hashes for inline script blocks in index.html (Control UI).
   - **Impact:** Hardens Control UI against XSS. **BENEFITS**

10. **Plugin manifest validation** — Enhanced validation against marketplace sources, prevents malformed plugin manifests.
    - **Impact:** Hardens our LCM plugin trust. **BENEFITS**

11. **Exec environment sandbox restrictions** — JVM and dependency resolution injection hardening.
    - **Impact:** Tighter exec sandbox. Our `exec.security: full` means bot has autonomous shell, but this limits injection vectors. **BENEFITS**

12. **Webhook pre-auth** — Body limits and timeouts applied before auth checks.
    - **Impact:** Defense-in-depth for webhook path (we use polling, but the control path benefits). **BENEFITS**

13. **Device token enforcement** — Stricter device-auth for `operator.read` scope. This is the fix for the CLI WS RPC regression.
    - **Impact:** Directly fixes #45560/#46716. **APPLIED**

14. **Auth-profile credential reversion fix** (v2026.3.23) — Gateway no longer overwrites `auth-profiles.json` with stale in-memory OAuth tokens.
    - **Impact:** Fixes exactly the auth issue we hit on 2026-03-21 where OAuth profiles were silently reverting. **BENEFITS**

### Packaging Fixes (v2026.3.23)

15. **Bundled plugin runtime sidecars restored** — WhatsApp, Matrix, and other optional bundled plugins were missing from the v2026.3.22 npm tarball due to missing `OPENCLAW_INCLUDE_OPTIONAL_BUNDLED=1` in release workflow.
    - **Impact:** We don't use WhatsApp/Matrix, but it indicates v2026.3.22 had packaging issues. v2026.3.23 fixes this. **NONE** (but validates our "skip to 3.23" decision)

16. **Control UI assets restored** — `dist/control-ui/` directory was excluded from v2026.3.22 npm tarball.
    - **Impact:** Dashboard access fixed in v2026.3.23. **BENEFITS**

### Provider Support

17. **Native Anthropic Vertex AI** — Claude via Google Vertex.
    - **Impact:** New provider option. We use direct Anthropic. **NOTED**

18. **Qwen DashScope endpoints** — Standard pay-as-you-go + coding plan.
    - **Impact:** New provider option. **NOTED**

19. **Forward compatible models** — `gpt-5.4-mini`, `gpt-5.4-nano` aliases.
    - **Impact:** Future model support. **NOTED**

### Plugin Ecosystem

20. **ClawHub integration** — Skill/plugin discovery via ClawHub marketplace.
    - **Impact:** We use bundled-only + explicit npm installs. **NOTED**

21. **Pluggable sandbox backends** — SSH and OpenShell support for sandboxed execution.
    - **Impact:** NemoClaw/OpenShell integration path. See Reference/NEMOCLAW.md. **NOTED**

22. **Per-agent thinking/reasoning defaults** — Configure thinking mode per agent.
    - **Impact:** Could optimize Gregor's reasoning behavior per session type. **CONSIDER**

### Performance

23. **Gateway cold start reduced** — Minutes → seconds for startup.
    - **Impact:** Faster restarts. **BENEFITS**

24. **Bundled plugins from compiled dist/extensions** — Faster plugin loading.
    - **Impact:** Faster startup. **BENEFITS**

25. **Model catalog caching** — Cached by configuration state, reduces repeated resolution.
    - **Impact:** Faster model selection. **BENEFITS**

### Fixes

26. **Telegram threading context population** — Thread context correctly passed.
    - **Impact:** Better thread handling. **BENEFITS**

27. **OpenRouter auto-pricing recursion fix** — Prevents infinite recursion in pricing refresh.
    - **Impact:** Our OpenRouter fallback is more stable. **BENEFITS**

28. **Browser attachment timeouts** — Longer timeouts for slower systems.
    - **Impact:** If browser tool is used. **NOTED**

### Operational Notes

- Auto-update applied v2026.3.13 on March 14. Rolled back to v2026.3.12 on March 16 due to CLI WS regression.
- Auto-update cron disabled (`#PINNED-3.12#` prefix) until upstream fixes CLI auth.
- Check-only update script still runs daily (harmless).
- `node-llama-cpp` reinstalled after rollback.
- Startup time after rollback: ~2min (major version change direction).

---

## Config Decisions Tracker

Items extracted from changelogs that may influence our configuration.

| Decision | Source | Status | Priority |
|----------|--------|--------|----------|
| `tools.allow: ["cron"]` is NOT redundant — `group:automation` outside all profiles | v2026.2.24 #6 | RESOLVED | Medium |
| `security.trust_model.multi_user_heuristic` | v2026.2.24 #35 | DEFERRED — single-user VPS, no benefit now | Low |
| Per-agent `params.cacheRetention` for cron | v2026.2.23 #4 | DEFERRED — cron cost is already low (~$6/mo total) | Low |
| `openclaw sessions cleanup` for transcript hygiene | v2026.2.23 #11 | DEFERRED — disk space not yet a concern (68 sessions) | Medium |
| `update.auto.*` for auto-updates | v2026.2.22 #53 | REJECTED — custom `auto-update.sh` + `check-openclaw-update.sh` give more control | Low |
| `/verbose on` for debugging tool errors | v2026.2.22 #2 | NOTED | — |
| `tools.allow` → `tools.alsoAllow` migration | v2026.3.2 #1 | APPLIED | High |
| `acp.dispatch.enabled=false` if ACP causes issues | v2026.3.2 #3 | NOTED | Low |
| `agents.*.heartbeat.lightContext` to reduce cron/heartbeat cost | v2026.3.2 #14 | DEFERRED — heartbeat cost already acceptable (~$4.65/mo) | Medium |
| Ollama memory embeddings (`memorySearch.provider: "ollama"`) | v2026.3.2 #17 | REJECTED — local embeddinggemma via node-llama-cpp works well | Low |
| Monitor compaction loop regression (#32106) | v2026.3.2 #47 | RESOLVED — no compaction loops observed since v2026.3.8 | High |
| `openclaw config validate` as pre-restart check | v2026.3.2 #26 | APPLIED | High |
| Fail-closed config loading — validate before EVERY restart | v2026.3.4 #2 | APPLIED | High |
| `openclaw backup create` vs custom `backup.sh` — evaluate overlap | v2026.3.8 #1 | RESOLVED — both kept: native covers config+sessions+auth, custom covers SQLite+memory markdown | Medium |
| ACP provenance (`openclaw acp --provenance meta`) | v2026.3.8 #2 | DEFERRED — no multi-agent ACP use case yet | Low |
| Remove Telegram streaming workarounds after 3.8 cron fix | v2026.3.8 #3 | RESOLVED — keep `streamMode: "off"`. v2026.3.8 fixed cron delivery (1.4) but non-cron dupes (1.1-1.3, 1.5-1.7) still need it | Medium |
| `node-llama-cpp` peer dep — manual install needed on upgrade | v2026.3.12 ops | APPLIED | High |
| Cron isolated resend queue fix — another dupe root cause closed | v2026.3.12 #14 | BENEFITS | Medium |
| Device pairing bootstrap tokens — credential replay class closed | v2026.3.12 #1 | BENEFITS | High |
| Workspace plugin auto-load disabled — code execution risk closed | v2026.3.12 #2 | BENEFITS | High |
| Anthropic fast mode (`service_tier`) available via `/fast` | v2026.3.12 #19 | DEFERRED — Gregor's Sonnet latency is acceptable | Low |
| Multimodal memory indexing (Gemini embeddings) | v2026.3.11 #10 | DEFERRED — no Gemini API key, text memory sufficient | Low |
| K8s deployment manifests available — alternative to systemd | v2026.3.12 #22 | NOTED | Low |
| CLI WS RPC regression — `cron list`/`cron runs` broken | v2026.3.13 #1 | UPSTREAM BUG | High |
| Shared token auth on plain HTTP — may relate to CLI WS issue | v2026.3.13 #13 | INVESTIGATE | High |
| Browser automation via Chrome DevTools | v2026.3.13 #2 | DEFERRED — no browser use case for Gregor yet | Low |
| Cron isolated session deadlock fix | v2026.3.13 #9 | BENEFITS | Medium |
| Auto-update disabled — pinned to v2026.3.12 | v2026.3.13 ops | APPLIED | High |
| CLI WS RPC regression — FIXED in v2026.3.22 | PR #50101 — operator scope fix | RESOLVED | High |
| Auth-profile credential reversion fix | v2026.3.23 — stale token overwrite | BENEFITS | High |
| Plugin SDK migration — verify LCM compat | v2026.3.22 — extension-api → plugin-sdk/* | INVESTIGATE | High |
| ClawHub default plugin store — namespace squatting | v2026.3.22 — explicit spec is safe | NOTED | Low |
| Pluggable sandbox backends (OpenShell) | v2026.3.22 — NemoClaw integration path | CONSIDER | Low |
| Per-agent thinking/reasoning defaults | v2026.3.22 — customize per session type | CONSIDER | Medium |
| Re-enable auto-update cron | v2026.3.23 — CLI fix landed | APPLIED | High |
| Gateway cold start improvement | v2026.3.22 — faster startup | BENEFITS | Medium |
| ReadOnlyPaths + plugin auto-enable conflict | v2026.3.22 — needs write on first startup | DOCUMENTED | Medium |

## Guide Update Tracker

Changelog items that need reflection in GUIDE.md.

| Section | What Changed | Source | Status |
|---------|-------------|--------|--------|
| Phase 13.3 (Heartbeat) | DM delivery blocked; delivery default now `none` | v2026.2.24 #1, #3 | APPLIED |
| Phase 5 (Commands) | `/verbose on` required for tool error details | v2026.2.22 #2 | APPLIED |
| Phase 12.5 (Cron) | Multiple cron reliability improvements; `cron.maxConcurrentRuns` | v2026.2.22 #13-24 | APPLIED |
| Phase 14.7 (Context) | Session maintenance: `openclaw sessions cleanup` | v2026.2.23 #11 | APPLIED |
| Phase 14.6 (Context) | Bootstrap file caching reduces cache invalidations | v2026.2.23 #5 | APPLIED |
| Phase 13.2 (Cost) | Official prompt-caching docs published | v2026.2.23 #20 | APPLIED |
| Appendix F (CLI) | `openclaw memory search --query` syntax added | v2026.2.24 #26 | APPLIED |
| Appendix (CLI) | Doctor hints corrected to valid commands | v2026.2.24 #27 | N/A — no incorrect hints found |
| Phase 14 (Maintenance) | `openclaw config validate` as pre-restart check | v2026.3.2 #26 | APPLIED |
| Phase 13.3 (Heartbeat) | Heartbeat DM delivery default reverted to `allow` in 3.1, then unchanged in 3.2 | v2026.3.1 | APPLIED |
| Phase 12.5 (Cron) | Lightweight bootstrap mode for cron/heartbeat; session reaper reliability | v2026.3.2 #9, #14 | APPLIED |
| Appendix F (CLI) | `openclaw config file` and `openclaw config validate` added | v2026.3.2 #26, #27 | APPLIED |
| Phase 7.2 (Tools) | `tools.allow` → `tools.alsoAllow` migration required on upgrade | v2026.3.2 #1 | APPLIED |
| Appendix F (Backups) | `openclaw backup create/verify` native backup command | v2026.3.8 #1 | APPLIED |
| Appendix F (Config) | Fail-closed config loading — always validate before restart | v2026.3.4 #2 | APPLIED |
| Phase 12.5 (Cron) | Cron announce delivery fix — silent failure resolved | v2026.3.8 #3 | APPLIED |
| Phase 14 (Maintenance) | `node-llama-cpp` peer dep install step in upgrade procedure | v2026.3.12 ops | APPLIED |
| Phase 7 (Security) | Device pairing now uses short-lived bootstrap tokens | v2026.3.12 #1 | APPLIED |
| Phase 7 (Security) | Workspace plugin auto-load disabled by default | v2026.3.12 #2 | APPLIED |
| Phase 12.5 (Cron) | Isolated sends excluded from resend queue — dupe fix | v2026.3.12 #14 | APPLIED |
| Phase 14 (Maintenance) | Cron doctor migration required (`doctor --fix`) on upgrade | v2026.3.11 #1 | APPLIED |
| Appendix J (K8s) | K8s deployment manifests as alternative to systemd | v2026.3.12 #22 | APPLIED |
| Phase 7 (Security) | Security evolution table — cumulative hardening across versions | v2026.3.22 security | APPLIED (§7.18) |
| Phase 7 (Plugins) | Plugin SDK migration note, ClawHub default store | v2026.3.22 #1, #4 | APPLIED (§7.7 note) |
| Phase 14.9 (Upgrade) | CLI WS RPC fix — re-enable auto-update, remove #PINNED prefix | v2026.3.22 #13 | APPLIED |
| Phase 14.9 (Upgrade) | Auth-profile credential reversion fix — document gotcha | v2026.3.23 fix | APPLIED |
| Phase 14.9 (Upgrade) | ReadOnlyPaths + plugin auto-enable conflict documented | v2026.3.22 ops | APPLIED |
