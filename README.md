<p align="center">
  <img src="assets/social-preview.png" alt="openclaw-bot — Maximum capability, minimum attack surface" width="640">
</p>

<h3 align="center">The most thorough guide to deploying OpenClaw on your own server.</h3>

<p align="center">
  Security-first &bull; Any LLM provider &bull; Every decision explained
</p>

---

## What This Is

A deployment blueprint and operational tooling for running [OpenClaw](https://docs.openclaw.ai) on a self-hosted VPS — security-hardened, provider-agnostic, and documented well enough to audit. From blank Ubuntu server to production-ready AI agent.

## What You Get

- **[The Guide](GUIDE.md)** — 14-phase walkthrough from VPS hardening to context engineering, with reasoning behind every decision
- **Monitoring scripts** — Automated backup, health checks, update management, and gateway binding verification
- **Config template** — Annotated `openclaw.json` with security defaults and placeholder secrets
- **Reference docs** — Deep research on security, cost routing, identity design, skills architecture, memory, and more (in `Reference/`)

## Quick Start

```bash
# 1. Clone to your VPS
git clone https://github.com/mj-deving/openclaw-bot.git
cd openclaw-bot

# 2. Run the installer (previews changes first)
./install.sh --dry-run    # See what it will do
./install.sh              # Deploy config, scripts, cron jobs, logrotate

# 3. Follow the guide
# GUIDE.md walks you through everything — start at Phase 1
```

> **Prerequisites:** Ubuntu 22.04+ VPS, 2+ GB RAM, [OpenClaw](https://www.npmjs.com/package/openclaw) installed, a Telegram account, and an API key from any supported provider (or run local models with [Ollama](https://ollama.ai) for free).

## Requirements

The installer deploys operational tooling on top of an existing OpenClaw install. It does **not** install OpenClaw itself — that's `npm install -g openclaw`.

What the installer sets up:
- Config template → `~/.openclaw/openclaw.json` (never overwrites existing)
- Monitoring scripts → `~/scripts/`
- Cron jobs → backup (daily), health check (10min), auto-update (weekly), binding check (5min)
- Log rotation → `/etc/logrotate.d/openclaw` (requires sudo, skipped if unavailable)

Safe to re-run. Never overwrites existing files. Use `--dry-run` to preview.

## Links

- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **OpenClaw npm:** [npmjs.com/package/openclaw](https://www.npmjs.com/package/openclaw)
- **AI agents:** Point your agent at [AGENTS.md](AGENTS.md) for machine-readable project context
