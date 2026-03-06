# Known Bugs & Workarounds

Documented bugs affecting OpenClaw deployments, with root cause analysis, upstream tracking, and available mitigations. Focus on issues that are systemic (not one-off configuration mistakes) and affect production stability.

> **Last updated:** 2026-03-06 | **OpenClaw version:** v2026.3.2

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

**Likelihood:** MEDIUM (if using cron) | **Fix:** Partial config available

Isolated cron jobs with `delivery.mode: "announce"` deliver their message correctly, but the main session also receives an injected "Summarize naturally..." prompt, generating a second response.

- **Cause:** Cron completion event injects a summary prompt into the main session
- **Fix:** Set `delivery.relay: false` on announce-mode crons
- **Upstream:** PRs #15737/#15739 partially fixed via `delivered` flag, but injection path not fully gated. Still reproducing on v2026.2.13+

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
- Audit cron jobs: add `delivery.relay: false` to announce-mode crons (fixes 1.4)
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

*This document tracks bugs confirmed through deployment experience and upstream issue research. For security-specific patches and CVEs, see [SECURITY-PATCHES.md](SECURITY-PATCHES.md).*
