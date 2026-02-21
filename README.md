# openclaw-bot

Deploy your own AI-powered Telegram bot on a VPS using [OpenClaw](https://docs.openclaw.ai) — an open-source AI agent that works with any LLM provider.

> *Maximum capability, minimum attack surface.*

## Quick Start

**Experienced users:** Follow the phases in order, skip the explanations.

**Beginners:** Every command is copy-pasteable. Every step has a checkpoint.

**[Read the full guide → GUIDE.md](GUIDE.md)**

### What you'll need

- A VPS (Ubuntu 22.04+, 2+ GB RAM)
- An API key from any supported provider (Anthropic, OpenAI, OpenRouter, and [20+ others](https://docs.openclaw.ai)) — or run local models with Ollama (free)
- A Telegram account

### What you'll get

A self-hosted AI agent on your own server — web search, shell access, persistent memory, scheduled automation — hardened and production-ready. Choose your own model and provider.

## Guide Structure

| Part | Phases | What it covers |
|------|--------|---------------|
| **1: Get It Running** | 1-6 | VPS hardening → Install → Auth → Telegram → First chat → Systemd |
| **2: Make It Solid** | 7-10 | OpenClaw security → Identity → Memory → Backups |
| **3: Make It Smart** | 11-14 | Skills → Cron automation → Cost optimization → Context engineering |
| **Appendices** | A-G | Architecture, pipeline, multi-bot, threat model, config reference |

## Repository Structure

```
├── GUIDE.md                      # The full setup guide — how AND why (start here)
├── Reference/
│   ├── CONTEXT-ENGINEERING.md    # Context management, caching & session persistence
│   └── MEMORY-PLUGIN-RESEARCH.md # mem0 evaluation + memory optimization research
├── src/
│   ├── config/
│   │   └── openclaw.json.example # Sanitized config template
│   └── scripts/
│       ├── backup.sh             # Daily backup script
│       ├── verify-binding.sh     # Gateway binding monitor
│       ├── health-check.sh       # Service health monitor
│       └── auto-update.sh        # Weekly update + security audit
```

## References

- **Guide:** [GUIDE.md](GUIDE.md) — complete setup instructions with reasoning behind every decision
- **Context engineering:** [Reference/CONTEXT-ENGINEERING.md](Reference/CONTEXT-ENGINEERING.md) — prompt caching, memory tuning, session persistence
- **Memory research:** [Reference/MEMORY-PLUGIN-RESEARCH.md](Reference/MEMORY-PLUGIN-RESEARCH.md) — why we use built-in memory over external plugins
- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **Security:** All configs verified against official schema. CVEs patched in v2026.1.29+.
