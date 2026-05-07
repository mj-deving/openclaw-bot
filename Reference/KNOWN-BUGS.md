# Known Bugs & Workarounds

Documented bugs affecting OpenClaw deployments, with root cause analysis, upstream tracking, and available mitigations. Focus on issues that are systemic (not one-off configuration mistakes) and affect production stability.

> **Last updated:** 2026-05-07 | **OpenClaw version:** v2026.5.6

---

## 1. Duplicate Message Delivery (Telegram)

**Severity:** High | **Status:** Partially fixed, multiple open issues | **Affected:** All channels, Telegram most common

OpenClaw sends duplicate messages to Telegram users. This is **not a single bug** — it is a systemic architectural weakness with **7+ distinct root causes** tracked across 15+ GitHub issues. The intermittent nature (sometimes duplicates, sometimes not) results from probabilistic factors like LLM response latency, provider load, and concurrent message timing.

### Root Cause Taxonomy

#### 1.1 Tool Execution Rapid-Fire — Issues [#18870](https://github.com/openclaw/openclaw/issues/18870), [#22258](https://github.com/openclaw/openclaw/issues/22258)

**Likelihood:** HIGH | **Fix:** Config available

When an agent runs multi-step tool calls, intermediate narration text between tool executions gets sent as separate Telegram messages. A single logical response fragments into multiple near-identical messages 0.3–1s apart.

- **Cause:** Reply pipeline splits streamed output into multiple `sendMessage` calls during tool execution gaps
- **Fix:** Set `channels.telegram.streamMode: "off"` — disables intermediate streaming, only sends final response
- **Upstream:** PR #18956 partially merged; PR #16275 (comprehensive fix) exists in external fork only, NOT merged into main

#### 1.2 Draft Streaming + Final Message (Perceived Duplicate)

**Likelihood:** HIGH | **Fix:** Config available

Telegram shows a live-updating "draft bubble" while the model streams, then OpenClaw sends the final reply as a separate `sendMessage`. Users perceive this as the answer sent twice.

- **Cause:** By design — `sendMessageDraft` for streaming preview + `sendMessage` for final delivery
- **Fix:** Same as 1.1 — `channels.telegram.streamMode: "off"` eliminates the preview bubble
- **Note:** This is UX confusion, not a true duplicate. But from the user's perspective it is identical

#### 1.3 Followup Queue Multi-Delivery — Issue [#30604](https://github.com/openclaw/openclaw/issues/30604)

**Likelihood:** MEDIUM-HIGH | **Fix:** None available

When a user sends messages while the agent is busy (mid-tool-call), the followup queue delivers the same inbound message multiple times across successive drain cycles.

- **Cause:** Inbound dedupe uses a TTL cache, but the followup queue only checks `queue.items` — it does not track already-drained items
- **Fix:** No config-level mitigation. Monitor upstream issue
- **Upstream:** Open, no fix merged as of March 2026

#### 1.4 Cron Announce-Mode Injection — Issue [#16139](https://github.com/openclaw/openclaw/issues/16139)

**Likelihood:** ~~MEDIUM~~ LOW (v2026.3.12+) | **Fix:** ~~Partial config available~~ **FIXED in v2026.3.8, further hardened in v2026.3.12**

Isolated cron jobs with `delivery.mode: "announce"` deliver their message correctly, but the main session also receives an injected "Summarize naturally..." prompt, generating a second response.

- **Cause:** Cron completion event injects a summary prompt into the main session
- **Fix:** ~~Set `delivery.relay: false` on announce-mode crons~~
- **Upstream:** **Fixed in v2026.3.8** — text-only jobs now routed through real outbound adapters. Cron no longer reports `delivered: true` when message never reached Telegram. The silent failure path is eliminated.
- **v2026.3.12 hardening:** Isolated cron sends are now excluded from the resend queue entirely. Previously, completed cron deliveries could re-enter the retry queue and produce duplicates even after the v2026.3.8 fix. This closes the remaining edge case.
- **Note:** This fix addresses the cron announce delivery path specifically. Non-cron duplicate causes (1.1-1.3, 1.5-1.7) are unaffected — keep `streamMode: "off"` workarounds.

#### 1.5 Polling Offset Loss on Restart — Issue [#739](https://github.com/openclaw/openclaw/issues/739)

**Likelihood:** LOW on v2026.1.13+ | **Fix:** Upstream fix merged

After gateway restart, grammY runner initialized with `offset = 0`. Telegram returned all unconfirmed updates (up to 24h backlog), causing reprocessing. In production, this caused ~60 duplicate status messages in a loop.

- **Cause:** Offset stored only in memory, cleared on restart. In-memory dedupe map also cleared
- **Fix:** Fixed Jan 2026 — offset now persists to `~/.openclaw/telegram/update-offset-default.json`
- **Residual risk:** A hard kill (OOM, SIGABRT from watchdog) could lose an unflushed write

#### 1.6 Session State Corruption Loop — Issue [#5806](https://github.com/openclaw/openclaw/issues/5806)

**Likelihood:** LOW (catastrophic when triggered) | **Fix:** Manual recovery

When an agent task fails (tool execution error, script crash), the session enters a retry loop. Session file grows to 200KB+ and reloads on restart, perpetuating the loop indefinitely.

- **Cause:** Corrupted session state persists across restarts; orphaned-user-message deletion logic re-triggers the same response
- **Fix:** Manual deletion of BOTH the offset file AND the stuck session file:
  ```bash
  sudo systemctl stop openclaw
  rm -f ~/.openclaw/telegram/update-offset-default.json
  rm -f ~/.openclaw/agents/<agent>/sessions/<stuck-session-id>.jsonl
  sudo systemctl start openclaw
  ```
- **Upstream:** PR #17743 partially addressed orphan deletion; core issue remains open

#### 1.7 No Outbound Idempotency — Issue [#32063](https://github.com/openclaw/openclaw/issues/32063)

**Likelihood:** MEDIUM | **Fix:** None available (architectural)

The `idempotency_key` column exists in the outbox schema but is **not populated**. OpenClaw provides at-least-once delivery only, not exactly-once. If a send times out but actually succeeds, the retry also succeeds — producing a duplicate.

- **Cause:** Delivery recovery retries on timeout without checking if the first attempt succeeded
- **Fix:** None — requires the durable SQLite outbox pattern (#32063) currently being designed
- **Related:** Issue [#30246](https://github.com/openclaw/openclaw/issues/30246) — cron announcements delivered twice via this path

### Additional Duplicate Sources

| Issue | Description | Status |
|-------|-------------|--------|
| [#10377](https://github.com/openclaw/openclaw/issues/10377) | Every inbound message appears 2x in session context (duplicate event handler registration) | Closed (Not Planned) |
| [#25606](https://github.com/openclaw/openclaw/issues/25606) | Heartbeat runs enqueued as followups create duplicate response branches | Fixed v2026.2.24+ |
| [#30316](https://github.com/openclaw/openclaw/issues/30316) | Text + audio both sent twice during multi-tool responses | Open — PRs #30478, #33455 pending |
| [#31710](https://github.com/openclaw/openclaw/issues/31710) | Discord health-monitor restart loop registers duplicate event listeners | Open |
| [#9167](https://github.com/openclaw/openclaw/issues/9167) | `boot-md` hook fires multiple times during startup | Open |
| [#5964](https://github.com/openclaw/openclaw/issues/5964) | Control UI webchat: every assistant reply appears twice | Open |

### Real-World Cost Impact (Observed 2026-03-06)

Session `5146418f` — a 9-hour Supercolony session — consumed **$31.77 / 28.8M tokens**. Analysis of the session file revealed:

- **115 user messages** in the session, but only **~48 unique `message_id` values**
- **~67 duplicate deliveries** (58% of all inbound messages were re-deliveries)
- After a 4-hour gap (user aborted, resumed), **every message was delivered 4x** — the followup queue re-drained the same messages on each cycle
- Each duplicate re-triggers the full agent pipeline (context load + LLM inference + tool execution), multiplying token spend

This is Root Cause 1.3 (followup queue multi-delivery, #30604) in action. Unlike 1.1/1.2, `streamMode: "off"` does **not** fix this — there is no config-level mitigation. The cost inflation from duplicates on long, tool-heavy sessions is substantial.

### Why It's Intermittent

The intermittent nature exists because none of the triggering conditions are deterministic:

- **LLM latency** — same prompt can take 4s or 14s depending on provider queue depth and context size
- **Tool execution time** — varies with external API response times
- **User behavior** — rapid-fire messages during agent processing trigger followup queue issues; slow conversation does not
- **Network conditions** — TCP ACK packet loss causes edge-node re-delivery (~0.02% rate across 50M updates)
- **Restart timing** — watchdog kills vs. graceful restarts differ in offset persistence behavior

### Recommended Mitigation

The single highest-impact config change:

```json
{
  "channels": {
    "telegram": {
      "streamMode": "off"
    }
  }
}
```

This eliminates root causes 1.1 and 1.2 (tool execution fragmentation and draft streaming perception). Trade-off: users lose the "typing preview" UX.

Additional mitigations:
- ~~Audit cron jobs: add `delivery.relay: false` to announce-mode crons (fixes 1.4)~~ — **No longer needed** (fixed in v2026.3.8, hardened in v2026.3.12)
- Ensure v2026.2.24+ for heartbeat followup fix (#25606)
- Monitor PRs #30478 and #33455 for multi-layer outbound dedup
- Monitor Issue #32063 for the durable SQLite outbox (architectural fix)

### Upstream Tracking

| PR/Issue | Description | Status |
|----------|-------------|--------|
| PR #18956 | Avoid duplicate preview bubbles in partial stream mode | Merged |
| PR #16275 | Comprehensive tool-execution dedup | External fork only |
| PR #30478 | Per-turn Telegram dedup | Open |
| PR #33455 | Multi-layer outbound dedup (3 layers) | Open |
| Issue #32063 | Durable SQLite outbox (architectural fix) | Open, designing |

### References

- [OpenClaw Telegram Channel Docs](https://docs.openclaw.ai/channels/telegram)
- [grammY: Long Polling vs. Webhooks](https://grammy.dev/guide/deployment-types)
- [grammY: Reliability (at-least-once guarantees)](https://grammy.dev/advanced/reliability)
- [Telegram Bot API](https://core.telegram.org/bots/api) — webhook retry behavior
- [DeepWiki: OpenClaw Telegram Integration](https://deepwiki.com/openclaw/openclaw/8.3-telegram-integration)

---

## 2. Silent Polling Death — Issue [#7526](https://github.com/openclaw/openclaw/issues/7526)

**Severity:** Medium | **Status:** Open | **Affected:** Telegram (long-polling mode)

Long-polling connection dies silently after ~8 minutes without auto-reconnect. The bot stops receiving messages with no error in logs. The built-in health monitor (5-min interval) does not check recency of inbound activity ([#28622](https://github.com/openclaw/openclaw/issues/28622)).

### Symptoms

- Bot stops responding to all messages
- No errors in `journalctl -u openclaw`
- Gateway appears healthy (`systemctl status openclaw` shows active)
- Restarting the gateway restores functionality

### Workaround

- Monitor inbound message timestamps in logs
- Consider a canary cron that verifies the bot can process messages
- Gateway restart resolves the issue until the next silent death

### References

- [Issue #7526](https://github.com/openclaw/openclaw/issues/7526) — Long-polling connection dies without reconnect
- [Issue #28622](https://github.com/openclaw/openclaw/issues/28622) — Health monitor does not check message recency

---

## 3. Typing Indicator Leak — Issues [#26586](https://github.com/openclaw/openclaw/issues/26586), [#27493](https://github.com/openclaw/openclaw/issues/27493)

**Severity:** Low | **Status:** Open | **Affected:** Telegram

The typing indicator (`sendChatAction: "typing"`) keepalive loop continues after the reply completes. Users see "typing..." indefinitely until the next message exchange or gateway restart.

### Workaround

- Cosmetic issue only — does not affect message delivery
- Sending a new message resets the typing state

---

## 4. Config Key Rejection — Undocumented Behavior

**Severity:** Medium | **Status:** By design | **Affected:** All

OpenClaw rejects unrecognized root keys in `openclaw.json`. Adding an invalid key breaks the entire config validation, potentially preventing gateway startup.

### Example

```json
{
  "context": { ... }   // WRONG — not a valid root key
}
```

The correct key path is `agents.defaults.contextPruning`, not top-level `context`.

### Mitigation

- Always run `openclaw config validate` before restarting (available since v2026.3.2)
- Back up `openclaw.json` before manual edits
- Never use `openclaw config set` for complex keys — it can introduce malformed JSON

---

## 5. 402 Billing Error Misreported as "Context Overflow"

**Severity:** Low | **Status:** By design | **Affected:** OpenRouter provider

When OpenRouter returns HTTP 402 (payment required / insufficient credits), OpenClaw misreports it as a "context overflow" error in logs and to the user.

### Diagnosis

- Check OpenRouter dashboard balance
- Look for `402` in raw gateway logs: `journalctl -u openclaw | grep 402`
- The bot will resume working immediately after topping up credits

---

## 6. Compaction Auth Failure — `compaction.provider` + Slash-Prefixed Model Misconfiguration

**Severity:** High (silent) | **Status:** Configuration trap | **Affected:** All versions | **Authoritative:** [docs.openclaw.ai/concepts/compaction](https://docs.openclaw.ai/concepts/compaction)

Compaction silently fails on every overflow when `compaction.provider` is paired with a slash-prefixed `compaction.model` string. The bot still chats normally until context fills, then auto-compaction throws and the user sees no clear signal.

### Symptom

```
[context-overflow-diag] sessionKey=... messages=1375
context overflow detected (attempt 1/3); attempting auto-compaction
[compaction-diag] end ... outcome=failed reason=unknown
auto-compaction failed for <chat-model>: No API key found for provider "<X>".
```

User-visible: bot may reply but session keeps growing; eventually hits hard provider overflow. Marius noticed by needing to manually `/compact` repeatedly.

### Root Cause

Per official docs: `compaction.provider` is for **custom compaction-provider plugin IDs** (a pluggable custom implementation registered via plugin), NOT for selecting an LLM-routing provider. Setting it forces `mode: "safeguard"` automatically and routes to a plugin lookup that fails.

When `model` is a slash-prefixed string (`anthropic/claude-haiku-4-5`), OpenClaw resolves the provider from the model string's first segment and **ignores** any explicit `provider` key. So the auth lookup goes to `anthropic` (direct API) rather than the intended OpenRouter routing.

### The Misconfig

```jsonc
// ❌ BROKEN
"compaction": {
  "provider": "openrouter",
  "model": "anthropic/claude-haiku-4-5"   // missing openrouter/ prefix
}
```

### The Fix

```jsonc
// ✅ CANONICAL
"compaction": {
  "model": "openrouter/openai/gpt-4.1-mini"
  // OR: "openrouter/anthropic/claude-haiku-4-5"
  // OR: "ollama/llama3.1:8b" (local, free)
}
```

### Auth Constraint (related)

OAuth providers (`openai-codex/...`) **cannot** be used for compaction reliably — OpenAI's own Codex CLI docs state OAuth tokens "aren't reliably maintainable across separate process invocations." Compaction must use API-key-based auth. OpenRouter is the path of least resistance.

### Diagnosis

```bash
# Look for the smoking-gun line
sudo journalctl -u openclaw --since "7 days ago" | grep -E 'auto-compaction failed|compaction-diag.*outcome'

# Healthy looks like:
#   [compaction-diag] end ... outcome=success
#   [agent/embedded] [compaction] skipping — no real conversation messages
```

### References

- [docs.openclaw.ai/concepts/compaction](https://docs.openclaw.ai/concepts/compaction)
- [GUIDE.md §9.6 Compaction Model Selection](../GUIDE.md)
- [Reference/CONTEXT-ENGINEERING.md Recommendation 4](CONTEXT-ENGINEERING.md)

---

## 7. Workspace Path Drift — Identity Loss on Restart

**Severity:** High | **Status:** Configuration trap | **Affected:** Any deployment using toolkits that scaffold under /tmp

`agents.defaults.workspace` is a writable config key. If it points at `/tmp/...` (especially a path scaffolded by a toolkit/test runner like `omniweb-toolkit`), the bot will lose identity on every gateway restart.

### Symptom

After a gateway restart, the bot sends the bootstrap dialogue to the user:

> "Hey. I just came online. Who am I, and who are you?"

…even though the bot was fully bootstrapped weeks ago. Memory files appear intact but identity files (`IDENTITY.md`, `USER.md`, `SOUL.md`, `BOOTSTRAP.md`) load from a path containing FRESH default templates.

### Root Cause

1. /tmp is wiped on reboot — workspace state doesn't persist
2. Toolkit test harnesses (omniweb-toolkit observed) scaffold ephemeral workspaces under `/tmp/<toolkit>-test/...` with default `BOOTSTRAP.md` + bare `IDENTITY.md` template files on each setup/test run
3. Memory writes silently fall back to a default location, so memory still works — only identity is lost

### Smoking-Gun Diagnostic

```bash
openclaw memory status | grep -E "^Workspace:|^Issues:"
# Healthy:   Workspace: ~/.openclaw/workspace
# Broken:    Issues: memory directory missing (/tmp/...)
```

The `Issues: memory directory missing` line is reported but not fatal — it's the canary, treat it as RED.

### Fix

```jsonc
// ✅ Stable, persistent path under bot user's home
"agents": {
  "defaults": {
    "workspace": "/home/<user>/.openclaw/workspace"
  }
}
```

### References

- [GUIDE.md §8.0 Workspace Path Discipline](../GUIDE.md)

---

## 8. Strict-Schema Auto-Restore Silently Reverts Config Edits

**Severity:** High | **Status:** Configuration trap | **Affected:** Any config edit to `~/.openclaw/openclaw.json` since v2026.4.x (strict schema rollout)

OpenClaw's config schema declares `additionalProperties: false` at every nested object. A single misnamed key — even a typo like `timeoutMs` instead of `timeoutSec` — invalidates the entire config block. On the next gateway restart the runtime triggers `reload-invalid-config`, which **silently restores the last-known-good snapshot** from a backup. *All* edits in that session are reverted, not just the bad key. The service starts cleanly, model registration succeeds, and `openclaw capability model run --model X` works (because the model is in `agents.defaults.models`) — but your fallback chain, exec tuning, or whatever else you changed is gone, and there is no error in the user-facing logs.

This is how the bot regressed silently on 2026-04-27: a fallback-chain edit was paired with `tools.exec.timeoutMs: 90000` (correct key is `timeoutSec`). The schema rejected the whole config; auto-restore reverted to the prior fallback chain. Pong via direct `--model` override worked, masking the regression for ~90 minutes.

### Symptom

- You edit `~/.openclaw/openclaw.json` (e.g., add a fallback chain, tune `tools.exec.timeoutSec`, add a subagent)
- `sudo systemctl restart openclaw` succeeds
- Service status: `active (running)` — no error
- `openclaw capability model run --model <provider>/<name>` returns a healthy pong
- Behavior in production does NOT match what you configured

### Root Cause

1. Schema is strict: every nested object has `additionalProperties: false` (verified at `tools.exec`, `agents.defaults`, and many sibling nodes)
2. ONE wrong key — anywhere in the file — fails whole-document validation
3. Validation failure on startup triggers `reload-invalid-config` which restores from the last-known-good backup
4. Restoration is silent in the user-facing journal; the only signal is that your edit isn't there anymore
5. `--model X` invocation tests model **registration** (allowlist in `agents.defaults.models`), not the **fallback chain** (`agents.defaults.model.fallbacks`) — so a successful pong proves nothing about the chain

### Smoking-Gun Diagnostic

```bash
# Always run BEFORE restart:
openclaw config validate
# Validates against the live schema. Cleaner than `config dump`.
# If you see "additionalProperties" or "must NOT have additional properties" — STOP, fix, revalidate.

# After restart, READ BACK the live JSON to confirm persistence:
sudo -u openclaw cat ~/.openclaw/openclaw.json | jq '.agents.defaults.model.fallbacks'
sudo -u openclaw cat ~/.openclaw/openclaw.json | jq '.tools.exec'
# These MUST match what you edited. If they revert to a prior shape, auto-restore fired.
```

The pong-only test is **insufficient**. The runtime allowlist may permit a model via direct `--model` override even when the fallback chain config got auto-restored.

### Fix / Discipline

1. **Always run `openclaw config validate` BEFORE every restart.** Treat its output as a gate.
2. **READ BACK from `~/.openclaw/openclaw.json` POST-RESTART.** Compare the actual live JSON to your intended edits. Only this proves persistence.
3. **Discover correct keys via the schema, not memory:** `openclaw config schema | jq '.properties.tools.properties.exec'` (or wherever you're editing) shows the legal sibling keys.
4. **Sibling correct keys for `tools.exec`:** `timeoutSec` (NOT `timeoutMs`), `security`, `allowlist`, `denylist`. (As of v2026.4.22.)
5. **Don't trust pong as fallback-chain proof.** A `--model X` test confirms model registration only. To test failover, force the primary unavailable (e.g., revoke its API key briefly, or change the chain head to a deliberately-broken model name) and confirm the next chain entry fires.
6. **Keep `~/.openclaw/openclaw.json.bak` aware.** If auto-restore fires, the prior good config is in the backup; check timestamps to detect silent reversion (`stat ~/.openclaw/openclaw.json*`).

### References

- bd memory `openclaw-config-edit-discipline-always-run-openclaw-config` (this session's lesson)
- bd memory `gregor-regression-learnings-2026-04-27-my-verified` (pong false-positive)
- Affected beads on 2026-04-27: `tm0`, `zhm`, `kou` (re-opened 15:50 after silent regression detected, fixed and re-closed with read-back evidence)

---

## 9. ACP `sessions_spawn` Ignores `agents.list[]` — `agentId` Must Be a Harness ID

**Status:** Confirmed v2026.4.22 (2026-05-02). Source-verified.

**Symptom:** Calling `sessions_spawn(runtime:"acp", agentId:"codex-eng", mode:"session", thread:true)` after declaring a custom ACP agent in `agents.list[]` fails with:

```
spawn_failed
Failed to spawn agent command: codex-eng
```

If you instead pass the harness id `agentId:"codex"` while `acp.allowedAgents` only contains `["codex-eng","codex-research"]`, you get:

```
agent_forbidden
ACP agent "codex" is not allowed by policy.
```

**Root cause:** The ACP spawn handler does **not** consult `agents.list[]`. The `agentId` argument is passed straight through:

- `dist/acp-spawn-sxPJHfFf.js:428` — `resolveTargetAcpAgentId(params.agentId)` returns `params.agentId` unchanged (or `acp.defaultAgent` when absent). No `agents.list[]` lookup.
- `dist/acp-spawn-sxPJHfFf.js:846` — `resolveAcpAgentPolicyError(cfg, targetAgentId)` checks `acp.allowedAgents` (so "codex-eng" passes user policy).
- `dist/extensions/acpx/node_modules/acpx/dist/runtime.js:384` — `agentRegistry.resolve(targetAgentId)` calls
- `dist/extensions/acpx/node_modules/acpx/dist/prompt-turn-CXMtXBl-.js:71` — `resolveAgentCommand("codex-eng", overrides)` → `registry["codex-eng"]` undefined → `AGENT_ALIASES["codex-eng"]` undefined → returns `"codex-eng"` literally
- `dist/extensions/acpx/node_modules/acpx/dist/prompt-turn-CXMtXBl-.js:1356` — `spawn("codex-eng", …)` → ENOENT → `AgentSpawnError`

The acpx hardcoded `AGENT_REGISTRY` (prompt-turn-CXMtXBl-.js:19) is the only valid namespace for `agentId`:

```
pi, openclaw, codex, claude, gemini, cursor, copilot, droid,
iflow, kilocode, kimi, kiro, opencode, qoder, qwen, trae
```

**What `agents.list[].runtime.type:"acp"` actually does:** Per schema description ("ACP runtime defaults for this agent when runtime.type=acp. Binding-level ACP overrides still take precedence per conversation"), it provides per-OpenClaw-agent defaults (cwd, mode, harness id pointer) used when **incoming traffic** is routed through `bindings[]` of `type:"acp"`. It is **not** a registration of a programmatically-spawnable ACP agent. The runtime never reaches it during `sessions_spawn`.

**Workaround for v2026.4.22:**

For programmatic dispatch (the `sessions_spawn` path), pass a real harness id:

```
sessions_spawn(runtime:"acp", agentId:"codex", mode:"session", thread:true,
               cwd:"/home/openclaw/workspaces/eng",
               resumeSessionId: <persisted-id-from-prior-spawn>)
```

For two persistent peers, differentiate by **stable thread + cwd** (the ACP session is bound to the thread when `thread:true`+`mode:"session"`). The "named co-worker" identity is per-thread-per-cwd, not per-`agentId`.

For channel-routed persistence, use `bindings[]` of `type:"acp"` to pin a specific Telegram thread/peer to an `agents.list[]` entry whose `runtime.acp.agent: "codex"` (the harness pointer) and `runtime.acp.cwd` is the working directory. The label is for diagnostics; the harness is still resolved through the hardcoded registry.

**Bug or design?** Documented behavior says `agents.list[].runtime.type:"acp"` declares ACP runtime defaults; however the mental model of "address custom ACP agents by id from `sessions_spawn`" (which the docs and examples imply) is **not implemented** in v2026.4.22. Either:

- runtime gap: `resolveTargetAcpAgentId` should detect `agents.list[].id` matches and resolve harness via `runtime.acp.agent`, OR
- doc gap: docs.openclaw.ai/tools/acp-agents should clarify that `sessions_spawn(agentId)` is a harness id, not an agent.list id, and that custom ACP identities are channel-side via `bindings[]`.

**Discipline:** when wiring ACP for the first time, validate end-to-end with the simplest call:

```bash
# 1. set acp.allowedAgents to the harness id, not custom names
openclaw config set acp.allowedAgents '["codex"]'
openclaw config set acp.defaultAgent codex

# 2. probe via /acp doctor and openclaw acp status
openclaw acp doctor

# 3. only after the harness path works, layer on agents.list[] + bindings[] for identity
```

**See also:**
- bd memory `acpx-agentid-is-harness-not-agentlist-2026-05-02`
- Source: `~/.npm-global/lib/node_modules/openclaw/dist/{acp-spawn-sxPJHfFf.js, extensions/acpx/node_modules/acpx/dist/{runtime.js, prompt-turn-CXMtXBl-.js, perf-metrics-D0um6IR6.js}}`

---

## 10. acpx Skips `authenticate` for ChatGPT OAuth Without Env Marker — `Token data is not available`

**Status:** Confirmed v2026.4.22 (2026-05-02). Source-verified, fix-verified end-to-end.

**Symptom:** A `/acp spawn codex` (or any acpx-mediated codex peer launch) reports:

```
Falling back from WebSockets to HTTPS transport.
Token data is not available.
ACP error (ACP_TURN_FAILED): Internal error
```

…even when `~/.codex/auth.json` is healthy and contains valid `tokens.refresh_token`/`id_token`/`account_id` (verified by direct JSON-RPC handshake — see Repro below).

**Root cause:** `acpx.AcpClient.selectAuthMethod` (`extensions/acpx/node_modules/acpx/dist/prompt-turn-CXMtXBl-.js:2405-2419`) iterates the `authMethods` array returned by codex-acp's `initialize` response and **requires a non-empty environment credential matching each method's id** before it will mark the method as selected:

```js
selectAuthMethod(methods) {
    for (const method of methods) {
        const envCredential = readEnvCredential(method.id);
        if (envCredential) return { methodId: method.id, credential: envCredential, source: "env" };
        const configCredential = resolveConfiguredAuthCredential(method.id, this.options.authCredentials);
        if (typeof configCredential === "string" && configCredential.trim().length > 0) return { ... };
    }
}
```

`readEnvCredential("chatgpt")` checks env keys `chatgpt`, `CHATGPT`, `ACPX_AUTH_CHATGPT` (via `toEnvToken` at line 1433). With none of those set, the function returns `undefined` and `authenticateIfRequired` (line 2421) **silently skips the authenticate call** with the log message:

```
agent advertised auth methods [chatgpt, codex-api-key, openai-api-key] but no matching
credentials found — skipping (agent may handle auth internally)
```

codex-acp then has no auth state loaded, falls back to OAuth refresh from a cold state, fails with the cascading errors above. The `~/.codex/auth.json` is never read because `authenticate({methodId:"chatgpt"})` was never sent.

**Why this is a bug:** The `chatgpt` OAuth method does not need a string credential — codex-acp handles all auth internally from `$CODEX_HOME/auth.json` once it receives `authenticate(methodId:"chatgpt")`. acpx's check is overly defensive: it conflates env-var-based methods (`codex-api-key`, `openai-api-key` — which legitimately need a string credential) with OAuth methods that don't.

**Workaround (verified):** Set `CHATGPT=1` (or any non-empty marker) in the gateway's systemd environment so `selectAuthMethod` finds the env match and triggers `authenticate(methodId:"chatgpt")`:

```bash
sudo tee /etc/systemd/system/openclaw.service.d/codex-acp-auth-chatgpt.conf <<'EOF'
[Service]
Environment=CHATGPT=1
EOF
sudo systemctl daemon-reload
sudo openclaw-gateway-stop && sleep 4 && sudo openclaw-gateway-start
```

The credential value is unused — only its presence matters. `selectAuthMethod` returns `{methodId:"chatgpt", credential:"1", source:"env"}`, `authenticateIfRequired` calls `connection.authenticate({methodId:"chatgpt"})`, codex-acp loads `auth.json` tokens, session creation succeeds.

**Repro / direct evidence the auth surface itself works:**

```bash
ssh vps 'sudo -u openclaw bash -lc "cd /tmp && \
  CODEX_HOME=/home/openclaw/.openclaw/agents/main/agent/acp-auth/codex-source \
  timeout 15 /home/openclaw/.npm/_npx/<hash>/node_modules/@zed-industries/codex-acp-linux-x64/bin/codex-acp" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}
{"jsonrpc":"2.0","id":2,"method":"authenticate","params":{"methodId":"chatgpt"}}
{"jsonrpc":"2.0","id":3,"method":"session/new","params":{"cwd":"/home/openclaw/workspaces/eng","mcpServers":[]}}
EOF
```

When `auth.json` is valid: id=2 returns `{}` (success), id=3 returns a `sessionId` + model list. When acpx skips id=2: id=3 fails with the cascading transport errors.

**End-to-end verification (2026-05-02 19:07 post-workaround):** `/acp spawn codex --mode persistent --thread auto --cwd /home/openclaw/workspaces/eng --label codex-eng` → sessionKey `agent:codex:acp:76d959af-...`, persistent, peer responded with model `Codex/GPT-5`, cwd `/home/openclaw/workspaces/eng`, acpx session id `019de9a8-...`. No fallback errors.

**Hidden prerequisite — the auth.json itself must be valid Codex CLI shape.** Required keys: `tokens.{refresh_token, id_token, account_id}` (and optionally `OPENAI_API_KEY`). A 2337-byte malformed file with no `tokens` block will fail even with `CHATGPT=1` set. Procedure: `codex login` on a workstation with a browser, scp `~/.codex/auth.json` to both VPS locations:
- `/home/openclaw/.codex/auth.json` (mode 0600 owner openclaw)
- `/home/openclaw/.openclaw/agents/main/agent/acp-auth/codex-source/auth.json` (same)

Also copy `~/.codex/installation_id` to the acp-auth path so the harness identity is consistent.

**Upstream fix would look like:** in `selectAuthMethod`, treat OAuth methods (those without a `type: "env_var"` property) as auto-eligible without requiring an env credential. The `authMethods` response distinguishes them — `chatgpt` has no `type` field, `codex-api-key`/`openai-api-key` have `type: "env_var"`.

**See also:**
- bd memory `acpx-chatgpt-env-required-workaround-2026-05-02`
- bd memory `acpx-agentid-is-harness-not-agentlist-2026-05-02`
- KNOWN-BUGS §9 (the agentId namespace gotcha — different bug, same plugin)

---

## 11. Compaction Config Edits Need a Real Restart — Live Reload Logged But Not Applied

**Status:** Confirmed v2026.4.22 (2026-05-05). Field-observed during Gregor's gpt-4.1-mini → Haiku 4.5 + 120s migration.

**Symptom:** After editing `agents.defaults.compaction.{model,timeoutSeconds}` in `~/.openclaw/openclaw.json`, the gateway logs:

```
config change detected; evaluating reload (agents.defaults.compaction.timeoutSeconds)
config change detected; evaluating reload (agents.defaults.compaction.model)
```

…but **no successful `applied reload` follow-up.** The next compaction attempt still uses the OLD provider/timeout, and any timeout cascade that motivated the edit continues firing. Editing the file changes disk state; live runtime continues with cached settings.

**Root cause:** these specific compaction keys are not on the gateway's hot-reload allowlist. The "evaluating reload" log line is recorded but the evaluator chooses NOT to apply — and silently. Compaction keys are evaluated lazily at process boot, not at file-change time. Workspace files, channel definitions, and some agent metadata DO hot-reload; compaction config doesn't.

**Why "restart and pong" is insufficient evidence the change took effect:** the gateway accepts new chat messages, runs them through the unmodified-cached compaction path, and returns successful responses for short conversations that don't trigger compaction. The only place the change manifests is the next compaction event — which may not fire for hours.

**Fix:** apply with a real gateway restart, then read back from live JSON, then watch the next compaction event in the journal.

```bash
# 1. Edit (e.g., switch compaction.model + bump timeoutSeconds)
jq '.agents.defaults.compaction = {
  "mode": "safeguard",
  "model": "openrouter/anthropic/claude-haiku-4-5",
  "timeoutSeconds": 120,
  "keepRecentTokens": 20000,
  "reserveTokens": 8000,
  "memoryFlush": { "enabled": true, "softThresholdTokens": 40000 },
  "qualityGuard": { "enabled": true }
}' ~/.openclaw/openclaw.json > /tmp/oc.new && mv /tmp/oc.new ~/.openclaw/openclaw.json

# 2. Validate (KNOWN-BUGS #8 discipline — strict schema)
openclaw config validate

# 3. Restart (with KNOWN-BUGS #11 in mind — compaction needs this)
systemctl restart openclaw    # NO sudo, via Polkit rule from GUIDE.md § 6.2

# 4. READ BACK from live JSON post-restart (KNOWN-BUGS #8 again)
jq '.agents.defaults.compaction' ~/.openclaw/openclaw.json

# 5. PROVE the new compaction is live by watching the next compaction event
sudo journalctl -u openclaw -f | grep -iE 'compaction|compaction-diag'
# Expected: provider matches the new model, timeout matches new value
```

**Detection signal in the live log post-edit (before restart):** repeated `config change detected; evaluating reload (...)` lines for compaction keys, never followed by `applied`. If you see those, restart is required.

**See also:**
- KNOWN-BUGS #6 (compaction auth failure — different compaction issue, same area)
- KNOWN-BUGS #8 (strict-schema auto-restore — independent discipline that bites the same workflow)
- GUIDE.md § 9.6 (canonical compaction config)
- GUIDE.md § 6.2 (Polkit self-restart pattern — what makes step 3 above work without external ssh)

---

## 12. v2026.4.x → v2026.5.x Migration: `embeddedHarness.fallback` Restart Loop

**Severity:** High | **Status:** Confirmed on Gregor 2026-05-06/07 | **Affected:** Any host upgraded from a v2026.4.x baseline that had `embeddedHarness.{runtime,fallback}` blocks

### Symptom

After `npm install -g openclaw@2026.5.x` and a gateway restart, the gateway enters a permanent systemd restart loop. Every attempt logs:

```
Gateway failed to start: Error: Invalid config at ~/.openclaw/openclaw.json.
agents.defaults.embeddedHarness: Unrecognized key: "fallback"
agents.list.<id>.embeddedHarness: Unrecognized key: "fallback"
Run "openclaw doctor --fix" to repair, then retry.
```

On Gregor the loop hit ~2000 restart attempts between 2026-05-06 21:56 and 2026-05-07 07:00 before manual intervention.

### Root Cause

In v2026.5.x the `embeddedHarness` schema was narrowed to `{runtime: string}` only — the old `fallback` field was deleted. New canonical home is `agents.defaults.agentRuntime.id` and `agents.list[].agentRuntime.id`. The schema is `additionalProperties: false`, so any `fallback` survivor invalidates the whole config and the gateway refuses to boot.

`openclaw doctor --fix` is supposed to migrate this automatically but **does not reliably remove the `fallback` keys** in our reproduction. Doctor's auto-fix is partial / contradictory in this version. Manual removal is required.

### Manual Fix (verified on Gregor)

```bash
# 1. Backup
cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.pre-fix-$(date +%Y-%m-%d)

# 2. Strip the legacy embeddedHarness blocks and migrate to agentRuntime
jq '
  del(.agents.defaults.embeddedHarness)
  | del(.agents.list[] | select(.id=="codex") | .embeddedHarness)
  | .agents.defaults.agentRuntime = {id: "auto"}
  | (.agents.list[] | select(.id=="codex") | .agentRuntime) = {id: "codex"}
  | (.agents.list[] | select(.id=="codex") | .model) = "openai-codex/gpt-5.4"
' ~/.openclaw/openclaw.json > /tmp/oc.json
cat /tmp/oc.json > ~/.openclaw/openclaw.json && rm /tmp/oc.json

# 3. Validate and restart
openclaw config validate         # must say "Config valid"
systemctl restart openclaw       # via Polkit rule, no sudo
ss -tlnp | grep :18789           # must show LISTEN

# 4. Confirm the four load-bearing invariants
src/scripts/config-invariants.sh
```

The full target shape (for reference and for fresh installs) lives in [GUIDE.md Appendix E.2](../GUIDE.md#appendix-e--configuration-reference-canonical). Treat `openclaw doctor --fix` as advisory in major-version upgrades; always read-back the JSON after running it.

**See also:**
- KNOWN-BUGS #8 (strict-schema auto-restore — same discipline)
- KNOWN-BUGS #13 (subagent routing fail-closed invariant — load-bearing config)
- UPGRADE-NOTES.md v2026.5.6 entry
- `src/scripts/config-invariants.sh`

---

## 13. Subagent Routing Silently Pinned to Key-Based Model via `agents.defaults.subagents.model`

**Severity:** Critical | **Status:** Confirmed and fixed on Gregor 2026-05-07 | **Affected:** Any deployment that ever set `agents.defaults.subagents.model` as a string

### Symptom

Main agent runs on Codex OAuth as configured. Subagents spawned via `sessions_spawn` (mode=run or mode=session) route through OpenRouter Haiku or `openrouter/free` regardless of main's model and regardless of `agents.defaults.model.fallbacks`. Visible in `~/.openclaw/agents/<id>/sessions/<uuid>.jsonl` as `"provider":"openrouter","model":"anthropic/claude-haiku-4-5"` etc.

When the OpenRouter monthly key limit is hit, subagents return 403s on the child task while the parent subagent task often shows `succeeded` (see KNOWN-BUGS #14 on the parent/child reporting bug).

### Root Cause

`agents.defaults.subagents.model` accepts either a string (single model pin) or an object `{primary, fallbacks, timeoutMs}`. When set to a string like `"openrouter/anthropic/claude-haiku-4-5"`, ALL subagents are forced onto that exact model — **the main agent's model and fallback chain are not inherited**. This is independent from `agents.defaults.model` which only governs the main agent. The two configs do not cross-reference.

This bites any installer or hand-edit that left `subagents.model` as a string, or any v2026.4.x baseline where the default was a string.

### The Invariant (operator-required, fail-closed)

Subagents must NEVER use a key-based model. The canonical shape lives in [GUIDE.md Appendix E.2](../GUIDE.md#appendix-e--configuration-reference-canonical) under `agents.defaults.subagents.model` (object form with empty `fallbacks: []`). Empty fallbacks means: if Codex OAuth is unavailable for the subagent run, **fail the run** rather than silently degrade to OpenRouter.

### Verification (verified on Gregor 2026-05-07)

End-to-end probe via `openclaw agent --agent main` asking main to spawn a subagent. Inspect the subagent session jsonl:

```bash
ls -lt ~/.openclaw/agents/worker/sessions/*.jsonl | head -1
# Then read the model_change and final assistant message — must show:
#   "provider":"openai-codex","modelId":"gpt-5.4"
# If you see "openrouter" or "anthropic" or "free" in there, the invariant is broken.
```

### Prevention

- `src/scripts/config-invariants.sh` enforces this as Invariant #2.
- Treat `agents.defaults.subagents.model` as a load-bearing object (never string) in installers, GUIDE.md, and any future config-edit playbook.

**See also:**
- KNOWN-BUGS #12 (the v5.x migration that surfaced this)
- KNOWN-BUGS #14 (subagent parent/child task-state inconsistency — upstream)
- Bead `openclaw-bot-bvy`

---

## 14. Subagent Run: Child CLI Task `failed` AND Parent Subagent Task `succeeded` Simultaneously

**Severity:** Medium | **Status:** Reported upstream — bead `openclaw-bot-brj` | **Affected:** Subagent runs where the first model attempt fails and a recovery path produces a visible answer

### Symptom

In `~/.openclaw/tasks/runs.sqlite` for the same subagent run:

- Child CLI task: `status=failed`, `error="403 Key limit exceeded ..."` (or any provider error)
- Parent subagent task: `status=succeeded`, `delivery_status=delivered`, with the same error string still attached
- `sessions_list` shows a normal completed answer

The parent reports "succeeded/delivered" because a hidden retry produced a final visible answer, but the child task that recorded the original failure is never reconciled. Maintainer cost: must inspect 3 layers (child task, parent task, session transcript) to understand one run.

### Mitigation Status

Less critical now that subagents are pinned to Codex OAuth with empty fallbacks (KNOWN-BUGS #13) — fewer hidden recovery paths can fire silently. But the state model is still wrong and should be reported upstream.

**See also:**
- Bead `openclaw-bot-brj` (upstream filing tracker)
- Original Gregor inbox report 2026-05-06 21:55 at `/home/openclaw/.openclaw/workspace/inbox/2026-05-06-subagent-model-routing-bug.md`

---

*This document tracks bugs confirmed through deployment experience and upstream issue research. For security-specific patches and CVEs, see [SECURITY-PATCHES.md](SECURITY-PATCHES.md).*
