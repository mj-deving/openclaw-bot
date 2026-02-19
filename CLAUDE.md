# CLAUDE.md — openclaw-bot

## What This Is

OpenClaw Telegram bot (Gregor) — deployment, configuration, security hardening

**Owner:** Marius Jonathan Jauernik
**GitHub:** [mj-deving/openclaw-bot](https://github.com/mj-deving/openclaw-bot)
**Created:** 2026-02-18

## Tech Stack

- **Runtime:** Bun + TypeScript (repo tooling); Node.js 22.x (OpenClaw itself)
- **Deployment:** VPS with systemd (maximum lockdown security posture)

## Conventions

- Commit messages: clear "why", prefixed by area when helpful
- Every session should end with a commit capturing the work done
- Code comments: thorough — document interfaces and logic
- File naming: kebab-case

## Session Workflow

1. Read this file on session start for project context
2. Do the work
3. Commit with a descriptive message at session end
4. Push to GitHub

## Project Structure

```
.
├── CLAUDE.md              # This file — project context for Isidore
├── CLAUDE.local.md        # Session continuity (auto-generated, gitignored)
├── README.md              # Public-facing project documentation
├── openclaw-vs-pai-comparison.md  # OpenClaw vs PAI deep comparison (fact-checked)
├── Plans/
│   ├── MASTERPLAN.md      # 10-phase deployment plan (fully corrected)
│   ├── MASTERPLAN-EXPLAINED.md  # Reasoning behind every decision
│   ├── RESEARCH-OFFICIAL-DOCS.md  # Official docs research findings
│   ├── IRC-REGISTRATION-GUIDE.md  # Libera.Chat registration steps
│   └── CLAWHUB-SKILLS-AND-GREGOR-ARCHITECTURE.md  # ClawHub ecosystem + Gregor design
├── src/                   # Source code (scripts, configs, systemd — TBD)
└── .sessions/             # Session docs (auto-generated)
```

## Key References

- **Official docs:** docs.openclaw.ai (NOT clawbot.ai — potentially fake)
- **Research source:** github.com/centminmod/explain-openclaw (199 files, third-party analysis)
- **Auth method:** Claude Max subscription via `setup-token` (API key fallback)

## Current State

**Status:** Phases 0-4 deployed and operational
**Bot:** @gregor_openclaw_bot (Telegram) | **VPS:** 213.199.32.18, Ubuntu 24.04.4 LTS
**OpenClaw:** v2026.2.17 | **Model:** claude-opus-4-6 | **Gateway:** 127.0.0.1:18789
**Permissions:** tools.profile "full", exec.ask off, deny [gateway, nodes, sessions_spawn, sessions_send]
**Pipeline:** ~/.openclaw/pipeline/ (inbox/outbox/ack) — async Isidore↔Gregor messaging
**Last session:** 2026-02-19
**Next steps:** Phase 5 (memory tuning), Phase 8 (backups), MASTERPLAN update
