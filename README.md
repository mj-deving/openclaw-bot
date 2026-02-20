# openclaw-bot

Deploy your own AI-powered Telegram bot on a VPS, powered by Anthropic Claude via [OpenClaw](https://docs.openclaw.ai).

> *As capable as possible, while as secure as necessary.*

## Quick Start

**Experienced users:** Follow the phases in order, skip the explanations.

**Beginners:** Every command is copy-pasteable. Every step has a checkpoint.

**[Read the full guide → GUIDE.md](GUIDE.md)**

### What you'll need

- A VPS (Ubuntu 22.04+, 2+ GB RAM)
- An [Anthropic API key](https://console.anthropic.com)
- A Telegram account

### What you'll get

A Telegram bot running Claude on your own server — web search, shell access, persistent memory, scheduled posts — hardened and production-ready.

## Guide Structure

| Part | Phases | What it covers |
|------|--------|---------------|
| **1: Get It Running** | 1-6 | VPS hardening → Install → Auth → Telegram → First chat → Systemd |
| **2: Make It Solid** | 7-10 | OpenClaw security → Identity → Memory → Backups |
| **3: Make It Smart** | 11-13 | Skills → Cron automation → Cost optimization |
| **Appendices** | A-G | Architecture, pipeline, multi-bot, threat model, config reference |

## Repository Structure

```
├── GUIDE.md                      # The full setup guide (start here)
├── how-memory-works.md           # ELI5 guide to OpenClaw memory system
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

- **Guide:** [GUIDE.md](GUIDE.md)
- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **Security:** All configs verified against official schema. CVEs patched in v2026.1.29+.
