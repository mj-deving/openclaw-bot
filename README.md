<p align="center">
  <img src="assets/social-preview.png" alt="openclaw-hardened — Maximum capability, minimum attack surface" width="640">
</p>

<h3 align="center">Security-first OpenClaw deployment — from blank server to hardened AI agent.</h3>

<p align="center">
  Capability-locked &bull; Auditable &bull; Every decision explained
</p>

---

## What This Is

A deployment blueprint for running [OpenClaw](https://docs.openclaw.ai) on a self-hosted VPS with a security-first posture. A practitioner's reference that treats AI agent security as a first-class concern and explains the reasoning behind every decision.

## Why Hardened?

A vanilla OpenClaw install trusts everything by default:

- **Supply chain attacks** — community skills from ClawHub execute arbitrary code with no review ([ClawHavoc campaign](Reference/SKILLS-AND-TOOLS.md))
- **Self-reconfiguration** — the `gateway` tool can modify its own permission boundaries at runtime
- **Credential exfiltration** — prompt injection can extract API keys and auth tokens via tool calls
- **Silent polling death** — Telegram polling fails silently with no built-in detection or recovery

This repo closes those gaps with defense-in-depth, documented from first principles.

## Security Model

| Layer | Mechanism | Prevents |
|-------|-----------|----------|
| 1. Tool profile | `tools.profile: "full"` + `tools.deny` | Self-reconfiguration, device access |
| 2. Exec gating | `exec.security: "full"` | Unrestricted shell with no audit trail |
| 3. Network isolation | Loopback-only gateway (`127.0.0.1:18789`) | Remote exploitation, direct API access |
| 4. Identity hardening | DM pairing + system prompt security | Impersonation, prompt extraction |
| 5. Defense proxy | 6-layer prompt injection defense (`127.0.0.1:18800`) | Injection, exfiltration, credential leaks |

Plus: zero community skills (bundled-only policy), supply chain lockdown, local embeddings.

## Prompt Injection Defense

A 6-layer defense system intercepts all LLM API calls, providing app-level protection against prompt injection, jailbreaks, and data exfiltration. Based on [Matthew Berman's architecture](https://x.com/MatthewBerman/status/2030423565355676100), informed by attack research from Pliny the Prompter's repos.

| Layer | Name | What It Does |
|-------|------|-------------|
| L1 | Deterministic Sanitizer | Unicode homoglyphs, base64/hex/ROT13 decoding, injection pattern detection (24+ patterns), zero-width/Zalgo/steganography removal, wallet flagging |
| L2 | LLM Frontier Scanner | Nonce-delimited classification prompt, risk scoring 0-100, attack category detection |
| L3 | Outbound Content Gate | Catches leaked API keys (18 patterns), internal paths, exfil URLs, financial data in responses |
| L4 | Redaction Pipeline | Strips API keys, personal emails, phone numbers, dollar amounts before delivery |
| L5 | Call Governor | Spend/volume limits, duplicate detection, circuit breaker per caller |
| L6 | Access Control | Path guards (30+ denied filenames), URL safety with DNS pinning, private IP blocking |

The defense proxy runs as a Bun HTTP server at `127.0.0.1:18800`, transparently intercepting API calls via `ANTHROPIC_BASE_URL` and `OPENAI_BASE_URL` environment variables. Includes a deploy script with `--rollback` support.

**162 tests** covering all attack vectors. See [Reference/DEFENSE-SYSTEM.md](Reference/DEFENSE-SYSTEM.md) for the full reference.

## What You Get

- **[The Guide](GUIDE.md)** — 15-phase walkthrough from OS hardening to context engineering, with threat analysis and tradeoff reasoning
- **[Reference docs](Reference/)** — Deep research on [security](Reference/SECURITY.md) (2,600 lines, 55 sources), [cost routing](Reference/COST-AND-ROUTING.md), [identity security](Reference/IDENTITY-AND-BEHAVIOR.md), [tool permissions](Reference/SKILLS-AND-TOOLS.md), [known bugs](Reference/KNOWN-BUGS.md), and more
- **Monitoring scripts** — Self-healing health check (4-tier failure detection, exponential backoff), ops playbook (12 diagnostic checks), backup, update management, binding verification
- **Config template** — Annotated `openclaw.json` with security defaults and audit annotations

## Quick Start

**Fresh VPS? Use the one-command installer:**

```bash
git clone https://github.com/mj-deving/openclaw-hardened.git
cd openclaw-hardened

# From blank Ubuntu 24.04 to running Gregor — handles everything:
sudo bash setup.sh --dry-run    # Preview all 13 steps
sudo bash setup.sh              # OS hardening, Node.js, OpenClaw, config, systemd, monitoring
```

**Already have OpenClaw installed? Deploy just the tooling:**

```bash
./install.sh --dry-run    # See what it will do
./install.sh              # Deploy config, scripts, cron jobs, logrotate
```

> **Prerequisites:** Ubuntu 22.04+ VPS, 2+ GB RAM, a Telegram account, and an LLM provider API key.

## What the Installers Do

**`setup.sh`** — Full VPS setup from scratch: creates `openclaw` user, hardens OS (firewall, unattended upgrades), installs Node.js 22.x + OpenClaw, deploys config + systemd service with hardening, then delegates to `install.sh` for monitoring. Interactive or non-interactive (secrets via env vars). 13 idempotent steps — safe to re-run.

**`install.sh`** — Deploys operational tooling on top of an existing OpenClaw install. It does **not** install OpenClaw itself.

- Config template → `~/.openclaw/openclaw.json` (never overwrites existing)
- Monitoring scripts → `~/scripts/` (health-check, ops-playbook, backup, auto-update, binding check)
- Cron jobs → backup (daily), health check (5min), auto-update (weekly), binding check (5min)
- Log rotation → `/etc/logrotate.d/openclaw` (requires sudo, skipped if unavailable)

Both are safe to re-run. Never overwrite existing files. Use `--dry-run` to preview.

## Links

- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **OpenClaw npm:** [npmjs.com/package/openclaw](https://www.npmjs.com/package/openclaw)
- **AI agents:** Point your agent at [AGENTS.md](AGENTS.md) for machine-readable project context
