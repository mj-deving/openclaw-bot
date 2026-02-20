# OpenClaw Bot Token Optimization Research

**Date:** 2026-02-20
**Purpose:** Comprehensive research on reducing an OpenClaw bot's token usage
**Status:** Research complete — awaiting implementation decisions

---

## Executive Summary

the bot currently runs **claude-opus-4-6 for ALL interactions** — every Telegram message, every Lattice cron post, every heartbeat. By implementing model tiering, prompt caching, and session architecture changes, total API costs can be reduced by **70-90%**. The single highest-impact change: **routing Lattice cron posts to Haiku 4.5**, which alone cuts that workload's cost by ~80%.

**Critical finding:** Prompt caching does NOT work with setup-token (subscription) auth — only API key auth. This means the bot's biggest potential optimization requires switching auth methods.

---

## 1. Why an OpenClaw Bot Uses More Tokens Than Claude Code (The Delta Analysis)

### The Core Problem

| Factor | Claude Code (on-demand) | OpenClaw Bot (always-on) |
|--------|----------------------|-------------------|
| **Architecture** | On-demand sessions | Always-on gateway |
| **Session lifecycle** | Opens → works → closes | Persists indefinitely |
| **Autonomous calls** | 0 (user-initiated only) | 5x Lattice cron + heartbeats + Telegram |
| **Context growth** | Fresh per session | Accumulates, triggers compaction |
| **System prompt** | Loaded once per session | Re-injected EVERY message |
| **Memory injection** | No vector search overhead | 6 chunks × 400 tokens per message |
| **Compaction** | Rare (short sessions) | Frequent (long-running session) |

### Per-Message Token Overhead (the bot)

Every single message the bot processes incurs:

| Component | Approx. Tokens | Notes |
|-----------|---------------|-------|
| System prompt (OpenClaw base) | ~3,000-5,000 | OpenClaw's built-in instructions |
| Bootstrap files (AGENTS.md, personality, directives) | ~10,000-35,000 | Re-injected EVERY message |
| Loaded skills/tools definitions | ~2,000-10,000 | More skills = more tokens |
| Memory search results | ~1,600-2,400 | 4-6 chunks × 400 tokens |
| Conversation history | Grows per turn | Full JSONL resent each time |
| Tool outputs (accumulated) | Unbounded | Large outputs persist in session |

**Issue #9157** reports workspace file injection wastes **93.5% of token budget** — ~35,600 tokens injected per message for workspace context, costing $1.51 per 100-message session in redundant injection alone.

### The Daily Math

For the bot doing 20 user messages + 5 Lattice cron + heartbeats:
- ~30+ total LLM calls/day
- Each with 15K-150K input context
- Estimated **3-10M+ tokens/day**
- At Opus 4.6 pricing: significant daily cost

For Claude Code doing 20 user messages in a session:
- Messages 1-20 with growing context, but session-bounded
- Typically 500K-2M total tokens, then session ends

**The multiplicative factors:** Always-on context growth + autonomous cron calls + per-message bootstrap re-injection + memory search overhead = "multiples" of Claude Code's usage.

---

## 2. Anthropic Model Pricing (Current, Feb 2026)

### Standard API Pricing (per million tokens)

| Model | Input | Output | vs. Opus Input | vs. Opus Output |
|-------|-------|--------|----------------|-----------------|
| **Claude Opus 4.6** | $5.00 | $25.00 | baseline | baseline |
| **Claude Sonnet 4.6** | $3.00 | $15.00 | **40% cheaper** | **40% cheaper** |
| **Claude Haiku 4.5** | $1.00 | $5.00 | **80% cheaper** | **80% cheaper** |

### Prompt Caching Pricing

| Operation | Multiplier | Opus 4.6 | Sonnet 4.6 | Haiku 4.5 |
|-----------|-----------|----------|-----------|-----------|
| Cache write (5min TTL) | 1.25x input | $6.25/MTok | $3.75/MTok | $1.25/MTok |
| Cache write (1hr TTL) | 2.0x input | $10.00/MTok | $6.00/MTok | $2.00/MTok |
| **Cache read/hit** | **0.1x input** | **$0.50/MTok** | **$0.30/MTok** | **$0.10/MTok** |

Cache reads are **90% cheaper** than base input. For a system prompt that stays constant across messages, this is transformative.

### Batch API Pricing (50% off everything)

| Model | Batch Input | Batch Output |
|-------|-----------|-------------|
| Opus 4.6 | $2.50/MTok | $12.50/MTok |
| Sonnet 4.6 | $1.50/MTok | $7.50/MTok |
| Haiku 4.5 | $0.50/MTok | $2.50/MTok |

**Note:** Opus 4.6 is already 67% cheaper than the previous Opus 4/4.1 at $15/$75.

---

## 3. Model Switching Capabilities in OpenClaw

### Native Support: Per-Cron Model Override

OpenClaw natively supports per-job model overrides for isolated cron jobs:

```bash
# Lattice engagement on Sonnet instead of Opus
openclaw cron add \
  --name "lattice-engage" \
  --cron "37 8,11,15,18,21 * * *" \
  --tz "Europe/Berlin" \
  --session isolated \
  --message "Engage on Lattice..." \
  --model "anthropic/claude-sonnet-4" \
  --announce
```

Or edit existing:
```bash
openclaw cron edit <jobId> --model "anthropic/claude-haiku-4-5" --thinking off
```

**Priority chain:** job payload override > hook-specific defaults > agent config default.

### Per-Agent Model Overrides in openclaw.json

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-20250514",
        "fallbacks": ["anthropic/claude-haiku-4-5"]
      }
    },
    "named": {
      "complex-tasks": {
        "model": { "primary": "anthropic/claude-opus-4-6" }
      }
    }
  }
}
```

### Dynamic Model Selection (Feature Requests)

- **[Issue #7468](https://github.com/openclaw/openclaw/issues/7468):** Context-size-based routing (proposed, not merged)
- **[Issue #10969](https://github.com/openclaw/openclaw/issues/10969):** Middleware hook for cost-saving model routing
- **[Discussion #858](https://github.com/openclaw/openclaw/discussions/858):** Opus-as-Orchestrator pattern (community approach)

### Community Routing Solutions

| Tool | What It Does | Source |
|------|-------------|--------|
| **ClawRouter** | Agent-native LLM router for OpenClaw | [BlockRunAI/ClawRouter](https://github.com/BlockRunAI/ClawRouter) |
| **model-hierarchy-skill** | Cost-optimized routing by task complexity | [zscole/model-hierarchy-skill](https://github.com/zscole/model-hierarchy-skill) |
| **OpenRouter Auto** | Auto-selects cheapest adequate model | [openrouter.ai](https://openrouter.ai/docs/guides/guides/openclaw-integration) |
| **LiteLLM local proxy** | Local routing layer for intelligent model selection | [Community gist](https://gist.github.com/digitalknk/ec360aab27ca47cb4106a183b2c25a98) |

### Recommended Routing for the bot

No ML classifier needed. Simple rule-based routing:

| Query Type | Route To | Method |
|------------|----------|--------|
| Lattice cron posts | **Haiku 4.5** | Deterministic — known task type |
| Simple Telegram greetings/reactions | **Haiku 4.5** | Keyword matching |
| Factual Q&A, status queries | **Sonnet 4.6** | Default conversational model |
| Complex reasoning, creative tasks | **Opus 4.6** | User escalation or explicit `/opus` command |

---

## 4. Token Monitoring & Observability

### OpenClaw Built-in Commands

| Command | What It Shows |
|---------|-------------|
| `/status` | Session model, context usage, last response I/O tokens, estimated cost |
| `/usage off\|tokens\|full` | Per-response usage footer (persists per session) |
| `/usage cost` | Local cost summary from session logs |
| `/context list` | Token breakdown per file, tools, system prompt |
| `/context detail` | Detailed context analysis |
| `openclaw status --usage` | Provider quota windows |

### Third-Party Observability

| Tool | What It Does | Install |
|------|-------------|---------|
| **ClawMetry** | Real-time observability dashboard — per-session cost, sub-agent activity, tool calls | `pip install clawmetry` |
| **ClawWatcher** | Dashboard showing token usage, cost per model, skills and actions | [HN thread](https://news.ycombinator.com/item?id=46954200) |
| **tokscale** | CLI for tracking token usage from OpenClaw, Claude Code, and others | [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) |

### steipete's model-usage Skill

The `model-usage` skill (7.2K downloads) analyzes **per-model cost data** from CodexBar's local logs. It provides current model cost or full breakdown across all models.

**Limitation for the bot:** CodexBar is a macOS menu bar app designed for local development. For a VPS deployment, **ClawMetry is more appropriate** — it's designed for server-side observability. The built-in `/usage` commands are the immediate first step.

### Recommended Monitoring Implementation

**Phase 1 (immediate):** Enable `/usage full` to see per-response token counts. Use `/context list` to identify the biggest context consumers.

**Phase 2:** Install ClawMetry for continuous dashboard monitoring. Establish daily baseline metrics.

**Phase 3:** Build a simple script that parses `~/.openclaw/cron/runs/<jobId>.jsonl` to track per-cron-job token consumption over time.

---

## 5. Cron Engagement Optimization (Lattice)

### Current State

- **5x/day** Lattice engagement via OpenClaw cron (`37 8,11,15,18,21 * * *` Berlin)
- **sessionTarget: "isolated"** — each run starts fresh (no context accumulation)
- **Model: claude-opus-4-6** — same as everything else
- **180-second timeout** per engagement session

### Per-Cron Token Economics

Each isolated cron run incurs:
- Full system prompt reload: ~3,000-5,000 tokens
- Bootstrap file injection: ~10,000+ tokens
- Memory search for Lattice context: ~1,600 tokens
- User message (cron prompt): ~200 tokens
- **Total input per cron: ~15,000-17,000 tokens**
- Output (engagement post + Telegram announce): ~500-1,024 tokens

**Current daily cron cost (estimated):**
- 5 runs × 16,000 input × $5.00/MTok = $0.40 input
- 5 runs × 800 output × $25.00/MTok = $0.10 output
- **Total: ~$0.50/day on Lattice cron alone**

### Optimization Strategies

**Strategy A: Model Downgrade (Highest Impact, Easiest)**
Switch Lattice cron from Opus to Haiku:
- Input: 5 × 16,000 × $1.00/MTok = $0.08
- Output: 5 × 800 × $5.00/MTok = $0.02
- **Savings: $0.40/day → $0.10/day (80% reduction)**

**Strategy B: Haiku + Reduced Bootstrap**
Reduce bootstrap injection for cron (use minimal personality prompt):
- Input: 5 × 5,000 × $1.00/MTok = $0.025
- Output: same
- **Savings: ~93% reduction**

**Strategy C: Batch API Pre-Generation**
Pre-generate all 5 daily posts in a single batch call:
- 1 batch call × 80,000 input × $0.50/MTok = $0.04
- 1 batch call × 5,000 output × $2.50/MTok = $0.0125
- **Savings: ~90% reduction, with posts queued for scheduled delivery**

**Strategy D: Weekly Batch Pre-Generation (Maximum Savings)**
Pre-generate a week's worth (35 posts) in a single batch call:
- 1 call per week instead of 35
- **Savings: ~96% reduction on cron token costs**

### Recommendation

Start with **Strategy A** (simplest: just change the `--model` on the cron job). Then evaluate quality. If Haiku quality is sufficient for social posts (likely — Lattice engagement doesn't need deep reasoning), keep it. If not, use Sonnet as the middle ground (still 40% cheaper than Opus).

---

## 6. Prompt Optimization Strategies

### System Prompt Compression

Every token in the system prompt is charged on EVERY query. Strategies:

1. **Audit and trim**: Remove redundant instructions, merge overlapping directives. Community reports 30-50% reduction achievable through manual editing.
2. **Tiered system prompts**: Full personality for Opus complex tasks; stripped personality for Sonnet routine queries; minimal instructions for Haiku cron tasks.
3. **Token-efficient formatting**: Markdown bullets over prose. Remove filler words ("please", "make sure to"). Use YAML-like structured formats for directives.

### Bootstrap File Optimization

| Setting | Default | Recommended | Effect |
|---------|---------|-------------|--------|
| `bootstrapMaxChars` | 20,000 | 10,000 | Community reports no functionality loss |
| `bootstrapTotalMaxChars` | 150,000 | 50,000 | Caps total injection |
| AGENTS.md length | Varies | 20-60 lines max | Reduces per-message overhead |

### Memory Context Pruning

Current: 6 chunks × 400 tokens = 2,400 tokens per query.

Optimization options:
- **Raise relevance threshold**: Only inject chunks above cosine similarity 0.75 (vs current 0.35). Many queries may only need 2-3 chunks.
- **Cron tasks need fewer chunks**: Lattice posts probably need 0-2 memory chunks, not 6. Custom memory config per cron job.
- **Dynamic chunk count**: Scale by query complexity — simple = 2 chunks, complex = 6.

### Prompt Caching (CRITICAL CAVEAT)

**Prompt caching does NOT work with setup-token (subscription) auth.** OpenClaw auto-applies `cacheRetention: "short"` for API key auth only.

This means the bot currently gets **zero prompt caching benefit**. The system prompt is fully re-processed every single message.

**To unlock prompt caching:**
1. Switch from setup-token to direct API key auth at console.anthropic.com
2. Configure `cacheRetention: "long"` in openclaw.json
3. Set heartbeat interval to 55 minutes (keeps cache warm within 60-min TTL)
4. Expected savings: **50-90% on input tokens** for the cached system prompt portion

```json
{
  "agents": {
    "defaults": {
      "models": {
        "anthropic/claude-opus-4-6": {
          "params": {
            "cacheRetention": "long"
          }
        }
      },
      "heartbeat": {
        "every": "55m"
      }
    }
  }
}
```

### Context Compaction Optimization

```json
{
  "compaction": {
    "memoryFlush": {
      "enabled": true,
      "softThresholdTokens": 40000
    }
  },
  "contextPruning": {
    "mode": "cache-ttl",
    "ttl": "6h",
    "keepLastAssistants": 3
  }
}
```

Compaction itself costs tokens (it's an LLM summarization call) but prevents the much larger cost of unbounded context growth.

---

## 7. Workflow Coupling Opportunities

Optimizations that compound when implemented together:

### Coupling 1: Model Tiering + Prompt Caching
- Switch default to Sonnet 4.6 + enable prompt caching
- Cached Sonnet input: $0.30/MTok (vs uncached Opus $5.00/MTok = **94% savings**)

### Coupling 2: Cron Model Downgrade + Bootstrap Reduction
- Haiku for cron + minimal bootstrap files
- Drops per-cron input from ~16K tokens on Opus to ~5K tokens on Haiku
- Combined savings: ~93%

### Coupling 3: Monitoring + Optimization Feedback Loop
- Enable `/usage full` → identify biggest token consumers
- Use `/context list` → see which bootstrap files waste the most tokens
- Optimize based on real data → re-measure
- Continuous improvement cycle

### Coupling 4: API Key Auth + Caching + Session Architecture
- Switch to API key auth (enables prompt caching)
- Set `cacheRetention: "long"` + heartbeat at 55 min
- Use isolated sessions for cron (clean context) + shared sessions for Telegram (cache benefit)
- Prompt caching reduces Telegram conversation input by 50-90%

---

## 8. Implementation Roadmap (Priority-Ordered)

### Tier 1: Quick Wins (implement now, config changes only)

| # | Action | Est. Savings | Effort | Details |
|---|--------|-------------|--------|---------|
| 1 | **Switch Lattice cron to Haiku/Sonnet** | 40-80% on cron | 5 min | `openclaw cron edit <id> --model "anthropic/claude-haiku-4-5"` |
| 2 | **Enable `/usage full`** | 0% (monitoring) | 1 min | Establish baseline — know what you're spending |
| 3 | **Reduce bootstrapMaxChars to 10,000** | ~15% total | 2 min | Config change in openclaw.json |
| 4 | **Trim system prompt / AGENTS.md** | 10-20% input | 30 min | Audit, remove redundancy, compress to <60 lines |
| 5 | **Disable extended thinking for cron** | Variable | 2 min | `--thinking off` on cron jobs |

### Tier 2: Medium-Term (requires auth/architecture changes)

| # | Action | Est. Savings | Effort | Details |
|---|--------|-------------|--------|---------|
| 6 | **Switch to API key auth** | Enables caching | 15 min | console.anthropic.com → create API key → `openclaw models auth` |
| 7 | **Enable prompt caching** | 50-90% input | 10 min | `cacheRetention: "long"` + heartbeat 55m |
| 8 | **Switch default model to Sonnet** | 40% overall | 5 min | Keep Opus available via `/model opus` for complex tasks |
| 9 | **Install ClawMetry** | 0% (monitoring) | 10 min | `pip install clawmetry` — server-side dashboard |
| 10 | **Configure context pruning** | Variable | 10 min | `contextPruning.mode: "cache-ttl"`, TTL 6h |

### Tier 3: Advanced (requires code/architecture changes)

| # | Action | Est. Savings | Effort | Details |
|---|--------|-------------|--------|---------|
| 11 | **Implement rule-based model routing** | 60-70% overall | 2-4 hrs | Message length + keyword classifier → route to Haiku/Sonnet/Opus |
| 12 | **Pre-generate Lattice posts via Batch API** | 90%+ on cron | 2-4 hrs | Daily batch generation, queued delivery |
| 13 | **Semantic response caching** | 50-68% call reduction | 4-8 hrs | Embedding-based similarity → cached response |
| 14 | **Reduce memory chunks for cron** | ~20% per cron | 1-2 hrs | Custom memory config per session type |

### Combined Impact Estimate

If Tier 1 + Tier 2 implemented:
- **Cron workload (5x/day):** ~80-93% reduction
- **Telegram routine (~70% messages):** ~60-70% reduction (Sonnet + caching)
- **Telegram complex (~30% messages):** ~40-50% reduction (Opus with caching)
- **Overall estimated reduction: 70-85%**

---

## 9. Auth Method Decision Point

**Current:** Setup-token (Claude Max subscription) — no separate API cost, but no prompt caching.

**Alternative:** Direct API key (console.anthropic.com) — pay-per-token, but full prompt caching support.

| Aspect | Setup-Token | API Key |
|--------|-----------|---------|
| Prompt caching | **NO** | **YES** |
| Pricing | Subscription-included | $5/$25 per MTok (Opus) |
| Rate limits | Subscription-tier | API-tier |
| Monthly cost predictability | Fixed (subscription) | Variable (usage-based) |

**The decision:** If the bot's uncached token usage costs more than the potential caching savings, API key auth pays for itself. Given that prompt caching saves 50-90% on input tokens, and the bot processes potentially millions of input tokens/day, the break-even point is likely within the first day.

However, with Claude Max subscription, the setup-token usage might be "free" (included in subscription). If Anthropic doesn't meter setup-token usage against the subscription cap, then the uncached setup-token approach may still be cheaper than API key + caching. **This needs verification against your actual subscription terms.**

---

## Sources

### Official Documentation
- [Token Use and Costs — OpenClaw Docs](https://docs.openclaw.ai/reference/token-use)
- [Compaction — OpenClaw Docs](https://docs.openclaw.ai/concepts/compaction)
- [Cron Jobs — OpenClaw Docs](https://docs.openclaw.ai/automation/cron-jobs)
- [Anthropic Provider — OpenClaw Docs](https://docs.openclaw.ai/providers/anthropic)
- [Anthropic Official Pricing](https://platform.claude.com/docs/en/about-claude/pricing)

### GitHub Issues & Discussions
- [#7468: Dynamic Model Selection Based on Context Size](https://github.com/openclaw/openclaw/issues/7468)
- [#10969: Middleware Hook for Cost-Saving Model Routing](https://github.com/openclaw/openclaw/issues/10969)
- [#9157: Workspace file injection wastes 93.5% of token budget](https://github.com/openclaw/openclaw/issues/9157)
- [#14377: First-class usage logging for automated jobs](https://github.com/openclaw/openclaw/issues/14377)
- [#12299: No programmatic access to cumulative token usage](https://github.com/openclaw/openclaw/issues/12299)
- [Discussion #858: Opus-as-Orchestrator](https://github.com/openclaw/openclaw/discussions/858)
- [Discussion #1949: Burning through tokens](https://github.com/openclaw/openclaw/discussions/1949)

### Community Resources
- [ClawRouter — Agent-native LLM router](https://github.com/BlockRunAI/ClawRouter)
- [model-hierarchy-skill — Cost-optimized routing](https://github.com/zscole/model-hierarchy-skill)
- [Running Without Burning Money — Community gist](https://gist.github.com/digitalknk/ec360aab27ca47cb4106a183b2c25a98)
- [Multi-model routing guide — VelvetShark](https://velvetshark.com/openclaw-multi-model-routing)
- [Cut Token Costs by 77% — ClawHosters](https://clawhosters.com/blog/posts/openclaw-token-kosten-senken)
- [Why OpenClaw is Token-Intensive — Apiyi](https://help.apiyi.com/en/openclaw-token-cost-optimization-guide-en.html)
- [ClawMetry — Observability dashboard](https://www.producthunt.com/products/clawmetry)
- [steipete/model-usage SKILL.md](https://github.com/openclaw/skills/blob/main/skills/steipete/model-usage/SKILL.md)
