# Agent Context — openclaw-bot

> Machine-readable project metadata for AI agents. Humans: see [README.md](README.md).

## Purpose

This repository contains the most thorough guide to deploying OpenClaw on a self-hosted VPS. It covers security-hardened setup, provider-agnostic configuration, memory tuning, skill architecture, cost optimization, and production operations. The guide explains the reasoning behind every decision, not just the steps.

## Start Here

1. **[README.md](README.md)** — Project overview, audience, and navigation
2. **[GUIDE.md](GUIDE.md)** — The full deployment guide (14 phases, 2,700 lines)
3. **Reference docs** — Deep dives on specific topics (see File Index below)

## File Index

| File | Format | Lines | Purpose | Relevance |
|------|--------|-------|---------|-----------|
| `README.md` | Markdown | ~85 | Project overview, audience, navigation | [essential] |
| `GUIDE.md` | Markdown | 2,700 | Full deployment guide — 14 phases + 8 appendices | [essential] |
| `AGENTS.md` | Markdown | ~80 | This file — machine-readable project context | [essential] |
| `Reference/SECURITY.md` | Markdown | 2,600 | VPS/OS hardening, application/LLM security (55 sources) | [reference] |
| `Reference/COST-AND-ROUTING.md` | Markdown | 580 | LLM cost optimization, model routing, provider strategy | [reference] |
| `Reference/IDENTITY-AND-BEHAVIOR.md` | Markdown | 590 | System prompt design, persona patterns, identity security | [reference] |
| `Reference/SKILLS-AND-TOOLS.md` | Markdown | 570 | Skill architecture, tool permissions, supply chain security | [reference] |
| `Reference/MEMORY-PLUGIN-RESEARCH.md` | Markdown | 400 | mem0 evaluation, built-in memory optimization | [reference] |
| `Reference/CONTEXT-ENGINEERING.md` | Markdown | 245 | Prompt caching, session persistence, memory tuning | [reference] |
| `Reference/SECURITY-PATCHES.md` | Markdown | 107 | Version-specific security patches and action status | [reference] |
| `Reference/UPGRADE-NOTES.md` | Markdown | 480 | Changelog across OpenClaw releases with deployment impact | [reference] |
| `Reference/PAI-PIPELINE.md` | Markdown | 280 | Cross-agent pipeline: Gregor ↔ Isidore Cloud architecture | [reference] |
| `src/config/openclaw.json.example` | JSON | 93 | Sanitized config template with security annotations | [config] |
| `src/config/logrotate-openclaw` | Config | 15 | Log rotation configuration | [utility] |
| `src/scripts/backup.sh` | Bash | 49 | Daily backup with 30-day retention | [utility] |
| `src/scripts/health-check.sh` | Bash | 83 | Service health monitoring | [utility] |
| `src/scripts/verify-binding.sh` | Bash | 38 | Gateway binding verification | [utility] |
| `src/scripts/auto-update.sh` | Bash | 66 | Weekly update + security audit | [utility] |
| `src/pipeline/send.sh` | Bash | 40 | Pipeline: send message to bot | [utility] |
| `src/pipeline/read.sh` | Bash | 43 | Pipeline: read bot responses | [utility] |
| `src/pipeline/status.sh` | Bash | 30 | Pipeline: check pipeline status | [utility] |
| `src/pai-pipeline/pai-submit.sh` | Bash | 109 | PAI pipeline: submit task to Isidore Cloud | [utility] |
| `src/pai-pipeline/pai-result.sh` | Bash | 179 | PAI pipeline: read results with wait/ack modes | [utility] |
| `src/pai-pipeline/pai-status.sh` | Bash | 106 | PAI pipeline: dashboard (human + JSON output) | [utility] |
| `assets/social-preview.png` | PNG | — | GitHub social preview image (1280x640) | [asset] |

## Architecture

### Dual-Agent System

Two AI agents run on the same VPS as separate Linux users, communicating through a shared filesystem pipeline:

- **Gregor** (`openclaw` user) — OpenClaw/Sonnet via OpenRouter. Always-on Telegram bot for routine tasks.
- **Isidore Cloud** (`isidore_cloud` user) — Claude Code/Opus. On-demand heavy computation via `claude -p` bridge.
- **PAI Pipeline** (`/var/lib/pai-pipeline/`) — Shared directory with `pai` group permissions (2770 setgid). See `Reference/PAI-PIPELINE.md`.

### Architecture Decisions

Key choices that an agent should understand before suggesting modifications:

- **Security model:** 4-layer permission pipeline — `tools.profile` (coarse), `tools.allow/deny` (fine), `exec.security` (shell), `ask` mode (runtime). Documented in GUIDE.md Phase 7.
- **Provider-agnostic design:** Not locked to any LLM provider. The guide covers Anthropic, OpenAI, OpenRouter, Ollama, and others. Config examples use a models registry for easy switching.
- **Bundled-only skills strategy:** Zero community (ClawHub) skill installs. Only the 50 bundled skills are used. Rationale: supply chain attack surface (see Reference/SKILLS-AND-TOOLS.md for the ClawHavoc case study).
- **Local embeddings:** Uses `embeddinggemma-300m` locally instead of cloud-based OpenAI embeddings. Deliberate privacy + cost decision.
- **Loopback-only gateway:** Gateway bound to 127.0.0.1:18789, never exposed to the internet. All external access via Telegram integration.
- **No privilege escalation in cross-agent pipeline:** Agents communicate via group-writable files, never sudo/su.

## Conventions

- **Commit messages:** Clear "why" with area prefix when helpful (e.g., `docs: add skills research`)
- **File naming:** kebab-case
- **Documentation:** Thorough — the guide includes reasoning blocks, not just commands
- **What to read before modifying:** This file, then README.md, then the specific section of GUIDE.md relevant to your change
