# Context Engineering & Session Persistence for OpenClaw

Best practices for optimizing context management, prompt caching, and session continuity. Research synthesized from Anthropic docs, OpenClaw internals, and LLM context engineering literature.

---

## Table of Contents

1. [The Big Picture: Where Your Tokens Go](#the-big-picture-where-your-tokens-go)
2. [Recommendation 1: Enable Prompt Caching (Highest Impact, Lowest Effort)](#recommendation-1-enable-prompt-caching-highest-impact-lowest-effort)
3. [Recommendation 2: Audit & Trim Workspace Files](#recommendation-2-audit--trim-workspace-files)
4. [Recommendation 3: Tune Memory Retrieval](#recommendation-3-tune-memory-retrieval)
5. [Recommendation 4: Session Continuity via Compaction + Memory Flush](#recommendation-4-session-continuity-via-compaction--memory-flush)
6. [Recommendation 5: Context Pruning Tuning](#recommendation-5-context-pruning-tuning)
7. [Recommendation 6: Monitor with ClawMetry](#recommendation-6-monitor-with-clawmetry)
8. [Priority Roadmap](#priority-roadmap)
9. [Lossless-Claw (LCM) — DAG-Based Context Persistence](#lossless-claw-lcm--dag-based-context-persistence)
10. [OpenClaw Context Internals Reference](#openclaw-context-internals-reference)
11. [Sources](#sources)

---

## The Big Picture: Where Your Tokens Go

Every LLM call the OpenClaw bot makes assembles this context stack:

| Component | ~Tokens | Behavior |
|-----------|---------|----------|
| Tool schemas | 5-10K | Fixed per session |
| Bootstrap/workspace files | ~35K chars (~8-10K tokens, truncated by `bootstrapMaxChars`) | Re-injected **every message** |
| Skills metadata | 1-2K | Fixed per session |
| Memory chunks | 2-4K (6 chunks @ ~700 chars) | Per-search, varies |
| Conversation history | Grows unbounded | Managed by pruning + compaction |
| Tool results | Grows fast | Prunable |

The single largest cost: **workspace files are re-injected on every single LLM call.** Over 100 messages, that's millions of tokens of static repetition.

---

## Recommendation 1: Enable Prompt Caching (Highest Impact, Lowest Effort)

**What:** Switch to Anthropic API key auth + `cacheRetention: "long"`

**Why:** The static prefix (tools + system prompt + workspace) gets cached. Cache reads cost 10% of base input price.

**Use `"long"` (1h) not `"short"` (5m):** Telegram conversations have natural gaps >5min between messages. The 1h TTL refreshes free on every hit, so it stays alive through a normal conversation. The 2x write cost pays for itself after a single cache hit.

**Critical caveat -- known bug:** OpenClaw issue #19534 reports cache reads showing 0 despite caching enabled. Root cause: OpenClaw injects dynamic content (timestamps, session IDs) into the system prompt, breaking the byte-identical prefix requirement. After enabling, verify via ClawMetry or API logs that `cache_read_input_tokens > 0`. If always 0, the community workaround proxy may be needed.

**Implementation:**
```bash
# Check exact model key first, then set cacheRetention on that key
openclaw config get agents.defaults.models
openclaw config set agents.defaults.models.anthropic/claude-sonnet-4-20250514.params.cacheRetention long
```
Then monitor: look for `cache_read_input_tokens` in API responses.

---

## Recommendation 2: Audit & Trim Workspace Files

**What:** Minimize what lives in `~/.openclaw/workspace/`

**Why:** Everything in workspace gets re-injected every message. The config caps are `bootstrapMaxChars: 20000` per file and `bootstrapTotalMaxChars: 150000` total, but even within those limits, leaner is cheaper.

**Decision framework:**

| Keep in workspace | Move to memory |
|-------------------|----------------|
| Identity/personality (needed every message) | Historical facts, project details |
| Core behavioral rules | Learned preferences |
| Security constraints | Past conversation context |
| Tool usage overrides | Reference material |

**Rule of thumb:** If removing it from a random message wouldn't break the bot's behavior, it belongs in memory, not workspace.

**Inspect current state:**
```
/context detail
```
This shows per-file, per-tool token breakdown. Target: anything not essential for every single message should move to `memory/` files where it gets retrieved by relevance instead of brute-force injected.

---

## Recommendation 3: Tune Memory Retrieval

**Current config:** 6 chunks, minScore 0.35, hybrid search (vector 0.7 + FTS 0.3)

**Research finding:** Fewer high-relevance chunks outperform more medium-relevance ones. Anthropic's own research: "a focused 300-token context often outperforms an unfocused 113,000-token context."

**Suggested experiments:**

1. **Raise minScore to 0.40-0.45.** At 0.35, medium-relevance chunks may dilute signal. Empty retrieval is better than noisy retrieval.

2. **Test reducing to 4 chunks.** If response quality holds, that saves ~30% of memory token budget per call.

3. **Enable MMR (Maximal Marginal Relevance):** If memory has redundant entries (daily notes that repeat similar content), MMR deduplicates at retrieval time:
   ```json
   "mmr": { "enabled": true, "lambda": 0.7 }
   ```

4. **Consider temporal decay** for long-running memory -- old entries naturally lose relevance:
   ```json
   "temporalDecay": { "enabled": true, "halfLifeDays": 30 }
   ```

---

## Recommendation 4: Session Continuity via Compaction + Memory Flush

**OpenClaw has two built-in mechanisms:**

**Compaction** (persistent -- rewrites transcript): Auto-triggers when context nears window limit. Summarizes older history, keeps recent messages. Can also trigger manually with `/compact`.

**Memory flush** (runs before compaction): Distills session knowledge to `memory/YYYY-MM-DD.md` before summarizing. Config:
```json
"compaction": {
  "memoryFlush": {
    "enabled": true,
    "softThresholdTokens": 40000
  }
}
```

**Best practice:** Ensure `memoryFlush.enabled: true` so important context gets persisted to memory files before compaction throws it away. This is the cross-session continuity mechanism -- without it, compaction discards older context permanently.

**For Lattice cron sessions:** These are isolated sessions (180s timeout). Consider adding a memory flush at session end so Lattice-discovered information persists to the main memory store.

---

## Recommendation 5: Context Pruning Tuning

**Current defaults:**
- Mode: `cache-ttl` (prunes old tool results by age)
- TTL: `5m` (tool results expire after 5 minutes)
- `keepLastAssistants: 3` (recent messages protected)

**Why this matters:** Tool results are the fastest-growing context consumer. A single file read or web search can inject thousands of tokens that become irrelevant within one turn.

**Tuning options:**
- If the bot does heavy tool use (file reads, web searches), consider a shorter TTL or lower `softTrimRatio` to be more aggressive about clearing stale results
- If conversations are long but tool-light, the defaults are fine

---

## Recommendation 6: Monitor with ClawMetry

**Set up token distribution tracking:**
- Break down average token usage per component (bootstrap, memory, history, tool results)
- If tool results consistently > 30% of context, prioritize more aggressive pruning
- If cache reads are always 0, investigate the dynamic content bug
- Track cost per conversation turn for baseline

**Inspection commands available now:**
- `/context detail` -- per-component token breakdown
- `/usage tokens` -- per-reply usage footer
- `/status` -- context fullness %, compaction count

---

## Priority Roadmap

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 1 | Anthropic API key auth + `cacheRetention: "long"` | 15 min | Eliminates re-processing cost for static context |
| 2 | Verify caching works (check `cache_read_input_tokens`) | 5 min | Catches known bug before assuming savings |
| 3 | `/context detail` audit of workspace files | 10 min | Identifies bloat to move to memory |
| 4 | Raise minScore to 0.40, test quality | 30 min | Reduces noise from low-relevance memories |
| 5 | Enable `memoryFlush` before compaction | 5 min | Cross-session continuity |
| 6 | Test 4 chunks instead of 6 | 30 min | Less context waste if quality holds |
| 7 | Enable MMR if memory has redundant entries | 5 min | Deduplicates at retrieval time |
| 8 | Set up ClawMetry token monitoring baseline | 1 hour | Data-driven optimization from that point |
| 9 | Evaluate Lossless-Claw plugin (see §9 below) | 1 hour | Replaces TTL pruning with persistent DAG — no context loss |

---

## Lossless-Claw (LCM) — DAG-Based Context Persistence

**GitHub:** [martian-engineering/lossless-claw](https://github.com/martian-engineering/lossless-claw)
**Version:** 0.4.0 (2026-03-18) · MIT license · 3,000+ stars
**Last checked:** 2026-03-21

### What It Is

An OpenClaw plugin that replaces the default sliding-window pruning with persistent, hierarchical summarization. The tagline: *"Bounded context, unbounded memory."*

**The problem it solves:** Traditional context management operates within a fixed token budget. When usage crosses ~80% capacity, flat summarization fires — replacing many messages with a single summary that loses detail. The model then "confidently misremembers specifics, contradicts earlier decisions." Our `cache-ttl` pruning is even more aggressive — it permanently discards messages older than 2 hours.

**LCM's approach:** Instead of discarding, LCM compacts messages into a **Directed Acyclic Graph (DAG)** of hierarchical summaries. Raw messages stay in `~/.openclaw/lcm.db`. Every summary links back to its source messages. The agent can drill into any level of detail on demand.

### What Is a DAG?

A **Directed Acyclic Graph** is a tree-like structure where nodes point in one direction (parent → children) and never form loops. Think of it like a library's catalog system:

```
                    ┌─────────────────────┐
                    │ D2: "Over the past  │  ← Weeks-level narrative
                    │ week, we hardened   │    (durable decisions,
                    │ the VPS and added   │     milestone timeline)
                    │ voice support"      │
                    └────────┬────────────┘
                     ┌───────┴────────┐
              ┌──────┴──────┐  ┌──────┴──────┐
              │ D1: "Set up │  │ D1: "Added  │  ← Hours-level arcs
              │ PARA memory │  │ Groq STT,   │    (outcomes, evolution,
              │ structure,  │  │ tested voice │     current state)
              │ 3 crons"    │  │ in Telegram" │
              └──────┬──────┘  └──────┬──────┘
               ┌─────┴─────┐    ┌─────┴─────┐
            ┌──┴──┐  ┌──┴──┐ ┌──┴──┐  ┌──┴──┐
            │ D0  │  │ D0  │ │ D0  │  │ D0  │  ← Minutes-level detail
            │msg 1│  │msg 2│ │msg 3│  │msg 4│    (specific decisions,
            │msg 2│  │msg 3│ │msg 4│  │msg 5│     rationale, config)
            │msg 3│  │msg 4│ │msg 5│  │msg 6│
            └─────┘  └─────┘ └─────┘  └─────┘
```

- **D0 (minutes):** Specific decisions, rationale, technical details — directly linked to original messages
- **D1 (hours):** Arc distillation — outcomes, evolution, current state
- **D2 (days):** Durable narrative — decisions in effect, milestone timeline
- **D3 (weeks) / D4 (months):** Higher-level compression for long-running conversations

**Condensation rule:** When 4 summaries accumulate at the same depth, they automatically synthesize into one higher-level node. This is how the DAG grows upward over time.

**Key property — "acyclic":** Summaries only point DOWN to their source messages, never back up. This means you can always trace any high-level summary all the way back to the exact messages that produced it. Nothing is lost — just compressed.

### Why It Matters for Gregor

Our previous setup used `contextPruning` with `mode: "cache-ttl"`, `TTL: "2h"`, `keepLastAssistants: 8`. This permanently discarded messages older than 2 hours — if Gregor needed something from 3 hours ago, it was gone. With LCM, those messages are compressed into the DAG and recoverable on demand.

### Architecture (5 Layers)

| Layer | What It Does |
|-------|-------------|
| **1. Persistence** | All messages stored in `~/.openclaw/lcm.db` (SQLite, optional FTS5) |
| **2. Fresh Tail** | Recent messages (default: 32) remain uncompressed, protected from summarization |
| **3. Incremental Compaction** | When messages outside the fresh tail exceed threshold, async compaction fires without interrupting conversation. Summaries form the DAG at increasing depth levels (D0→D1→D2→...) |
| **4. Context Assembly** | Each turn combines raw recent messages + compressed historical summaries within token budget (default 128K) |
| **5. Retrieval Tools** | 4 tools for the agent to drill into the DAG on demand |

### Retrieval Tools

The agent doesn't need to know the DAG structure — four tools handle navigation:

| Tool | Purpose | How It Works |
|------|---------|-------------|
| `lcm_describe` | Plan retrieval strategy | Returns subtree token counts + child manifests — "how much is stored under this node?" |
| `lcm_grep` | Search across all depths | Full-text search with depth labels — "where in the DAG does topic X live?" |
| `lcm_expand` | Drill into a specific node | Descend from a summary to its children — "show me the details behind this summary" |
| `lcm_expand_query` | Smart retrieval | Spawns a bounded sub-agent (4K token budget) to navigate the DAG strategically — full source fidelity with bounded cost |

### Key Features

- **Cost optimization:** Summarization model can differ from session model — route to Haiku for compression while keeping Sonnet for conversation
- **Session filtering:** Glob patterns to ignore/make-stateless specific sessions (e.g., cron jobs)
- **Large file handling:** Content exceeding token thresholds externalized with 3-segment sampling (beginning + middle + end)
- **LLM escalation:** Normal → Aggressive → Character truncation fallback if summarization struggles
- **Subagent delegation:** Expansion grants for child agents with automatic cleanup
- **Data integrity:** Idempotent bootstrap from JSONL, tool metadata preservation, structured content round-tripping

### Installation

```bash
openclaw plugins install @martian-engineering/lossless-claw
```

### Configuration

Environment variables (highest priority) or plugin config:

```bash
LCM_FRESH_TAIL_COUNT=32          # Recent messages protected from compaction
LCM_CONTEXT_THRESHOLD=0.75       # Compaction trigger (% of token budget)
LCM_INCREMENTAL_MAX_DEPTH=-1     # Unlimited DAG cascade depth
LCM_DB_PATH=~/.openclaw/lcm.db   # Database location
```

Recommended plugin config for Gregor:

```json
{
  "summaryProvider": "anthropic",
  "summaryModel": "claude-haiku-4-5-20251001",
  "freshTailCount": 32,
  "contextThreshold": 0.75,
  "fanout": 8
}
```

### Security Concerns (Evaluate Before Deploying)

| Concern | Severity | Notes |
|---------|----------|-------|
| Cross-session data leakage via query tools | High | No auth boundaries on `lcm_grep`/`lcm_expand` — any session can query any other |
| Prompt injection persistence | Medium | Malicious content survives compaction cycles into summaries |
| No cost circuit breaker | Medium | Heavy summarization can exhaust budget — monitor closely |
| Database growth | Low-Medium | 230MB in 4 days reported by users — add to backup.sh |

### Evaluation Plan

1. **Pre-flight:** Back up current config. Verify plugin doesn't conflict with existing `contextPruning` settings
2. **Install:** `openclaw plugins install @martian-engineering/lossless-claw`
3. **Configure:** Start conservative — use Haiku for summarization, default thresholds
4. **Test:** Run a few Telegram conversations, verify DAG formation via TUI (`lcm-tui`)
5. **Monitor:** Check `lcm.db` size growth, summarization costs, conversation quality
6. **Compare:** Side-by-side with current TTL pruning — does Gregor recall old context better?
7. **Decide:** Keep LCM or revert to TTL pruning based on cost/quality tradeoff

### Known Issues & Compatibility

| Issue | Status | Impact on Gregor |
|-------|--------|-----------------|
| **#145** Plugin loading failure: Node 22.16.0 + OpenClaw v2026.3.13 = no summaries written | Open | We're on v2026.3.12 + Node 22.x — verify compat before install |
| **#142** Installation "Invalid path" error | Open | May need workaround |
| **#70** Cross-session data leakage via lcm_grep/lcm_describe | Open | No upstream fix yet |
| **#71** Prompt injection persistence across compaction | Open | No upstream fix yet |
| **#100** False flag from OpenClaw security audit | Open | Low impact |

**Recent fixes (post-v0.4.0, landed on main):**
- Timeout protection for summarizer (60s blocks unresponsive providers)
- Session queue memory leak fix (unbounded growth eliminated)
- Media message annotation ("[Media attachment]" for media-only messages)
- Summary model persistence (stores actual model name in DB)

### Current Status

**Installed on VPS (2026-03-21).** v0.4.0, loaded and active. Configuration via systemd env vars in `/etc/systemd/system/openclaw.service.d/lcm.conf`:

```bash
LCM_SUMMARY_MODEL=claude-haiku-4-5-20251001
LCM_SUMMARY_PROVIDER=anthropic
LCM_FRESH_TAIL_COUNT=32
LCM_CONTEXT_THRESHOLD=0.75
LCM_IGNORE_SESSION_PATTERNS=cron:*,*:heartbeat*,*:daily-report*,*:para-nightly*,*:para-weekly*,*:para-monthly*
```

Plugin explicitly trusted in `plugins.allow: ["lossless-claw"]`. DB at `~/.openclaw/lcm.db`.

**Note:** Plugin config keys in `plugins.entries.lossless-claw` cause `config validate` to fail ("Unrecognized keys"). Use systemd env vars instead — they take highest priority per LCM's `resolveLcmConfig()`. The startup banner logs `(default)` for the summary model even when env vars are set; this is cosmetic — env vars override at runtime.

17 open PRs (was 21 — 4 merged since initial research). PostgreSQL + pgvector backend PR (#140/#141) in flight. Active daily development.

### Monitoring Routine

**Deployed:** `~/scripts/lcm-check.sh` on VPS (source: `src/scripts/lcm-check.sh`).

Checks: installed version vs npm latest, `lcm.db` size (warns >500MB), plugin load status, open GitHub security issues, latest release tag.

```bash
# Run manually
~/scripts/lcm-check.sh

# View results
cat ~/.openclaw/logs/lcm-check.log
```

**Cron:** Add to weekly schedule (Sunday 05:00, after doctor-fix at 04:30):

```bash
# Add via: crontab -e
0 5 * * 0 $HOME/scripts/lcm-check.sh
```

**Note on version detection:** LCM is installed via `openclaw plugins install` (not npm global). The script reads the version from `openclaw.json` → `plugins.installs.lossless-claw.resolvedVersion`.

### Open Questions

- Does LCM play nicely with our PARA memory structure, or does it duplicate what memory-core already does?
- What's the cost impact of Haiku-based summarization over a typical day of Gregor usage?
- Should cron sessions (heartbeat, daily-report, PARA) be ignored or stateless?
- Does the 230MB/4-day DB growth concern apply to our usage patterns?
- Is #145 (Node 22 + OpenClaw 3.13 loading failure) relevant to our v2026.3.12 setup?

---

## OpenClaw Context Internals Reference

### Bootstrap Injection

Workspace files are injected on every message via `resolveBootstrapContextForRun()`. Configurable limits:

| Config Key | Default | Purpose |
|------------|---------|---------|
| `agents.defaults.bootstrapMaxChars` | 20,000 | Per-file truncation limit (chars) |
| `agents.defaults.bootstrapTotalMaxChars` | 150,000 | Total bootstrap injection cap (chars) |

### Memory Search Pipeline

1. Vector query returns top `maxResults * candidateMultiplier` candidates
2. BM25 returns top `maxResults * candidateMultiplier` candidates
3. Weighted merge: `finalScore = vectorWeight * vectorScore + textWeight * textScore`
4. Optional MMR re-ranking for diversity
5. Optional temporal decay for recency bias
6. Results capped to `maxResults`

### Context Overflow Handling

1. **Pruning** fires first (in-memory, removes old tool results)
2. If still over limit, **auto-compaction** triggers (summarizes older conversation)
3. The system retries the original request with compacted context
4. If all else fails: `context_length_exceeded` error

### Prompt Caching Mechanics

- Anthropic caches prefixes in fixed order: `tools > system > messages`
- Cache keys are cumulative hashes -- block N depends on blocks 1 through N being identical
- Minimum cacheable tokens: 1,024 (Sonnet), 4,096 (Opus/Haiku)
- Cache read: 10% of base input cost
- 5min write: 1.25x base input; 1h write: 2.0x base input
- TTL refreshes free on every cache hit

### What Invalidates Cache

| Change | Impact |
|--------|--------|
| Modifying tool definitions | Invalidates entire cache |
| Toggling web search/citations | Invalidates system + messages cache |
| Changing `tool_choice` | Invalidates messages cache |
| Dynamic content in system prompt | Prevents caching entirely |

### Memory Indexing Internals

OpenClaw's memory system uses a three-tier architecture with SQLite as the indexing backend:

- **Chunking:** Markdown files are split into ~400-token chunks with ~80-token overlap, preserving semantic boundaries
- **Indexing:** `MemoryIndexManager` class manages both FTS5 virtual tables (for BM25 text search) and vector embeddings in SQLite
- **Embedding fallback chain:** local model (embeddinggemma-300m) → OpenAI → Gemini — auto-selected based on availability
- **Hybrid search:** Weighted fusion of vector similarity (0.7) and BM25 text relevance (0.3), with optional MMR re-ranking and temporal decay
- **Delta sync:** Incremental indexing — only re-indexes chunks that changed since last sync, not the entire memory store
- **Pre-compaction flush:** Before context overflow triggers auto-compaction, the system flushes important context to memory files, preventing information loss

> **Deep reference:** For full architecture details (three-tier memory model, batch optimization, SQLite schema), see [MEMORY-PLUGIN-RESEARCH.md § OpenClaw Built-in Memory Architecture](MEMORY-PLUGIN-RESEARCH.md).
>
> **Source:** [OpenClaw Memory System Deep Dive](https://snowan.gitbook.io/study-notes/ai-blogs/openclaw-memory-system-deep-dive)

---

## Sources

- [Anthropic: Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Anthropic: Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)
- [Anthropic: Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [OpenClaw Docs: Context](https://docs.openclaw.ai/concepts/context)
- [OpenClaw Docs: Memory](https://docs.openclaw.ai/concepts/memory)
- [OpenClaw Docs: Compaction](https://docs.openclaw.ai/concepts/compaction)
- [Lost in the Middle (Liu et al. 2023)](https://arxiv.org/abs/2307.03172)
- [OpenClaw GitHub Issue #19534: Cache Read Always 0](https://github.com/openclaw/openclaw/issues/19534)
- [OpenClaw GitHub Issue #9157: Workspace Injection Waste](https://github.com/openclaw/openclaw/issues/9157)
- [Lossless-Claw Plugin](https://github.com/martian-engineering/lossless-claw) — DAG-based context persistence for OpenClaw
- [LCM: Lossless Context Management — Explainer](https://www.losslesscontext.ai/) — visual explanation of the DAG architecture and retrieval system
