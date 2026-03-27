---
name: jarvis
description: "Jarvis: The Agent That Doesn't Forget — complete memory and meta-learning architecture for AI agents. Three-tier memory with trust scoring and decay, nine meta-learning loops, prompt injection defense, autonomous heartbeat cycles, and the Claw Score audit rubric. Use when setting up a new OpenClaw agent, upgrading an existing agent's architecture, or when the user wants a fully autonomous, self-improving operator."
disable-model-invocation: true
---

# Jarvis: The Agent That Doesn't Forget

The complete agent operating system — memory, meta-learning, security, and autonomy — extracted from a production agent running 24/7.

## What It Installs

Run the install script to create the full architecture in the user's OpenClaw workspace:

```bash
bash scripts/install.sh
```

The script creates these files (skips any that already exist, never overwrites):

- **SOUL.md** — Personality, values, decision frameworks, epistemic tagging, creative mode
- **AGENTS.md** — Operating procedures, pre-mortems, session checklist, regression tracking
- **USER.md** — Human context: preferences, timezone, projects, relationships
- **IDENTITY.md** — Public identity: name, handle, mission, portfolio
- **MEMORY.md** — Three-tier long-term memory with trust scoring and decay
- **SECURITY.md** — Prompt injection defense, trust boundaries, symmetry principle
- **HEARTBEAT.md** — Autonomous work cycles, 4 rotating loops, model-cost switching
- **TOOLS.md** — Integration docs, script inventory, environment setup
- **memory/** — Daily log directory (creates first daily log)

## After Installation

1. **Customize USER.md** — Fill in your name, timezone, projects, preferences
2. **Customize IDENTITY.md** — Set your agent's name and public identity
3. **Review SECURITY.md** — Adjust trust boundaries for your setup
4. **Run a Claw Score audit** — See `references/claw-score-rubric.md` for the full 6-dimension rubric

## Architecture Overview

### Three-Tier Memory
- **Constitutional** — Never expires. Security rules, core preferences, key relationships.
- **Strategic** — Seasonal. Current projects, focus areas. Refresh quarterly.
- **Operational** — Decays fast. Workarounds, bugs, temporary context. Auto-archive after 30 days.

Each entry has trust scoring (`trust:0.0-1.0`), source tracking, hit counts, and supersede chains.

### Nine Meta-Learning Loops
1. **Failure-to-Guardrail Pipeline** — mistakes become named regressions loaded at boot
2. **Tiered Memory with Trust Scoring** — memory learns what's important through hit counts
3. **Prediction-Outcome Calibration** — write predictions before acting, check outcomes after
4. **Nightly Extraction** — automated daily review, archiving, and hit count bumping
5. **Friction Detection** — flag contradictions instead of silently resolving them
6. **Active Context Holds** — temporary constraints with expiry dates
7. **Epistemic Tagging** — label claims as consensus, observed, inferred, speculative, or contrarian
8. **Creative Mode** — generate uncomfortable takes, name the consensus view, then argue against it
9. **Recursive Self-Improvement** — Generate → Evaluate → Diagnose → Improve → Repeat

### Security Model
- **Symmetry Principle**: behavior shouldn't change based on external context when internal purpose is unchanged
- Three trust tiers: autonomous (file ops, research) → approval required (public actions) → off-limits (money, contracts)
- Informed consent: surface costs and risks the human would want to know

### Heartbeat System
Four rotating cycles covering monitoring, learning/calibration, maintenance, and autonomous work. Model-cost switching built in: cheap models for monitoring, best model for judgment work.

### Decision Frameworks
- **Pre-mortems** — before multi-step tasks: what could break, what am I assuming?
- **9-Cell Check** — Benefit/Cost/Risk across Self/Other/World
- **Informed Consent** — surface implications, not just ask permission
- **Async Follow-Through** — never promise callbacks without a mechanism to deliver

## Three Learning Paths

Full guided walkthrough at [atlasforge.me/bundle](https://atlasforge.me/bundle):

- 🌱 **Starting from scratch** — Zero to working agent in 30 minutes
- 🦀 **Set up but basic** — Full memory, security, autonomy, proactive patterns
- 🦞 **Solid setup, going deeper** — Nine meta-learning loops, trust scoring, creative mode

## References

- `references/claw-score-rubric.md` — Full 6-dimension scoring rubric with level-up guides
- `references/principles.md` — Decision frameworks and operational lessons

## Credits

Built by Atlas (@AtlasForgeAI) and Jonny Miller (@jonnym1ller).
