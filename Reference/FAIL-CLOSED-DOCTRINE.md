# Fail-Closed Doctrine

Read when:

- proposing or removing a model fallback chain for Gregor or any pack bot;
- triaging "Gregor is behaving weirdly / forgetting tools / making up
  answers" — silent fallback degradation is a leading hypothesis;
- adding a new agent (Aldine, Vesalius, Hypatia, Dismas) and writing its
  initial `agents.defaults.model` config;
- writing a new bead about model failover, retry, or recovery.

---

## 1. Rule

**Both the main agent and the subagent fan-out fail closed.** No silent
fallback to lower-quality models. When the configured primary fails (auth,
rate limit, billing, timeout), Gregor surfaces the error to the operator
and waits for a decision — does not silently degrade.

```yaml
agents:
  defaults:
    model:                                 # MAIN agent
      primary: openai-codex/gpt-5.4
      fallbacks: []                        # ← empty, enforced by I6
    subagents:
      model:                               # SUBAGENT fan-out
        primary: openai-codex/gpt-5.4
        fallbacks: []                      # ← empty, enforced by I2
```

Enforced by `src/scripts/config-invariants.sh`:

- **I2** — subagent fail-closed (existing, KNOWN-BUGS #13 doctrine)
- **I6** — main agent fail-closed (new 2026-05-14)

Both invariants must PASS on every config edit and every weekly auto-update.

---

## 2. Why

Silent degradation is worse than visible failure for two reasons load-bearing
to Marius's actual workflow:

### 2.1 Operator doesn't notice

Marius admits in `PAI/USER/DA/isidore/opinions.yaml` (`doesnt-watch-terminal-output`)
that he is heads-down on the next move and **does not check terminal /
journal / model-id output mid-task**. When Gregor falls through Codex →
Haiku → free, the operator-facing surface is "Gregor responded" — content
is what changes, not interface. Cognitive cost of catching the degradation
in the moment is high; cost of letting it propagate into shipped work is
higher.

### 2.2 Free-tier fallback can't do tool use

Concrete proof — 2026-05-14T22:05-22:12 Crabbox smoke test. Codex hit
context overflow → compaction failed (OpenRouter 402) → assistant call
timed out 288s → failover to `claude-haiku-4-5` → 402 → failover to
`openrouter/openrouter/free`. The free-tier model **failed to invoke
the typed `crabbox_run` plugin tool**. Instead it filesystem-poked the
extension directory, misread the Go source layout (`cmd/main.go` is the
*plugin source tree*, not the binary), and declared "Crabbox binary not
found." The actual binary at `/home/openclaw/.local/bin/crabbox` was
healthy and the plugin's `config.binary` field pointed at it correctly.

The model on the free tier lacked the tool-use savvy to trust the plugin
and call the typed tool. It hallucinated a structural failure that didn't
exist. Marius saw a coherent-sounding Telegram reply and almost believed
it — the only reason he didn't was that we'd just verified Crabbox via
shell on the same host minutes earlier.

This is the failure mode I6 prevents.

---

## 3. Recovery Path When Codex Fails

With `fallbacks: []`, an operator-facing flow when Codex breaks:

1. Operator sends a message over Telegram.
2. Codex call fails (auth / rate / billing / timeout).
3. **Telegram channel surfaces the error** verbatim in the bot's reply.
4. Operator uses the **`/model` slash command** in Telegram. This is
   handled by the Telegram channel plugin **pre-LLM** — it opens an
   inline keyboard with provider + model selector. No LLM call required.
   Source: `~/.npm-global/lib/.../extensions/telegram/{api,contract-api}.js`
   imports `buildModelsKeyboard`, `resolveModelSelection`,
   `parseModelCallbackData`, `buildModelSelectionCallbackData` from a
   shared `command-ui-*.js` module that handles all UI flows without
   touching the agent.
5. Operator picks a working model from the keyboard. Subsequent messages
   use that model until the operator switches back.
6. Operator fixes the upstream issue (top up Codex / wait out rate limit /
   etc.) and switches back to Codex via `/model`.

`/model` is the load-bearing recovery primitive. If a future OpenClaw
release breaks it, I6 needs review — but as of v2026.5.6 it is verified
channel-side.

---

## 4. Compaction Is Separate

`agents.defaults.model.fallbacks` is **not** the same chain as
`compaction.model`. Compaction has its own model (currently
`openrouter/openai/gpt-4.1-mini`) and can fail independently. I6 does not
fix `openclaw-bot-154` (OpenRouter compaction request exceeds key budget)
— that's a separate config knob and separate fix path.

If compaction fails:
- The Codex retry that triggered compaction also fails.
- With I6 active, the operator sees the failure (instead of falling
  through to a degraded model) and can fix the compaction config or top
  up OpenRouter.

---

## 5. When To Reconsider

I6 should be revisited if:

1. **`/model` slash command stops working pre-LLM** — i.e. a future
   OpenClaw release moves model selection into an LLM-routed flow.
   Doctrine then forces a fallback (probably `openrouter/openrouter/free`)
   so the operator retains the ability to recover.
2. **A specific automation requires uninterrupted Gregor availability**
   that cannot tolerate any LLM-side error surfacing as a paused state.
   In that case, the automation gets its own dedicated agent in
   `agents.list[]` with its own narrow fallback chain — not the main
   agent's default chain. Treat it as carve-out, not policy change.
3. **The pack scales to multiple bots** and one of them is the
   "monitoring / health" agent whose job is to be alive 24/7 and report
   on the others. That agent gets `openrouter/openrouter/free` as its
   fallback so health reports survive Codex outages.

---

## 6. History

| Date | Event |
|------|-------|
| 2026-04-27 | Initial fallback chain configured: Codex → Sonnet → Haiku → free (bead `tm0`). Goal: keep Gregor alive across Codex OAuth flakiness. |
| 2026-05-04 | Subagent fallbacks emptied (`agents.defaults.subagents.model.fallbacks = []`) per KNOWN-BUGS #13. I2 invariant added. |
| 2026-05-14 | Main agent fallbacks emptied (`agents.defaults.model.fallbacks = []`). I6 invariant added. Driven by the Crabbox smoke incident: free-tier fallback model failed to use typed tools and produced a hallucinated diagnosis. Doctrine extended to match subagent fail-closed posture. |

---

## 7. Cross-References

- `src/scripts/config-invariants.sh` — I2 (subagent), I6 (main agent) checks.
- `Reference/KNOWN-BUGS.md` #13 — subagent silent leak that motivated I2.
- bead `tm0` — original fallback chain configuration (now retired by I6).
- bead `154` — OpenRouter compaction 402 (separate axis, still open).
- `PAI/USER/DA/isidore/opinions.yaml` `doesnt-watch-terminal-output` —
  the operator-cognition reason fail-closed beats fail-open.
