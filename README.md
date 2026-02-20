# openclaw-bot

Community guide for deploying an OpenClaw-powered Telegram bot on a VPS, using Anthropic Claude as the AI provider.

## What This Is

A step-by-step deployment guide covering:

- VPS preparation and OS hardening
- OpenClaw installation and Anthropic authentication
- Telegram bot setup with device pairing
- Security hardening (capability-first posture)
- Memory system with local embeddings
- Systemd service with auto-recovery
- Monitoring, backups, and log hygiene
- ClawHub skill vetting (optional)

## Quick Start

1. Read `Plans/MASTERPLAN.md` — the complete setup guide
2. Follow phases 0-8 in order
3. Use `src/config/openclaw.json.example` as your config template
4. Deploy monitoring scripts from `src/scripts/`

## Repository Structure

```
├── Plans/
│   ├── MASTERPLAN.md              # Complete setup guide (start here)
│   ├── MASTERPLAN-EXPLAINED.md    # Reasoning behind key decisions
│   ├── RESEARCH-OFFICIAL-DOCS.md  # Official docs research findings
│   ├── CLAWHUB-SKILLS-AND-BOT-ARCHITECTURE.md  # ClawHub ecosystem & agent design
│   ├── TOKEN-OPTIMIZATION-RESEARCH.md  # Token cost analysis
│   └── SESSION-HISTORY.md         # Development journal
├── how-memory-works.md            # ELI5 guide to OpenClaw memory system
├── src/
│   ├── config/
│   │   └── openclaw.json.example  # Sanitized config template
│   └── scripts/
│       ├── backup.sh              # Daily backup script
│       ├── verify-binding.sh      # Gateway binding monitor
│       ├── health-check.sh        # Service health monitor
│       └── auto-update.sh         # Weekly update + security audit
```

## Philosophy

> *As capable as possible, while as secure as necessary.*

The bot runs with `tools.profile: "full"` and a targeted deny list — not blanket lockdown. Security protects capability, not replaces it.

## References

- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **Security:** All configs verified against official schema. Known CVEs patched in v2026.1.29+.
