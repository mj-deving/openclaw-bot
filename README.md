<p align="center">
  <img src="assets/social-preview.png" alt="openclaw-hardened — Maximum capability, minimum attack surface" width="640">
</p>

<h3 align="center">Deploy a security-hardened OpenClaw AI agent — from blank server to defended production bot.</h3>

<p align="center">
  6-layer injection defense &bull; Config auditing &bull; Every decision explained
</p>

<p align="center">

![Shell](https://img.shields.io/badge/-Shell-4EAA25?style=flat-square) ![Security](https://img.shields.io/badge/-Security-DC3545?style=flat-square)

</p>

---

## What This Is

A complete deployment system for running [OpenClaw](https://docs.openclaw.ai) on a self-hosted VPS with defense-in-depth security. Includes a 15-phase setup guide, a 6-layer prompt injection defense system, config auditing via ClawKeeper, monitoring scripts, and automated installers.

Not tied to any specific bot — deploy one bot or five, each gets the same hardened baseline.

## Quick Start

**Install the defense system on a running OpenClaw instance (no repo clone needed):**

```bash
curl -fsSL -o defense-install.sh \
  https://raw.githubusercontent.com/mj-deving/openclaw-hardened/main/src/defense/install.sh
bash defense-install.sh          # Downloads defense modules from GitHub, installs plugins
bash ~/.openclaw/workspace/skills/security-defense/validate.sh   # 12 tests, all should pass
```

**Fresh VPS? Full setup from scratch:**

```bash
git clone https://github.com/mj-deving/openclaw-hardened.git && cd openclaw-hardened
sudo bash setup.sh               # 13 steps: OS hardening → OpenClaw → systemd → monitoring
bash src/defense/install.sh      # Defense Shield + ClawKeeper plugins
bash src/defense/validate.sh     # Prove it works
```

> **Prerequisites:** Ubuntu 22.04+ VPS, 2+ GB RAM, a Telegram account, an LLM provider credential.

## Why Hardened?

A vanilla OpenClaw install trusts everything by default:

- **No input scanning** — prompt injection from any message source reaches the LLM unfiltered
- **Supply chain exposure** — community skills from ClawHub execute arbitrary code with no review
- **Self-reconfiguration** — the `gateway` tool can modify its own permission boundaries at runtime
- **No output filtering** — leaked API keys, internal paths, PII pass through to users unchecked

This repo closes those gaps with code-enforced defense, not just model-level safety instructions.

## Security Architecture

| Layer | Mechanism | Prevents |
|-------|-----------|----------|
| **OS hardening** | Firewall, unattended upgrades, dedicated user | Privilege escalation, lateral movement |
| **systemd sandbox** | ReadOnlyPaths, NoNewPrivileges, ProtectSystem | File system compromise, persistence |
| **Tool restrictions** | `tools.deny: [gateway, nodes]` + `exec.security: full` | Self-reconfiguration, unrestricted shell |
| **Network isolation** | Loopback-only gateway, egress filtering | Remote exploitation, data exfiltration |
| **Identity hardening** | DM pairing + system prompt security | Impersonation, prompt extraction |
| **Defense Shield** | 6-layer native plugin (5 hook events covering all 6 layers) | Injection, encoding attacks, credential leaks |
| **ClawKeeper** | Config auditing, drift detection, skill scanning | Config regression, supply chain, behavioral drift |

## Prompt Injection Defense

A 6-layer defense system runs as a native OpenClaw plugin, hooking into 5 gateway events to enforce real-time protection. Based on [Matthew Berman's architecture](https://x.com/MatthewBerman/status/2030423565355676100), hardened against 20 findings from a STRIDE threat model.

| Layer | Hook | What It Does |
|-------|------|-------------|
| **L1: Sanitizer** | `message_received` | Unicode normalization, encoding detection (base64/hex/ROT13/stego), injection pattern matching, wallet flagging. All channels. |
| **L2: LLM Scanner** | `message_received` | Nonce-delimited classifier (Haiku, ~$0.001/scan). High-risk channels only — skips trusted Telegram DMs. |
| **L3: Outbound Gate** | `message_sending` | Catches leaked secrets (18 patterns), internal paths, exfil URLs, financial data. Pre-delivery enforcement. |
| **L4: Redaction** | `message_sending` | Strips API keys, personal emails, phone numbers, dollar amounts before delivery. |
| **L5: Governor** | `llm_input` | Spend/volume tracking, duplicate detection, circuit breaker per caller. |
| **L6: Access Control** | `before_tool_call` | Path guards (30+ denied filenames), URL safety with DNS pinning, private IP blocking. |

**162 tests** covering real attack payloads from [L1B3RT4S](https://github.com/elder-plinius/L1B3RT4S), [P4RS3LT0NGV3](https://github.com/elder-plinius/P4RS3LT0NGV3), and TOKEN80M8 repos.

## What You Get

| Component | Description |
|-----------|-------------|
| **[GUIDE.md](GUIDE.md)** | 4,400+ line walkthrough — 15 phases from OS hardening to context engineering, with threat analysis and reasoning |
| **[Defense System](Reference/DEFENSE-SYSTEM.md)** | 6-layer TypeScript modules, native plugin, STRIDE threat model, 162 tests |
| **[ClawKeeper](Reference/CLAWKEEPER.md)** | Config auditing (9 domains, 49+ checks), drift monitoring, skill supply chain scanning |
| **[Reference docs](Reference/)** | [Security](Reference/SECURITY.md) (2,600 lines), [cost routing](Reference/COST-AND-ROUTING.md), [identity](Reference/IDENTITY-AND-BEHAVIOR.md), [tools](Reference/SKILLS-AND-TOOLS.md), [known bugs](Reference/KNOWN-BUGS.md) |
| **Installers** | `setup.sh` (full VPS), `install.sh` (monitoring), `defense/install.sh` (defense + ClawKeeper, standalone or repo) |
| **Monitoring** | Health check (4-tier detection), ops playbook (12 diagnostics), backup, auto-update, binding verification |
| **Config template** | Annotated `openclaw.json` with security defaults |
| **Validation** | `validate.sh` — 12 attack payload tests proving the defense works |

## What the Installers Do

**`setup.sh`** — Full VPS from scratch. Creates dedicated user, hardens OS, installs Node.js + OpenClaw, deploys config + systemd service, then delegates to `install.sh` for monitoring. 13 idempotent steps.

**`install.sh`** — Deploys monitoring on top of existing OpenClaw: config template, health check, ops playbook, backup, auto-update, logrotate.

**`src/defense/install.sh`** — Installs the defense system. Works standalone (downloads from GitHub) or from a repo checkout. Deploys Defense Shield plugin (all 6 defense layers) + ClawKeeper (config auditing). Idempotent, supports `--dry-run`, `--uninstall`, `--remote HOST`.

**`src/defense/validate.sh`** — Runs 12 attack payloads against the installed defense and reports PASS/FAIL. Works locally on VPS or via `--remote HOST`.

All installers are idempotent and never overwrite existing files. Use `--dry-run` to preview.

## Links

- **Official docs:** [docs.openclaw.ai](https://docs.openclaw.ai)
- **OpenClaw npm:** [npmjs.com/package/openclaw](https://www.npmjs.com/package/openclaw)
- **AI agents:** Point your agent at [AGENTS.md](AGENTS.md) for machine-readable project context
