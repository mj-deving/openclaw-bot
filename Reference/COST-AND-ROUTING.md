# Cost & Provider Routing Strategy for OpenClaw

Best practices for choosing providers, optimizing routing, and controlling costs. Research synthesized from provider pricing pages, ClawRouter documentation, OpenClaw internals, and community analysis (February 2026).

---

## The Big Picture: Four Cost Levers

Every token you send or receive has a price. You control cost through four independent mechanisms:

| Lever | What It Does | Savings Potential | Effort |
|-------|-------------|-------------------|--------|
| **Prompt caching** | Reuse static context across messages | 90% on repeated input | Low (one config change) |
| **Model routing** | Send simple tasks to cheap models | 50-90% on routed tasks | Medium (config + testing) |
| **Provider selection** | Pick the cheapest provider for equivalent quality | 20-80% depending on task | Medium (comparison shopping) |
| **Context optimization** | Reduce token volume per message | Proportional to reduction | High (ongoing tuning) |

This document covers levers 2 and 3. For lever 1 (caching mechanics) and lever 4 (context optimization), see [CONTEXT-ENGINEERING.md](CONTEXT-ENGINEERING.md).

---

## 1. Provider Pricing Comparison (February 2026)

### 1.1 Anthropic (Claude)

| Model | Input (/MTok) | Output (/MTok) | Cached Input (/MTok) | Context |
|-------|--------------|----------------|---------------------|---------|
| **Opus 4.6** | $5.00 | $25.00 | $0.50 | 200K |
| **Sonnet 4.6** | $3.00 | $15.00 | $0.30 | 200K |
| **Haiku 4.5** | $1.00 | $5.00 | $0.10 | 200K |

- **Batch API:** 50% off all prices for non-urgent tasks
- **Cache write cost:** 25% premium on 5-minute TTL, 100% premium on 1-hour TTL
- **Cache read:** 10% of base input price (90% savings)
- **Cache TTL:** 5 minutes ("short") or 60 minutes ("long"), refreshes free on every hit
- **Minimum cacheable tokens:** 1,024 (Sonnet), 4,096 (Opus/Haiku)
- **Rate limits (Tier 1):** 50 RPM, 30K ITPM (Sonnet), 50K ITPM (Haiku), $100/mo spend limit, $5 deposit
- **Web search:** $10 per 1,000 searches (additional cost)
- **Note:** Cached tokens do NOT count towards ITPM rate limits

Source: [Anthropic Pricing](https://docs.anthropic.com/en/docs/about-claude/models), [Rate Limits](https://platform.claude.com/docs/en/api/rate-limits)

### 1.2 OpenAI

| Model | Input (/MTok) | Output (/MTok) | Cached Input (/MTok) | Context |
|-------|--------------|----------------|---------------------|---------|
| **GPT-4o** | $2.50 | $10.00 | $1.25 | 128K |
| **GPT-4o-mini** | $0.15 | $0.60 | $0.075 | 128K |
| **o3** | $2.00 | $8.00 | $0.50 | 200K |
| **o4-mini** | $1.10 | $4.40 | $0.275 | 200K |

- **Batch API:** 50% off
- **Reasoning token caveat:** o-series models produce internal "reasoning tokens" billed as output tokens but invisible in API responses. Actual output cost can be significantly higher than raw pricing suggests.
- **Rate limits (Tier 1):** 500 RPM, $5 deposit
- **Free tier:** 3 RPM, GPT-3.5 Turbo only

Source: [OpenAI Pricing](https://platform.openai.com/docs/pricing), [pricepertoken.com](https://pricepertoken.com)

### 1.3 Google (Gemini)

| Model | Input (/MTok) | Output (/MTok) | Cached Input (/MTok) | Context |
|-------|--------------|----------------|---------------------|---------|
| **Gemini 2.5 Pro** | $1.25 | $10.00 | $0.31 | 1M |
| **Gemini 2.5 Flash** | $0.30 | $2.50 | $0.075 | 1M |
| **Gemini 2.0 Flash** | $0.10 | $0.40 | ~$0.025 (est.) | 1M |

- **Batch API:** 50% off
- **Cache storage:** $1.00-4.50/MTok/hour (model-dependent) -- makes caching cost-effective only for high-frequency reuse
- **Free tier:** 15 RPM, most models including 2.5 Flash. Free tier data may be used to improve Google products.
- **Context window:** 1M tokens across all current models -- the largest available

Source: [Gemini Pricing](https://ai.google.dev/gemini-api/docs/pricing)

### 1.4 DeepSeek

| Model | Input (/MTok) | Output (/MTok) | Cache Hit (/MTok) | Context |
|-------|--------------|----------------|-------------------|---------|
| **DeepSeek-V3** | $0.27 | $1.10 | $0.07 | 128K |
| **DeepSeek-R1** | $0.55 | $2.19 | $0.14 | 128K |

- Aggressive pricing, strong coding/reasoning performance
- Available direct or through OpenRouter
- Generous rate limits for the price

Source: [DeepSeek Pricing](https://platform.deepseek.com/api-docs/pricing)

### 1.5 OpenRouter (Gateway)

OpenRouter is not a model provider -- it's a **gateway** that routes to other providers.

- **Pricing:** Pass-through at underlying provider rates. 5.5% platform fee on credit card purchases.
- **No per-request fees:** Billing is purely token-based.
- **Free models:** DeepSeek R1, Llama 3.3 70B, Gemma 3 and others (rate-limited: ~20 req/min, 200/day)
- **Auto-router:** `openrouter/auto` uses NotDiamond to pick optimal model per request at no extra cost (see Section 3)
- **Provider restriction:** `allowed_models` parameter limits routing to specific providers (e.g., `anthropic/*`)

Source: [OpenRouter Docs](https://openrouter.ai/docs)

### 1.6 Ollama (Local)

Running models locally on your own hardware. No API costs, but real constraints:

| Model Size | RAM Required | Speed (CPU-only, 8 cores) | Viability |
|-----------|-------------|--------------------------|-----------|
| **7B** (Gemma 3 4B, Phi-4, Qwen2.5-7B) | 4-8 GB | 5-10 tok/sec | Usable for simple tasks |
| **13B** (CodeLlama-13B, Llama 3.2-13B) | 10-16 GB | 2-5 tok/sec | Slow but workable |
| **32B+** (Qwen2.5-32B, DeepSeek-V3-Lite) | 20+ GB | <2 tok/sec | Impractical without GPU |

**On a 24GB RAM / 8-core CPU VPS with no GPU:**
- 7B models are practical for classification, simple Q&A, and format conversion
- 13B models work but latency makes interactive Telegram use frustrating
- Anything larger is too slow for real-time responses
- Main value: zero-cost fallback, complete privacy, no API dependency

---

## 2. ClawRouter Deep Dive

### 2.1 What Is ClawRouter?

[ClawRouter](https://github.com/BlockRunAI/ClawRouter) (3,150 stars, MIT license, v0.9.39) is an **OpenClaw-native LLM router** by BlockRunAI. It intercepts model requests and routes them to the cheapest capable model using a 15-dimension weighted scoring classifier running locally in <1ms.

**Key facts:**
- Created: February 3, 2026 (less than 3 weeks old)
- Last release: v0.9.39 (February 21, 2026) -- actively maintained, rapid iteration
- Language: TypeScript
- ClaHub status: [Issue #125](https://github.com/openclaw/clawhub/issues/125) -- proposed as provider plugin, open, 0 community comments
- HN reception: 12 points, 1 comment -- minimal community validation

### 2.2 How It Works

ClawRouter classifies requests into four tiers and routes accordingly:

| Tier | Typical Distribution | Default Model | Fallback |
|------|---------------------|---------------|----------|
| **SIMPLE** | ~55% of requests | claude-haiku-4.5 | deepseek-chat |
| **MEDIUM** | ~31% | deepseek-chat / kimi-k2.5 | gpt-4o-mini, gemini-2.5-flash |
| **COMPLEX** | ~7% | claude-sonnet-4.6 | gpt-4o, gemini-2.5-pro |
| **REASONING** | ~7% | deepseek-reasoner | o3-mini, claude-sonnet-4.6 |

**15 scoring dimensions:** reasoning markers (0.18 weight), code presence (0.15), agentic keywords, tool requirements, context length, structured output needs, and more. All configurable via `openclaw.yaml`.

**Additional features:**
- Response cache (10-minute TTL, 200-entry limit)
- Agentic auto-detection (routes multi-step tasks to specialized models)
- Context-length-aware routing (filters incompatible models before they fail)
- Session pinning (1-hour conversation continuity)
- Cost tracking (`/stats` command shows savings)
- Free tier fallback (routes to gpt-oss-120b when wallet balance reaches $0)

**Claimed savings:** 74-100% on Auto strategy, up to 91.4% in documented examples ($18.40 saved over 7 days).

### 2.3 x402: The Agent Micropayment Standard

ClawRouter uses the [x402 protocol](https://www.x402.org) for **USDC micropayments on the Base L2 blockchain**. x402 is a Coinbase-backed HTTP payment standard designed specifically for machine-to-machine transactions -- it's emerging as *the* agent micropayment protocol and will likely see wide adoption as autonomous agents increasingly need to pay for services programmatically.

**How it works:**
1. Install via `curl -fsSL https://blockrun.ai/ClawRouter-update | bash`
2. A wallet is auto-generated at `~/.openclaw/blockrun/wallet.key`
3. Fund the wallet with USDC on Base ($5 minimum recommended)
4. Each LLM request includes a cryptographic signature (EIP-712) authorizing micropayment
5. Private key stays local -- only signatures are transmitted
6. A local x402 proxy runs on port 8402

**Security model (honest assessment):**

| Aspect | Assessment |
|--------|-----------|
| **USDC exposure** | Stablecoin (1:1 USD, Circle-issued, Deloitte-audited). Financial exposure capped at wallet balance -- actually *safer* than API keys linked to credit cards with unlimited spend |
| **Wallet key storage** | Plaintext at `~/.openclaw/blockrun/wallet.key` -- identical security model to API keys in `openclaw.json`. If you trust one, the principle for trusting the other is the same |
| **x402 proxy** | Port 8402 on loopback. Standard HTTP proxy pattern, equivalent to the OpenClaw gateway on 18789 |
| **Base L2 RPC** | Standard JSON-RPC over HTTPS to Coinbase infrastructure. Same trust model as any cloud API call |
| **EIP-712 signing** | Cryptographic authorization per-request. Key never leaves the machine -- only signatures are transmitted |
| **Project maturity** | 18 days old. v0.9.x. Active iteration. Zero ClaHub community comments yet. No independent security audit |

**The bigger picture:** A capable agent *should* eventually hold wallet keys and interact with blockchain APIs and smart contracts. The x402 payment layer is early infrastructure for that future -- not an attack surface to avoid, but a capability to grow into.

**The `curl | bash` concern (separate from crypto):**

The install method `curl -fsSL URL | bash` is a supply chain risk independent of what's being installed:

- **DNS hijack:** Attacker poisons DNS resolution, serves a malicious script from a lookalike server
- **CDN compromise:** The legitimate CDN serves a tampered payload (rare but has happened -- [codecov 2021](https://about.codecov.io/security-update/), ua-parser-js 2021 supply chain attack)
- **No pre-execution audit:** The script runs before you can read it. On a VPS with `exec.security: "full"`, this means arbitrary code execution as the `openclaw` user
- **No checksum verification:** No `.sha256` file to verify integrity independently
- **No atomic rollback:** If the script modifies system state halfway through and fails, cleanup is manual

**Mitigation:** `curl -fsSL URL -o install.sh && less install.sh && bash install.sh` -- download first, audit, then run. ClawRouter doesn't officially document this path, but it works. This constraint may need loosening as the agent ecosystem matures and more tools adopt this install pattern -- the tradeoff between auditability and adoption friction is an ongoing one

### 2.4 The Crypto-Free Fork (Alternative)

[cgaeking/ClawRouter](https://github.com/cgaeking/ClawRouter) is a community fork that **strips the crypto payment layer** and replaces it with direct provider API keys + optional OpenRouter fallback. Useful if you want the routing engine without x402 -- though you lose the micropayment capability that makes ClawRouter unique.

**Removed:** USDC/x402 payments, wallet generation, balance monitoring, payment caching, `viem` dependency (~2MB), BlockRun API gateway

**Preserved:** 15-dimension routing engine, 4-tier classification, agentic auto-detection, fallback chains, session pinning, rate-limit awareness, SSE heartbeat, request deduplication

**How it works:** Supply your own API keys (Anthropic, OpenAI, Google, xAI, DeepSeek, Moonshot, NVIDIA). Direct keys take priority; OpenRouter serves as fallback if configured.

**Assessment:** Simpler setup if you only want routing without blockchain interaction. **Caveat:** Independent fork with unknown maintenance commitment -- may diverge from upstream as ClawRouter iterates rapidly.

### 2.5 ClawRouter vs OpenRouter vs Manual Routing

| Factor | ClawRouter (original) | ClawRouter (fork) | OpenRouter Auto | Manual (OpenClaw native) |
|--------|----------------------|-------------------|-----------------|------------------------|
| **Routing intelligence** | 15-dimension local scoring | Same | NotDiamond (server-side, opaque) | Human judgment via `/model` |
| **Latency** | <1ms (local) | <1ms (local) | +50-100ms (server) | 0 (no routing) |
| **Payment** | USDC crypto (x402) | Direct API keys | Credit card | Direct API keys |
| **Attack surface** | Moderate (proxy + wallet, equivalent to API keys) | Low (just routing) | Low (HTTPS gateway) | Minimal |
| **Model consistency** | Low (routes across providers) | Low (same) | Low (same) | High (you choose) |
| **Prompt caching** | Incompatible (multi-provider) | Incompatible | Incompatible | Fully compatible |
| **Setup effort** | Medium (wallet funding) | Low | Low | Low |
| **Maturity** | 18 days, v0.9.x | Newer fork | Established | Built-in |

---

## 3. OpenRouter Auto-Router (NotDiamond)

Set model to `openrouter/auto` and OpenRouter's NotDiamond-powered router analyzes each prompt to select the optimal model.

**Configuration:**
```bash
openclaw config set provider.name openrouter
openclaw config set provider.apiKey "sk-or-YOUR-KEY"
openclaw config set provider.model "openrouter/auto"
```

**Routing modifiers:**

| Modifier | Model ID | Behavior |
|----------|----------|----------|
| Auto (default) | `openrouter/auto` | Best model for the prompt |
| Nitro | `openrouter/auto:nitro` | Fastest throughput |
| Floor | `openrouter/auto:floor` | Lowest price per token |
| Provider filter | `allowed_models: ["anthropic/*"]` | Restrict to specific providers |

**Limitations:**
- Routing decisions are server-side and opaque -- you can't inspect selection logic
- Multi-provider routing **invalidates prompt caches** (the bigger win, see Section 5)
- Model pool shifts between providers -- inconsistent personality for a bot like Gregor
- No published accuracy benchmarks for the routing classifier

**Best use case:** Cost discovery and experimentation. Use `:floor` modifier for Lattice heartbeats where personality matters less. For primary conversations, manual model selection gives better consistency.

---

## 4. Manual Routing with OpenClaw (Native Config)

OpenClaw has built-in model selection without any third-party tools. This is the simplest and most secure approach.

### 4.1 Primary + Fallback Chain

```jsonc
// ~/.openclaw/openclaw.json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6",
        "fallbacks": [
          "anthropic/claude-haiku-4-5",
          "deepseek/deepseek-chat",
          "google/gemini-2.5-flash"
        ]
      }
    }
  }
}
```

**Failover triggers:** Auth failures, billing exhaustion, rate limits (429), timeouts, service unavailability. Context overflow triggers compaction, not failover.

**Failover sequence:**
1. Primary model with current auth profile
2. Next auth profile for same provider (if multiple exist)
3. Next fallback model from the configured list
4. Repeat until success or all options exhausted

Failed profiles receive cooldown timers (`billingBackoffHours` ramping to `billingMaxHours`) to prevent rapid retry loops.

### 4.2 Task-Specific Model Assignment

```jsonc
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6"
      },
      "models": {
        "anthropic/claude-sonnet-4-6": { "alias": "sonnet" },
        "anthropic/claude-opus-4-6": { "alias": "opus" },
        "anthropic/claude-haiku-4-5": { "alias": "haiku" },
        "google/gemini-2.5-flash": { "alias": "flash" }
      },
      "heartbeat": {
        "every": "55m",
        "model": "anthropic/claude-haiku-4-5"
      },
      "subagents": {
        "model": "google/gemini-2.5-flash"
      }
    }
  }
}
```

**Recommended model assignment:**

| Workload | Model | Cost (in/out per MTok) | Rationale |
|----------|-------|----------------------|-----------|
| **Primary conversation** | Sonnet 4.6 | $3 / $15 | Best quality/cost for general use |
| **Cron/Lattice tasks** | Haiku 4.5 | $1 / $5 | Simple, scheduled, repetitive |
| **Heartbeat/keepalive** | Haiku 4.5 | $1 / $5 | Minimal cost for cache-warming |
| **Complex reasoning** | Opus 4.6 | $5 / $25 | On-demand via `/model opus` |
| **Subagents** | Gemini 2.5 Flash | $0.30 / $2.50 | Cheap, fast, 1M context |

### 4.3 Runtime Model Switching

```
/model list          # Show available models
/model sonnet        # Switch to Sonnet (via alias)
/model opus          # Switch to Opus for complex task
/model haiku         # Switch back for simple work
/model status        # Current model and fallback chain
```

### 4.4 CLI Management

```bash
openclaw models set anthropic/claude-sonnet-4-6           # Change primary
openclaw models fallbacks add anthropic/claude-haiku-4-5   # Add fallback
openclaw models fallbacks add google/gemini-2.5-flash      # Add another
openclaw models aliases add sonnet anthropic/claude-sonnet-4-6
openclaw models aliases add opus anthropic/claude-opus-4-6
openclaw models aliases add haiku anthropic/claude-haiku-4-5
```

---

## 5. Caching Economics

Full caching mechanics are documented in [CONTEXT-ENGINEERING.md](CONTEXT-ENGINEERING.md). This section covers the **cost math** only.

### 5.1 Break-Even Calculation

Anthropic prompt caching write premiums:
- **5-minute TTL:** 125% of base input price (25% premium)
- **1-hour TTL:** 200% of base input price (100% premium)
- **Cache read (both):** 10% of base input price (90% savings)
- **TTL refresh:** Free on every cache hit — no additional write charge

**Break-even with 5-minute TTL:** 1 write + 1 read = 125% + 10% = 135% vs 200% uncached. **Pays for itself on the second message.**

**Break-even with 1-hour TTL:** 1 write + 1 read = 200% + 10% = 210% vs 200% uncached. The first read doesn't quite break even, but by the third message (200% + 10% + 10% = 220% vs 300%) you're well ahead. **Pays for itself on the third message.**

**Why use 1-hour despite the higher write cost?** Telegram conversations have natural gaps >5 minutes between messages. With 5-minute TTL, each gap triggers a new cache write (1.25×). With 1-hour TTL, a single write (2×) covers an entire conversation session. For a personal bot with sporadic usage, 1-hour TTL produces fewer total writes and lower overall cost.

### 5.2 Real-World Savings (Sonnet 4.6)

The OpenClaw bootstrap context (workspace files, tools, system prompt) is approximately 35K tokens, re-sent on every message. These numbers show **bootstrap input cost only** — output tokens and conversation history are additional.

| Scenario | Messages/Day | Without Caching | With Caching (1h) | Monthly Savings |
|----------|-------------|----------------|-------------------|----------------|
| **Light** | 10 | ~$31.50/mo | ~$9/mo | **~$22 (71%)** |
| **Moderate** | 30 | ~$94.50/mo | ~$15/mo | **~$79 (84%)** |
| **Heavy** | 50 | ~$157.50/mo | ~$22/mo | **~$136 (86%)** |

*Calculation: 35K tokens × $3/MTok = $0.105/message uncached. Cached column assumes 1-hour TTL with ~1 cache write per day ($6/MTok) and the rest as cache reads ($0.30/MTok) — realistic with the heartbeat keeping caches warm. Higher message volumes amortize the daily write cost better, hence improving savings percentages.*

### 5.3 Multi-Provider Caching Conflict

Caching is **provider-specific and model-specific.** Routing different messages to different providers destroys caching for all of them.

| Strategy | Caching Effectiveness |
|----------|---------------------|
| Single provider (Anthropic only) | Maximum -- every message builds on cached prefix |
| Primary + fallback (Anthropic -> OpenAI) | Good -- caching works unless failover triggers |
| Auto-routing (OpenRouter/ClawRouter) | Poor -- frequent provider switches invalidate caches |
| Manual model switching within same provider | Good -- switching Sonnet <-> Haiku preserves Anthropic cache |

**The fundamental tradeoff:** Prompt caching (71-86% savings on input, depending on session patterns) conflicts with multi-provider routing (50-90% on individual requests). For personal deployments, **caching wins** because it applies to every single message, while routing savings only apply to the subset that could use a cheaper model.

---

## 6. Monthly Cost Projections

> **Usage calibration:** Projections use ~15 conversational messages/day, which produces the ~$50/mo baseline measured on this setup. Scale linearly for different volumes -- at 30 msgs/day, double the input costs; at 5 msgs/day, cut them by two-thirds. Percentage savings from caching and tiering are consistent across volumes.

### 6.1 Baseline: Current Setup (Sonnet primary, Haiku cron, no caching)

| Component | Volume | Model | Monthly Cost (est.) |
|-----------|--------|-------|-------------------|
| Conversation | ~15/day | Sonnet 4.6 | ~$47 input + ~$2 output = **~$49** |
| Cron (Lattice) | 5/day | Haiku 4.5 | ~$5.25 input + ~$0.25 output = **~$5.50** |
| **Total** | | | **~$55/mo** |

*Input dominates: 35K bootstrap tokens × $3/MTok = $0.105/message. Output at ~300 tokens/message is comparatively small.*

### 6.2 With Prompt Caching Enabled

| Component | Volume | Model | Monthly Cost (est.) |
|-----------|--------|-------|-------------------|
| Conversation | ~15/day | Sonnet (cached, 1h) | ~$10 input + ~$2 output = **~$12** |
| Cron + heartbeat | 5+24/day | Haiku (cached) | ~$3 input + ~$0.25 output = **~$3.25** |
| **Total** | | | **~$15/mo** |

**Savings: ~$40/mo (73%) from one config change.** Cached input: ~80% savings on Sonnet (session starts are cache writes at 2× base; intra-session messages are reads at 10%). Heartbeat keeps Haiku cache warm for cron.

### 6.3 With Caching + Model Tiering

Using Haiku for simple messages (~50% of traffic), Sonnet for complex:

| Component | Volume | Model | Monthly Cost (est.) |
|-----------|--------|-------|-------------------|
| Complex conversation | ~8/day | Sonnet (cached) | ~$7 |
| Simple conversation | ~7/day | Haiku (cached) | ~$1.50 |
| Cron + heartbeat | 5+24/day | Haiku (cached) | ~$3.25 |
| **Total** | | | **~$12/mo** |

*Tiering adds modest savings on top of caching because cache reads are already cheap. The bigger tiering win is on output tokens: Haiku at $5/MTok vs Sonnet at $15/MTok.*

### 6.4 Budget-Optimized (Gemini Flash primary)

| Component | Volume | Model | Monthly Cost (est.) |
|-----------|--------|-------|-------------------|
| Conversation | ~15/day | Gemini 2.5 Flash | ~$3 input + ~$0.35 output = **~$3.50** |
| Cron + heartbeat | 5+24/day | Haiku (cached) | ~$3.25 |
| **Total** | | | **~$7/mo** |

*Tradeoff: Gemini Flash is cheaper but Claude Sonnet provides better tool use and instruction following for bot workloads. Google's cache has per-hour storage fees that make it less cost-effective for sporadic usage.*

---

## 7. Recommendations for This Setup

**Hardware:** 24GB RAM, 8-core CPU, no GPU
**Current config:** Anthropic primary (Sonnet), Haiku for cron
**Current spend:** ~$50/mo baseline
**Philosophy:** Maximum capability, minimum attack surface

### Recommendation 1: Enable Prompt Caching (Do This First)

The single highest-impact change. One config line, ~73% cost reduction.

```bash
ssh vps
export PATH="$HOME/.npm-global/bin:$PATH"
openclaw config set agents.defaults.models.anthropic/claude-sonnet-4.params.cacheRetention long
```

See [CONTEXT-ENGINEERING.md](CONTEXT-ENGINEERING.md) for implementation details and the known cache-read-always-0 bug (OpenClaw issue #19534).

### Recommendation 2: Configure Fallback Chain

Add resilience without adding attack surface:

```bash
openclaw models fallbacks add anthropic/claude-haiku-4-5
openclaw models fallbacks add google/gemini-2.5-flash
```

Haiku first (same provider, same personality DNA), then Gemini Flash as a cross-provider hedge. Only activates during Anthropic outages/rate limits. No cost impact under normal operation.

### Recommendation 3: Set Up Model Aliases

```bash
openclaw models aliases add opus anthropic/claude-opus-4-6
openclaw models aliases add sonnet anthropic/claude-sonnet-4-6
openclaw models aliases add haiku anthropic/claude-haiku-4-5
openclaw models aliases add flash google/gemini-2.5-flash
```

Then switch in Telegram: `/model opus` for hard problems, `/model sonnet` for daily use, `/model haiku` for simple tasks.

### Recommendation 4: Heartbeat for Cache Warming

```jsonc
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "55m",
        "model": "anthropic/claude-haiku-4-5"
      }
    }
  }
}
```

**Cache is model-specific.** A Haiku heartbeat keeps the Haiku cache warm (benefiting cron and Haiku conversations), but does NOT warm the Sonnet cache used by primary conversations. Sonnet cache warmth depends on the 1-hour TTL covering gaps between user messages.

**Why Haiku heartbeat is still the right default:** Haiku cache reads cost $0.10/MTok (~$2.50/mo for 24 heartbeats/day). This keeps cron (also Haiku) running on cache reads ($0.10/MTok) instead of cache writes ($2/MTok) -- saving ~$8/mo on cron alone. A Sonnet heartbeat ($0.30/MTok reads, ~$7.50/mo) would warm the Sonnet cache too, but the cost often exceeds the savings for light-to-moderate usage. Monitor your cache hit rates via ClawMetry before adding a Sonnet heartbeat.

### Recommendation 5: Adopt ClawRouter After Phase 1 Stabilization

ClawRouter's routing intelligence is genuinely impressive, and x402 micropayments are forward-looking infrastructure worth growing into. But it's not the right *first* optimization -- get caching and fallback chains stable first, then layer ClawRouter on top.

**Why not Phase 1:**
1. Multi-provider routing conflicts with prompt caching -- get caching ROI first
2. v0.9.x with rapid iteration means the install/config UX will improve quickly
3. `curl | bash` install requires manual audit step (download → read → run)

**Why Phase 2 (after caching + fallbacks are stable):**
1. **Resilience:** Adds intelligent multi-provider routing as a fallback layer beyond OpenClaw's native chain
2. **Cost savings at scale:** At ~$50/mo spend, ClawRouter's tier routing (55% SIMPLE → Haiku) saves real money
3. **Capability growth:** x402 wallet + blockchain interaction is infrastructure for an agent that can eventually pay for services, interact with smart contracts, and operate in the emerging agent economy
4. **Routing intelligence:** 15-dimension local scoring in <1ms is genuinely better than manual `/model` switching for diverse workloads

**Adoption path:** Caching → fallback chain → model aliases → ClawRouter (audit install script → configure tiers → fund wallet with $5-10 USDC → monitor savings via `/stats`)

### Recommendation 6: Skip Ollama (For Now)

- 7B models at 5-10 tok/sec can't match cloud response times for interactive Telegram use
- The cheapest cloud option (Gemini 2.0 Flash at $0.10/MTok) is likely cheaper than CPU time/electricity
- Adds operational complexity (model management, updates, RAM contention)

**Revisit when:** You need complete offline capability or privacy requirements prohibit any cloud provider.

---

## 8. Strategy Comparison Matrix

| Strategy | Monthly Cost (~$50 baseline) | Caching | Attack Surface | Quality | Complexity |
|----------|------------------------------|---------|---------------|---------|------------|
| **Sonnet only, no caching** | ~$55 | None | Minimal | Best | None |
| **Sonnet + caching** | ~$15 | Full | Minimal | Best | Low |
| **Sonnet/Haiku split + caching** | ~$12 | Full | Minimal | Good | Low |
| **Gemini Flash primary** | ~$7 | Partial | +1 provider | Good | Low |
| **OpenRouter auto-routing** | ~$16-25 | None | +1 gateway | Variable | Low |
| **ClawRouter (original)** | ~$10-16 | None | Moderate (equivalent to API keys) | Variable | Medium |
| **ClawRouter (fork)** | ~$10-16 | None | Low | Variable | Medium |
| **Ollama local** | ~$0 (electricity) | N/A | None | Limited | High |

**Recommended path:** Sonnet + caching (~$15/mo) → add Haiku for simple tasks (~$12/mo) → layer ClawRouter for intelligent routing + resilience → evaluate Ollama for offline/privacy needs.

---

## Sources

### Provider Pricing (verified February 2026)
- [Anthropic Pricing & Models](https://docs.anthropic.com/en/docs/about-claude/models)
- [Anthropic Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Anthropic Rate Limits](https://platform.claude.com/docs/en/api/rate-limits)
- [OpenAI Pricing](https://platform.openai.com/docs/pricing)
- [Google Gemini Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [DeepSeek Pricing](https://platform.deepseek.com/api-docs/pricing)
- [OpenRouter Docs](https://openrouter.ai/docs)
- [pricepertoken.com](https://pricepertoken.com) (pricing aggregator)

### ClawRouter
- [BlockRunAI/ClawRouter](https://github.com/BlockRunAI/ClawRouter) (original, 3,150 stars)
- [cgaeking/ClawRouter](https://github.com/cgaeking/ClawRouter) (crypto-free fork)
- [ClaHub Issue #125](https://github.com/openclaw/clawhub/issues/125) (provider plugin proposal)
- [x402 Protocol](https://www.x402.org) (Coinbase payment standard)

### OpenClaw Configuration
- [OpenClaw Model Docs](https://docs.openclaw.ai/concepts/models)
- [OpenClaw Model Failover](https://deepwiki.com/openclaw/openclaw/5.4-model-selection-and-failover)

### Routing
- [OpenRouter Auto-Router](https://openrouter.ai/docs/guides/routing/routers/auto-router)
- [NotDiamond](https://notdiamond.ai) (routing intelligence behind OpenRouter auto)
