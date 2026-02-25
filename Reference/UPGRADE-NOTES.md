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
   - **Impact:** May mean `tools.allow: ["cron"]` is now handled differently. Our explicit allow should still work, but test if the allow is now redundant. **INVESTIGATE**

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

## Config Decisions Tracker

Items extracted from changelogs that may influence our configuration.

| Decision | Source | Status | Priority |
|----------|--------|--------|----------|
| `tools.allow: ["cron"]` may be redundant | v2026.2.24 #6 | INVESTIGATE | Medium |
| `security.trust_model.multi_user_heuristic` | v2026.2.24 #35 | CONSIDER | Low |
| Per-agent `params.cacheRetention` for cron | v2026.2.23 #4 | CONSIDER | Low |
| `openclaw sessions cleanup` for transcript hygiene | v2026.2.23 #11 | CONSIDER | Medium |
| `update.auto.*` for auto-updates | v2026.2.22 #53 | CONSIDER | Low |
| `/verbose on` for debugging tool errors | v2026.2.22 #2 | NOTED | — |

## Guide Update Tracker

Changelog items that need reflection in GUIDE.md.

| Section | What Changed | Source |
|---------|-------------|--------|
| Phase 8 (Heartbeat) | DM delivery blocked; delivery default now `none` | v2026.2.24 #1, #3 |
| Phase 5 (Commands) | `/verbose on` required for tool error details | v2026.2.22 #2 |
| Phase 12 (Cron) | Multiple cron reliability improvements; `cron.maxConcurrentRuns` | v2026.2.22 #13-24 |
| Phase 14 (Context) | Session maintenance: `openclaw sessions cleanup` | v2026.2.23 #11 |
| Phase 14 (Context) | Bootstrap file caching reduces cache invalidations | v2026.2.23 #5 |
| Phase 13 (Cost) | Official prompt-caching docs published | v2026.2.23 #20 |
| Appendix (CLI) | `openclaw memory search --query` syntax added | v2026.2.24 #26 |
| Appendix (CLI) | Doctor hints corrected to valid commands | v2026.2.24 #27 |
