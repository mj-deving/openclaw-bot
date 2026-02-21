# Context Engineering & Session Persistence for OpenClaw

Best practices for optimizing context management, prompt caching, and session continuity. Research synthesized from Anthropic docs, OpenClaw internals, and LLM context engineering literature.

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

**What:** Switch to API key auth + `cacheRetention: "long"`

**Why:** The static prefix (tools + system prompt + workspace) gets cached. Cache reads cost 10% of base input price.

**Use `"long"` (1h) not `"short"` (5m):** Telegram conversations have natural gaps >5min between messages. The 1h TTL refreshes free on every hit, so it stays alive through a normal conversation. The 2x write cost pays for itself after a single cache hit.

**Critical caveat -- known bug:** OpenClaw issue #19534 reports cache reads showing 0 despite caching enabled. Root cause: OpenClaw injects dynamic content (timestamps, session IDs) into the system prompt, breaking the byte-identical prefix requirement. After enabling, verify via ClawMetry or API logs that `cache_read_input_tokens > 0`. If always 0, the community workaround proxy may be needed.

**Implementation:**
```bash
openclaw config set agents.defaults.models.anthropic/claude-sonnet-4.params.cacheRetention long
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
| 1 | API key auth + `cacheRetention: "long"` | 15 min | Eliminates re-processing cost for static context |
| 2 | Verify caching works (check `cache_read_input_tokens`) | 5 min | Catches known bug before assuming savings |
| 3 | `/context detail` audit of workspace files | 10 min | Identifies bloat to move to memory |
| 4 | Raise minScore to 0.40, test quality | 30 min | Reduces noise from low-relevance memories |
| 5 | Enable `memoryFlush` before compaction | 5 min | Cross-session continuity |
| 6 | Test 4 chunks instead of 6 | 30 min | Less context waste if quality holds |
| 7 | Enable MMR if memory has redundant entries | 5 min | Deduplicates at retrieval time |
| 8 | Set up ClawMetry token monitoring baseline | 1 hour | Data-driven optimization from that point |

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
