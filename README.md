# OpenClaw Deployment Guide

A practitioner's reference for deploying [OpenClaw](https://docs.openclaw.ai) on your own server — streamlined setup, security-first defaults, and the reasoning behind every decision.

> *Maximum capability, minimum attack surface.*

## Why This Exists

The official OpenClaw docs explain features well. What doesn't exist is a single resource that covers **end-to-end secure deployment** — from a blank Ubuntu server to a hardened, production-ready AI agent — while explaining *why* each choice was made.

This guide fills that gap:

- **Streamlined with reasoning.** Not just the commands — the *why* behind every decision. Why these permissions? Why this auth method? Why deny these tools? Look for the indented "Why?" blocks throughout.
- **Security as a first-class concern.** SSH hardening, 4-layer permission pipeline, skill supply chain vetting, threat model appendix. Security protects capability — it doesn't prevent it.
- **Provider-agnostic.** Anthropic, OpenAI, OpenRouter, Ollama (free local models), and 20+ others. Choose your model, choose your provider, change your mind later.

## A Living Repository

This isn't a static tutorial that decays after publishing. It's updated whenever new insights emerge — deployment learnings, configuration recommendations, utility hacks, cost optimizations, security discoveries. The reference docs capture deep research that informed real decisions on a production bot.

If you're deploying OpenClaw seriously, bookmark it. It'll be different (and better) next time you check.

## What You'll Build

A self-hosted AI agent on your own VPS — web search, shell access, persistent memory, scheduled automation, hardened permissions. You own the server, you own the data.

We start with Telegram as the interface because it's the fastest path to a working bot. But OpenClaw supports multiple channels — WhatsApp, Discord, iMessage, Slack, and more — and the security model, memory configuration, skill architecture, and cost patterns you'll learn here transfer to any of them.

"Production-ready" means: systemd service management, automated backups, health monitoring, log rotation, and a security posture you can reason about.

Every command is copy-pasteable. Every step has a checkpoint. Or point your AI agent at [AGENTS.md](AGENTS.md) and let it drive.

## What You'll Need

- A VPS (Ubuntu 22.04+, 2+ GB RAM)
- An API key from any supported provider — or run local models with [Ollama](https://ollama.ai) (free)
- A Telegram account

## The Guide

14 phases across three parts, plus appendices:

| Part | Phases | What It Covers |
|------|--------|---------------|
| **Get It Running** | 1-6 | VPS hardening, install, auth, Telegram, first chat, systemd |
| **Make It Solid** | 7-10 | OpenClaw security, identity, memory, backups & monitoring |
| **Make It Smart** | 11-14 | Skills, cron automation, cost optimization, context engineering |
| **Appendices** | A-G | Architecture, pipeline, multi-bot, threat model, config reference |

**[Read the guide &rarr; GUIDE.md](GUIDE.md)**

## Repository Map

```
GUIDE.md                          # The deployment guide (2,000 lines)
AGENTS.md                         # Machine-readable project context for AI agents
Reference/
  CONTEXT-ENGINEERING.md          # Prompt caching, session persistence, memory tuning
  COST-AND-ROUTING.md             # Provider pricing, model routing, ClawRouter analysis
  MEMORY-PLUGIN-RESEARCH.md       # Why built-in memory over external plugins (mem0 eval)
  SKILLS-AND-TOOLS.md             # Skill architecture, tool permissions, supply chain security
  IDENTITY-AND-BEHAVIOR.md        # System prompt design, persona patterns, identity-layer security
src/
  config/
    openclaw.json.example         # Sanitized config template with security annotations
    logrotate-openclaw            # Log rotation config
  scripts/
    backup.sh                     # Daily backup with 30-day retention
    health-check.sh               # Service health monitor
    verify-binding.sh             # Gateway binding verification
    auto-update.sh                # Weekly update + security audit
  pipeline/
    send.sh / read.sh / status.sh # Async messaging pipeline utilities
```

## References

- **Guide:** [GUIDE.md](GUIDE.md) — complete setup instructions with reasoning behind every decision
- **Context engineering:** [Reference/CONTEXT-ENGINEERING.md](Reference/CONTEXT-ENGINEERING.md) — prompt caching, memory tuning, session persistence
- **Cost & routing:** [Reference/COST-AND-ROUTING.md](Reference/COST-AND-ROUTING.md) — provider pricing, model routing strategies, ClawRouter deep dive
- **Memory research:** [Reference/MEMORY-PLUGIN-RESEARCH.md](Reference/MEMORY-PLUGIN-RESEARCH.md) — why we use built-in memory over external plugins
- **Skills & tools:** [Reference/SKILLS-AND-TOOLS.md](Reference/SKILLS-AND-TOOLS.md) — skill creation, tool permissions, security vetting, supply chain risks
- **Identity & behavior:** [Reference/IDENTITY-AND-BEHAVIOR.md](Reference/IDENTITY-AND-BEHAVIOR.md) — system prompt design, persona patterns, Telegram constraints, identity-layer security
- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
