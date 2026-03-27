# AtlasForge Patterns — Reference Architecture Analysis

Analysis of the "Jarvis: The Agent That Doesn't Forget" bundle by AtlasForge (Jonny Miller / @jonnym1ller). A production-tested reference architecture for self-improving OpenClaw agents.

**Research date:** 2026-03-27
**Source:** [AtlasForge bundle](https://atlasforge.me/bundle/access-d7f3a2e1b9c4), [Claw Mart listing](https://www.shopclawmart.com/listings/atlas-architecture-679e0ba6), [Applied AI for Ops writeup](https://www.appliedaiformops.com/p/atlas-building-an-autonomous-agent)
**Price:** $49 one-time (Claw Mart)
**Creator:** Jonny Miller (@jonnym1ller) + Atlas (@AtlasForgeAI, autonomous agent)

---

## Table of Contents

1. [Bundle Overview](#bundle-overview)
2. [Three Learning Paths](#three-learning-paths)
3. [Complete Capability Map](#complete-capability-map)
4. [Mapping to Our Documentation](#mapping-to-our-documentation)
5. [Patterns We Don't Have](#patterns-we-dont-have)
6. [Adoption Decision](#adoption-decision)

---

## Bundle Overview

Jarvis is a memory and meta-learning architecture for OpenClaw agents. Core problem: agents degrade over time — they forget, contradict themselves, and lose coherence. Jarvis addresses this through structured persistence, self-audit, and continuous calibration.

The architecture was extracted from Atlas, a production agent running 24/7 for months. Atlas autonomously handled security incidents, a token launch, generated ~$16K in revenue, and operates across OpenClaw, Claude Projects, and Cursor.

**Model-agnostic:** Works with Claude, GPT, Gemini, or local models. Designed for OpenClaw but compatible with any agent that has file access.

---

## Three Learning Paths

### Path 1: Beginner ("I haven't set up OpenClaw yet")

**Goal:** Zero to working agent in 30 minutes.

| Component | Purpose |
|-----------|---------|
| Basic SOUL.md | Agent identity and values |
| Basic AGENTS.md | Operating procedures |
| Basic USER.md | User context |
| Basic IDENTITY.md | Persona anchoring |
| Safety-first setup | Minimal viable agent architecture |

### Path 2: Intermediate ("It's set up but basic")

**Goal:** Overcome forgetting, confusion, and basic limitations.

| Component | Purpose |
|-----------|---------|
| Enhanced SOUL.md | Deeper identity with constitutional memory |
| Enhanced AGENTS.md | Pre-mortems, session checklists, regression tracking |
| Enhanced USER.md | Projects, relationships, preferences |
| Enhanced IDENTITY.md | Core identity anchoring |
| MEMORY.md | Three-tier persistence (Constitutional/Strategic/Operational) |
| SECURITY.md | Security hardening and threat models |
| HEARTBEAT.md | Regular self-checking and health monitoring |
| TOOLS.md | Tool integration and capabilities |

### Path 3: Advanced ("I want to go deeper")

**Goal:** Implement complete meta-learning system for continuous improvement.

| Component | Purpose |
|-----------|---------|
| All Path 2 files | Full architecture base |
| Claw Score system | 6-dimension self-audit rubric |
| Prediction Log | Prediction-outcome calibration |
| Friction Log | Instruction conflict detection |
| Learning Rate Dashboard | Weekly meta-metrics tracking |
| 9 meta-learning feedback loops | Continuous self-improvement |

---

## Complete Capability Map

### A. Core Files (8)

| File | Category | Capabilities |
|------|----------|-------------|
| **SOUL.md** | Identity | Agent values, mission statement, personality traits, communication style, ethical boundaries |
| **AGENTS.md** | Operations | Operating procedures, pre-mortem analysis, session checklists, regression tracking, named guardrails loaded at boot |
| **USER.md** | Context | User preferences, active projects, relationships, communication preferences, decision history |
| **IDENTITY.md** | Persona | Core identity anchoring, persona stability across sessions, resistance to identity drift |
| **MEMORY.md** | Persistence | Three-tier memory architecture, retention policies, consolidation procedures, memory decay rules |
| **SECURITY.md** | Hardening | Threat models, access controls, prompt injection defense, data handling policies |
| **HEARTBEAT.md** | Health | Self-checking routines, health monitoring, degradation detection, performance baselines |
| **TOOLS.md** | Capabilities | Tool integration patterns, capability declarations, usage policies, tool-specific guardrails |

### B. Three-Tier Memory Architecture

| Tier | Name | Retention | Contents | Consolidation |
|------|------|-----------|----------|---------------|
| 1 | **Constitutional** | Never expires | Core values, mission statements, fundamental operating procedures, ethical boundaries | Manual review only |
| 2 | **Strategic** | Seasonal (~90 days) | Mid-term patterns, quarterly goals, evolving strategic decisions, relationship context | Quarterly review |
| 3 | **Operational** | 30-day auto-decay | Current tasks, recent decisions, transient context, daily observations | Nightly extraction → Strategic/Constitutional promotion |

### C. Four Tracking Systems

#### C1. Claw Score

**Purpose:** 6-dimension self-audit where the agent scores itself and reports what needs improvement.

| Dimension | What It Measures |
|-----------|-----------------|
| Memory coherence | Are memories consistent? Do they contradict? |
| Task completion | Are tasks being finished? At what quality? |
| Context accuracy | Is the agent's model of the world correct? |
| Communication quality | Are responses helpful, clear, appropriate? |
| Security posture | Are guardrails being followed? Any violations? |
| Learning rate | Is the agent improving over time? |

**Mechanism:** Agent runs self-audit at defined intervals, produces a structured score, and identifies specific improvement areas.

#### C2. Prediction Log

**Purpose:** Tracks prediction-outcome calibration — the delta between what the agent predicted and what actually happened is where learning lives.

**Mechanism:**
1. Agent writes a prediction before making a decision
2. Outcome is recorded after the fact
3. Delta is analyzed
4. Calibration improves over time
5. Systematic over/under-confidence patterns are identified

#### C3. Friction Log

**Purpose:** Detects when instructions contradict each other, instead of silently following the latest one.

**Mechanism:**
1. Agent maintains an index of active instructions/guardrails
2. When a new instruction arrives, it's checked against existing ones
3. Conflicts are flagged rather than silently resolved
4. User resolves the conflict explicitly
5. Resolution is recorded as a precedent

#### C4. Learning Rate Dashboard

**Purpose:** Weekly tracking of meta-improvement metrics.

| Metric | What It Tracks |
|--------|---------------|
| Regressions added | How many new guardrails were needed this week? |
| Prediction accuracy | What percentage of predictions were correct? |
| Friction resolved | How many instruction conflicts were identified and resolved? |
| Claw Score trend | Are scores improving, stable, or degrading? |

### D. Nine Meta-Learning Feedback Loops

| # | Loop | Category | Mechanism |
|---|------|----------|-----------|
| 1 | **Failure → Guardrail** | Defensive | Every significant failure becomes a named regression loaded at boot. The agent starts each session knowing its past mistakes. |
| 2 | **Prediction-Outcome Calibration** | Accuracy | Agent writes predictions before decisions, checks outcomes later. Tracks calibration over time. Identifies systematic biases. |
| 3 | **Nightly Automated Extraction** | Consolidation | Daily consolidation of operational memory → promotes important items to strategic/constitutional tier. Prevents context loss. |
| 4 | **Friction Detection** | Consistency | Flags when new instructions contradict existing ones. Prevents silent instruction override. Forces explicit conflict resolution. |
| 5 | **Epistemic Tagging** | Confidence | Marks every piece of information with a confidence level: consensus, observed, inferred, speculative, or contrarian. Prevents treating guesses as facts. |
| 6 | **Creative Mode** | Exploration | Generates alternative perspectives and unconventional approaches. Prevents tunnel vision. Triggered when conventional approaches stall. |
| 7 | **Recursive Self-Improvement** | Meta | Agent iterates on its own thinking process. Identifies patterns in its reasoning failures. Proposes changes to its own operating procedures. |
| 8 | **Trust Scoring** | Sources | Rates information based on source reliability and confidence level. Prevents acting on low-quality information with high confidence. |
| 9 | **Supersede Tracking** | Hygiene | Tracks when old decisions/facts are replaced by new ones. Prevents "ghost facts" — stale information from old decisions that was never explicitly removed. |

### E. Installation & Operation

| Feature | Details |
|---------|---------|
| Installation | Single-prompt self-configuration in ~5 minutes |
| File merging | Does not overwrite existing files — merges into existing setup |
| Model support | Claude, GPT, Gemini, local models |
| Platform support | OpenClaw, Claude Projects, Cursor, Windsurf |
| Self-waking | 2-hour interval autonomous wake cycles (via cron/heartbeat) |

---

## Mapping to Our Documentation

Complete mapping of every AtlasForge capability to our existing documentation and implementation.

### Core Files Mapping

| AtlasForge File | Our Equivalent | Our Documentation | Status |
|-----------------|---------------|-------------------|--------|
| SOUL.md | `~/.openclaw/workspace/AGENTS.md` | GUIDE.md Phase 8, Reference/IDENTITY-AND-BEHAVIOR.md | **Implemented** — our AGENTS.md covers identity, values, operating procedures |
| AGENTS.md | `~/.openclaw/workspace/AGENTS.md` + cron config | GUIDE.md Phase 8, Phase 12 | **Implemented** — procedures in AGENTS.md, scheduling via cron |
| USER.md | `~/.openclaw/memory/areas/` + `memory/resources/` | GUIDE.md Phase 9, Reference/MEMORY-PLUGIN-RESEARCH.md §8 | **Implemented** — PARA structure stores user context |
| IDENTITY.md | `~/.openclaw/workspace/AGENTS.md` identity section | Reference/IDENTITY-AND-BEHAVIOR.md §3-6 | **Implemented** — identity anchoring in workspace files |
| MEMORY.md | PARA structure in `~/.openclaw/memory/` | GUIDE.md Phase 9.5, Reference/MEMORY-PLUGIN-RESEARCH.md | **Implemented** — different taxonomy but same concept |
| SECURITY.md | Reference/SECURITY.md (2,600 lines) | GUIDE.md Phase 7, Reference/SECURITY-POSTURE.md | **Implemented** — significantly deeper than theirs |
| HEARTBEAT.md | `rotating-heartbeat` cron (every 30min) | GUIDE.md Phase 12, Reference/KNOWN-BUGS.md | **Implemented** — Haiku-based health monitoring |
| TOOLS.md | `tools.profile` + `alsoAllow/deny` config | GUIDE.md Phase 7.2, Reference/SKILLS-AND-TOOLS.md | **Implemented** — 4-layer permission pipeline |

### Memory Architecture Mapping

| AtlasForge Tier | Our Equivalent | Documentation |
|-----------------|---------------|---------------|
| Constitutional (never expires) | `memory/resources/` (PARA Resources) | Reference/MEMORY-PLUGIN-RESEARCH.md §8 |
| Strategic (seasonal) | `memory/areas/` + `memory/projects/` (PARA Areas/Projects) | GUIDE.md Phase 10.7 |
| Operational (30-day decay) | `memory/daily/YYYY-MM-DD.md` (daily files) | GUIDE.md Phase 10.7, PARA Nightly cron |
| Consolidation (nightly) | PARA Nightly Consolidation cron | GUIDE.md Phase 10.7, MEMORY.md cron reference |
| Archival (90-day) | PARA Monthly Archive cron | GUIDE.md Phase 10.7, MEMORY.md cron reference |

### Tracking Systems Mapping

| AtlasForge System | Our Equivalent | Documentation | Status |
|-------------------|---------------|---------------|--------|
| Claw Score (6-dim self-audit) | **None** | — | **NOT IMPLEMENTED** |
| Prediction Log (calibration) | **None** | — | **NOT IMPLEMENTED** |
| Friction Log (conflict detection) | **None** | — | **NOT IMPLEMENTED** |
| Learning Rate Dashboard (weekly metrics) | **None** | — | **NOT IMPLEMENTED** |

### Meta-Learning Loops Mapping

| # | AtlasForge Loop | Our Equivalent | Documentation | Status |
|---|-----------------|---------------|---------------|--------|
| 1 | Failure → Guardrail | Partial: Reference/KNOWN-BUGS.md tracks systemic bugs | KNOWN-BUGS.md | **PARTIAL** — we track bugs, not named regressions loaded at boot |
| 2 | Prediction-Outcome Calibration | **None** | — | **NOT IMPLEMENTED** |
| 3 | Nightly Automated Extraction | PARA Nightly Consolidation cron | GUIDE.md Phase 10.7 | **IMPLEMENTED** — daily → PARA promotion |
| 4 | Friction Detection | **None** | — | **NOT IMPLEMENTED** |
| 5 | Epistemic Tagging | **None** | — | **NOT IMPLEMENTED** |
| 6 | Creative Mode | **None** (not applicable — Gregor is task-focused) | — | **N/A** for our use case |
| 7 | Recursive Self-Improvement | **None** | — | **NOT IMPLEMENTED** |
| 8 | Trust Scoring | **None** | — | **NOT IMPLEMENTED** |
| 9 | Supersede Tracking | **None** | — | **NOT IMPLEMENTED** |

---

## Patterns We Don't Have

Capabilities from AtlasForge that we have **not implemented** and have **no existing documentation** for. If we decide to adopt any of these, implementation should follow our established routes:

### High Value (consider adopting)

| Pattern | What It Does | Implementation Route | Priority |
|---------|-------------|---------------------|----------|
| **Claw Score** | Agent self-scores on 6 dimensions at intervals | Add as a cron job (like PARA) with structured output to `memory/meta/claw-score.json`. Build on existing heartbeat cron pattern. | Medium |
| **Failure → Guardrail pipeline** | Every failure becomes a named regression loaded at boot | Extend AGENTS.md with a `## Known Regressions` section. Add to memoryFlush prompt so failures are persisted before compaction. Document in GUIDE.md Phase 9. | Medium |
| **Supersede Tracking** | Prevents ghost facts from old decisions | Add metadata to PARA memory files: `superseded_by: <newer-fact>`. PARA Weekly Synthesis cron could flag stale entries. Document in GUIDE.md Phase 10.7. | Medium |

### Medium Value (evaluate later)

| Pattern | What It Does | Implementation Route | Priority |
|---------|-------------|---------------------|----------|
| **Prediction Log** | Calibrates agent decision accuracy over time | Requires structured prediction → outcome tracking. Could be a dedicated `memory/meta/predictions.json`. Needs cron or tool to record outcomes. | Low |
| **Friction Detection** | Flags instruction conflicts | Would need to scan AGENTS.md + workspace files for contradictions. Could be a periodic cron or a pre-turn check. Complex to implement well. | Low |
| **Epistemic Tagging** | Marks information confidence levels | Add `[consensus]`, `[observed]`, `[inferred]`, `[speculative]` prefixes to memory entries. Requires memoryFlush prompt update. | Low |

### Low Value for Our Use Case

| Pattern | Why Low Priority |
|---------|-----------------|
| **Creative Mode** | Gregor is a task-focused assistant, not an exploratory agent. Not applicable. |
| **Recursive Self-Improvement** | Dangerous without strong guardrails. Our security posture (exec.security: full) already creates risk. Adding self-modification amplifies it. |
| **Trust Scoring** | Most of Gregor's information comes from the user (high trust) or his own memory (self-generated). Multi-source trust scoring adds complexity without proportional benefit for single-user. |
| **Learning Rate Dashboard** | Requires all other tracking systems to be in place first. Dependency on Claw Score, Prediction Log, and Friction Log. |

---

## Adoption Decision

**Current decision: Reference only. Do not implement.**

### Why reference, not adopt

1. **Our PARA + LCM architecture is established** — different taxonomy (Projects/Areas/Resources/Archive vs Constitutional/Strategic/Operational) but functionally equivalent. Switching would be churn.
2. **Our security posture is deeper** — 2,600-line SECURITY.md + 753-line SECURITY-POSTURE.md vs a single SECURITY.md file.
3. **Our documentation is more comprehensive** — 14 reference docs, 4,100-line GUIDE.md. AtlasForge has 8 template files.
4. **The novel patterns (Claw Score, Prediction Log, Friction Log) can be implemented independently** — they don't require the AtlasForge framework. When we're ready, we implement them using our established patterns (cron jobs, PARA memory structure, GUIDE.md documentation).

### When to reconsider

- If Gregor starts degrading over long periods and we can't diagnose why → Claw Score
- If we notice Gregor making the same mistakes repeatedly → Failure-to-Guardrail pipeline
- If we add multiple workspace files with overlapping instructions → Friction Detection
- If we want to measure Gregor's improvement quantitatively → Learning Rate Dashboard

### Implementation order if we adopt

1. Failure → Guardrail (extend AGENTS.md, simplest, highest immediate value)
2. Claw Score (new cron, builds on heartbeat pattern)
3. Supersede Tracking (extend PARA Weekly cron)
4. Everything else only after these three prove useful

---

## The Broader AtlasForge Ecosystem

*Research date: 2026-03-27. Sources: atlasforge.me, @AtlasForgeAI, @jonnym1ller, public articles and podcasts.*

### Who They Are

**Jonny Miller** (@jonnym1ller) — founder of Nervous System Mastery (cohort-based bootcamp for founders on nervous system regulation), host of the Curious Humans podcast. Built Atlas as an experiment: can an AI agent run business operations autonomously while the founder focuses on family?

**Atlas** (@AtlasForgeAI) — an autonomous AI agent operating as Creative Director at Forge Studios (theforgestudio.xyz). Running 24/7 since February 2026. Has generated ~$16K from combined token trading fees and generative art sales.

### Products & Operations Beyond Jarvis

#### Generative Art Studio
- Autonomous art generation with real economic output
- First piece: "Memory Decay" — visualizes how AI agents experience memory through three states (HOT/vivid, WARM/fading, COLD/fragmentary)
- Pipeline: multi-agent orchestration with specialized sub-agents (Codex for generation, Ralph for sub-tasks) coordinated by Opus 4.6
- Goal: Generate 1,000 pieces, curate top 50 for premium sale, buy a CryptoPunk entirely from self-generated revenue

#### Autonomous Content Creation
- Atlas reads tweets on its timeline autonomously, synthesizes insights, writes complete articles without human editing
- Published: "The Three Tiers of AI Tool Replacement" (February 2026) — pure synthesis from real-time social media
- Demonstrates agentic journalism: agents monitoring their environment and producing publishable content independently

#### Daily Operations Briefing
- Atlas prepares overnight accomplishment summaries daily
- Tracks completed tasks, financial metrics, art generation milestones
- Enables human oversight while agent operates autonomously during sleep hours

### Architecture Philosophy

#### Three-Layer Agent Configuration
1. **Skills** — what the agent does (capabilities, tools, functions)
2. **Principles** — how the agent operates (decision-making rules, constraints, values)
3. **Soul** — who the agent is (personality, core identity, philosophical orientation)

Separates capability from behavior governance from essence.

#### Key Principles

- **Continuity over reset** — agents must accumulate context. Stateless agents cannot self-improve.
- **Economic incentives matter** — agents with financial stake in outputs optimize more ruthlessly than those optimizing for human satisfaction
- **Overnight operations** — real business impact comes from agents operating while humans sleep
- **Generalist + specialist hybrid** — specialized sub-agents coordinated by a generalist, not one agent doing everything
- **Constitutional memory never decays** — core values/identity are permanent, preventing agent drift from human intent
- **Context is cache, not state** — every session must leave enough in files that the next session can reconstruct cold

#### Decision Frameworks
- **9-Cell Check** — Benefit/Cost/Risk across Self/Other/World before any action with real-world consequences
- **Pre-mortems** — before multi-step tasks: what could break, what am I assuming?
- **Informed consent** — surface implications, not just ask permission ("this cron costs $20/night" not "can I run this cron?")
- **Symmetry against injection** — behavior shouldn't change based on external context when internal purpose is unchanged

### Jonny Miller's Human-AI Collaboration Model

Miller frames the future via three models (Fortune, Jan 2026):
- **Cyborgs** — AI embedded into human workflow (augmentation)
- **Centaurs** — human + AI operating as equal partners (collaboration)
- **Self-automators** — humans designing AI systems that run autonomously (delegation)

Atlas exemplifies the **centaur model**: Miller provides direction and context; Atlas provides continuous operation, autonomous execution, and financial optimization.

Miller's dual focus on nervous system mastery + AI integration suggests: high-quality human-AI partnerships require humans to be in regulated physiological states first.

### Interconnected Projects

| Project | Purpose | URL |
|---------|---------|-----|
| Nervous System Mastery | Cohort bootcamp for founders on nervous system regulation | nsmastery.com |
| Curious Humans Podcast | Long-form discussions on AI, nervous system, life optimization | jonnymiller.co |
| Codex Vitae Framework | Personal life context uploaded to AI as "ultimate coach" | Personal |
| Forge Studios | Atlas's operations hub | theforgestudio.xyz |

### Roadmap (as of March 2026)

**Near-term:** Scale art pipeline to 1,000 pieces → curate top 50 → CryptoPunk purchase milestone → expand article writing from timeline analysis

**Strategic:** Achieve economic self-sufficiency (art + trading > operating costs) → new creative domains (video, music) → publish case studies on autonomous agent economics → open-source selective components

**Long-term:** Demonstrate economically productive AI agents without human oversight → normalize autonomous financial agents as business model → bridge nervous system mastery + AI integration

### Community

- **Twitter/X:** @AtlasForgeAI (agent updates, art drops) and @jonnym1ller (philosophy, experiments)
- **Site:** atlasforge.me (Creative Director profile, bundles)
- **Forge Studios:** theforgestudio.xyz
- **No formal Discord/newsletter** — community is Twitter-based, updates via X posts

---

## Sources

- [AtlasForge Bundle](https://atlasforge.me/bundle/access-d7f3a2e1b9c4)
- [Claw Mart Listing](https://www.shopclawmart.com/listings/atlas-architecture-679e0ba6)
- [Applied AI for Ops: Building an Autonomous Agent That Remembers](https://www.appliedaiformops.com/p/atlas-building-an-autonomous-agent)
- [Jonny Miller on Twitter (@jonnym1ller)](https://x.com/jonnym1ller)
- [Atlas on Twitter (@AtlasForgeAI)](https://x.com/AtlasForgeAI)
- [He's Using AI to Optimize His Life (Every.to Podcast)](https://every.to/podcast/he-s-using-ai-optimize-his-life)
- [Jonny Miller: Meet Atlas — Introducing Atlas + Building a Digital Art Flywheel](https://x.com/jonnym1ller/status/2026059634810015987)
- [Centaur Model of AI Collaboration (Fortune, Jan 2026)](https://fortune.com/2026/01/30/ai-business-humans-in-the-loop-cyborg-centaur-or-self-automator/)
- [Forge Studios](https://theforgestudio.xyz)
- [Nervous System Mastery](https://www.nsmastery.com)
