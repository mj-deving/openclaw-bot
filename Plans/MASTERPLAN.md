# OpenClaw Telegram Bot — Setup Guide

**Goal:** Deploy a capable OpenClaw instance on a VPS, using Telegram as the primary channel, powered by Anthropic Claude.

> **Guiding philosophy:** *As capable as possible, while as secure as necessary.*
>
> Security exists to protect capability, not to prevent it. Every deny-list entry, every disabled feature must justify itself against the question: "Does removing this capability make the bot meaningfully safer, or just less useful?"

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Phase 0 — VPS Preparation](#2-phase-0--vps-preparation)
3. [Phase 1 — OpenClaw Installation](#3-phase-1--openclaw-installation)
4. [Phase 2 — Anthropic Provider Configuration](#4-phase-2--anthropic-provider-configuration)
5. [Phase 3 — Telegram Channel Setup](#5-phase-3--telegram-channel-setup)
6. [Phase 4 — Security Hardening](#6-phase-4--security-hardening)
7. [Phase 5 — Bot Identity & Behavior](#7-phase-5--bot-identity--behavior)
8. [Phase 6 — Memory & Persistence](#8-phase-6--memory--persistence)
9. [Phase 7 — Systemd Service & Auto-Recovery](#9-phase-7--systemd-service--auto-recovery)
10. [Phase 8 — Monitoring, Backups & Log Hygiene](#10-phase-8--monitoring-backups--log-hygiene)
11. [Phase 9 — Skills](#11-phase-9--skills)
12. [Phase 10 — Autonomous Engagement (Cron)](#12-phase-10--autonomous-engagement-cron)
13. [Phase 11 — Async Pipeline (Local ↔ Bot)](#13-phase-11--async-pipeline-local--bot)
14. [Phase 12 — Cost Monitoring](#14-phase-12--cost-monitoring)
15. [Security Threat Model](#15-security-threat-model)
16. [Configuration Reference](#16-configuration-reference)
17. [Runbook: Common Operations](#17-runbook--common-operations)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                          Your VPS                             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                OpenClaw Gateway                         │  │
│  │                (Node.js 22.x process)                   │  │
│  │                Port 18789 (loopback ONLY)              │  │
│  │                                                        │  │
│  │  ┌──────────┐  ┌────────┐  ┌─────────┐               │  │
│  │  │ Telegram │  │ Agent  │  │ Memory  │               │  │
│  │  │ Bot API  │  │ Runtime│  │ SQLite  │               │  │
│  │  │ (paired) │  │        │  │ + vec   │               │  │
│  │  └────┬─────┘  └───┬────┘  └────┬────┘               │  │
│  │       │            │            │                      │  │
│  │       │       ┌────┴─────┐  ┌───┴──────┐             │  │
│  │       │       │ Anthropic│  │ Local    │             │  │
│  │       │       │ Claude   │  │ Embeddings│             │  │
│  │       │       │ API      │  │ gemma-300m│             │  │
│  │       │       └──────────┘  └──────────┘             │  │
│  └───────┼───────────────────────────────────────────────┘  │
│          │                                                   │
│          │ HTTPS (Bot API polling)                            │
│          ▼                                                   │
│  api.telegram.org              api.anthropic.com             │
│                                                              │
│  SSH tunnel ◄──── Local machine (management)                  │
└──────────────────────────────────────────────────────────────┘
```

**Key architectural points:**
- Gateway binds to **loopback only** (127.0.0.1) — never exposed to the internet
- Outbound connections: Telegram Bot API, Anthropic API
- Management access via **SSH tunnel only** — no Tailscale, no public Control UI
- Plugins enabled selectively (memory-core, telegram, device-pair) — not from ClawHub
- Single channel: **Telegram** (paired to owner via device pairing)
- **Posture:** Capability-first — `tools.profile "full"` with targeted deny list, not blanket lockdown

---

## 2. Phase 0 — VPS Preparation

### 2.1 System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| RAM | 2 GB | 4 GB |
| Disk | 10 GB | 20 GB SSD |
| CPU | 1 vCPU | 2 vCPU |
| Network | IPv4, outbound to Anthropic + Telegram | Same |

### 2.2 OS-Level Hardening

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Create dedicated user (NEVER run OpenClaw as root)
sudo useradd -m -s /bin/bash openclaw
sudo passwd openclaw  # strong password, then lock it:
sudo passwd -l openclaw  # disable password login, SSH key only

# 3. Firewall (ufw)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
# Do NOT open port 18789 — gateway stays on loopback
sudo ufw enable

# 4. SSH hardening
# In /etc/ssh/sshd_config:
#   PermitRootLogin no
#   PasswordAuthentication no
#   AllowUsers your-admin-user openclaw
sudo systemctl restart sshd

# 5. Automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# 6. Install Node.js 22.x (required by OpenClaw)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 7. Verify
node --version  # should be >= 22.12.0
npm --version
```

### 2.3 Disk Encryption (Optional but recommended)

If your VPS provider supports LUKS or encrypted volumes, enable it. Credentials in `~/.openclaw/` are stored as plaintext files protected only by Unix permissions (0600/0700).

### 2.4 Directory Structure on VPS

```
/home/openclaw/
├── .openclaw/                  # OpenClaw state directory (auto-created)
│   ├── openclaw.json           # Main configuration
│   ├── credentials/            # OAuth tokens, API keys
│   ├── memory/                 # SQLite memory database
│   ├── agent/                  # Agent workspace
│   └── logs/                   # Gateway logs
└── workspace/                  # Agent working directory
```

---

## 3. Phase 1 — OpenClaw Installation

### 3.1 Install as the Dedicated User

```bash
# Switch to the openclaw user
sudo -u openclaw -i

# Install OpenClaw globally (MUST be >= 2026.1.29 for CVE patches)
npm install -g openclaw@latest

# Verify installation
openclaw --version

# Run onboarding wizard (interactive)
openclaw onboard --install-daemon
```

The onboarding wizard will:
1. Ask for your Anthropic API key
2. Generate an auth token for the gateway
3. Create `~/.openclaw/openclaw.json`
4. Optionally install as a systemd service

### 3.2 Alternative: Install Script

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

This auto-detects missing Node.js and installs it. It also sets up the systemd daemon.

### 3.3 Post-Install Verification

```bash
# Check the gateway starts
openclaw gateway start

# Check it's listening on loopback only
ss -tlnp | grep 18789
# Should show: 127.0.0.1:18789 — NOT 0.0.0.0:18789

# Stop it (configure before running for real)
openclaw gateway stop
```

---

## 4. Phase 2 — Anthropic Provider Configuration

### 4.1 Authentication via Setup-Token (Claude Max Subscription)

A Claude Max subscription can directly power OpenClaw via the **setup-token** method. No separate API account needed.

```bash
# Step 1: Generate a setup token via Claude Code CLI
claude setup-token

# Step 2: On the VPS (as the openclaw user), register it
openclaw models auth setup-token --provider anthropic

# If the token was generated on a different machine, paste it manually:
openclaw models auth paste-token --provider anthropic

# Step 3: Verify authentication
openclaw models status
openclaw doctor
```

**How it works:** The setup-token creates an OAuth-based credential that ties your Max subscription to OpenClaw's Anthropic provider. The gateway refreshes the token automatically.

**Caveats:**
- If you see "OAuth token refresh failed," run `openclaw doctor --fix`
- If you see "credentials only authorized for use with Claude Code," fall back to an API key (see 4.1b)
- **Note (Jan 2026):** Anthropic may have restricted setup-token for non-Claude-Code use. If setup-token auth fails, proceed to the API key fallback.

**Important tradeoff:** Setup-token auth does **not** support prompt caching. Claude Max is metered (5-hour rolling windows, weekly caps against 5x Pro usage), so every message re-sends the full system prompt at full input cost with zero reuse. For a bot that handles many messages per day, this adds up fast. Switching to API key auth (4.1b) with `cacheRetention: "long"` enables prompt caching — 90% savings on repeated system prompt tokens. Setup-token works for getting started, but API key auth with caching is the recommended long-term configuration.

### 4.1b API Key Auth (Recommended for Production)

For long-term operation, API key auth with prompt caching is the optimal configuration. Create an Anthropic API account at `console.anthropic.com`:

```bash
# Option A: Environment variable (preferred for secrets)
export ANTHROPIC_API_KEY="sk-ant-..."

# Option B: Edit config directly
openclaw config set provider.name anthropic
openclaw config set provider.apiKey "sk-ant-..."
```

**Note:** The API account is separate from your Claude Max subscription. Costs are per-token (~$3/MTok input, ~$15/MTok output for Sonnet). To enable prompt caching after switching, add `cacheRetention: "long"` to your model config (see Phase 12 — Cost Monitoring for details).

### 4.2 Post-Auth Verification

```bash
openclaw models status
# Should show: anthropic — authenticated

# Test a query
openclaw chat --once "Hello, respond with just 'OK'"
```

### 4.3 Model Selection

```bash
openclaw config set provider.model "claude-sonnet-4"
```

| Model | Best For | Cost |
|-------|----------|------|
| `claude-opus-4` | Complex reasoning, long context | Highest |
| `claude-sonnet-4` | Good balance of quality/cost | Medium |
| `claude-haiku-4` | Fast responses, simple queries | Lowest |

Sonnet is recommended as the default — good quality at reasonable cost. Use Opus for complex tasks, Haiku for automated/scheduled tasks.

### 4.4 Rate Limits & Cost Management

```jsonc
// In ~/.openclaw/openclaw.json
{
  "provider": {
    "name": "anthropic",
    "model": "claude-sonnet-4",
    "maxTokens": 1024  // Cap output tokens for cost predictability
  }
}
```

Capping output tokens keeps responses concise and costs predictable. Telegram messages can be up to 4096 chars.

---

## 5. Phase 3 — Telegram Channel Setup

Telegram is the bot's primary channel — personal, mobile-accessible, paired to owner.

### 5.1 Create a Telegram Bot via @BotFather

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a name and username for your bot
4. BotFather gives you a **bot token** (format: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
5. **Save this token securely** — it goes in the systemd env file, NOT in openclaw.json

### 5.2 Telegram Configuration

```jsonc
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "allowFrom": [],       // Empty = pairing mode (pair via first message)
      "groupPolicy": "allowlist",  // FLAT STRING (not an object!)
      "groups": {}
    }
  }
}
```

### 5.3 Bot Token as Environment Variable

Add to `/etc/openclaw/env`:

```bash
TELEGRAM_BOT_TOKEN=your-bot-token-here
```

### 5.4 Pairing Process

Telegram uses a **pairing** model — the first person to DM the bot becomes the paired user:

1. Start the gateway: `openclaw gateway start`
2. Open Telegram, find your bot
3. Send any message (e.g., "hello")
4. OpenClaw generates a pairing code shown in the gateway logs
5. Confirm the pairing via the gateway logs or Control UI (via SSH tunnel)
6. Once paired, only YOUR Telegram account can interact with the bot

### 5.5 Telegram Security Model

| Aspect | Detail |
|--------|--------|
| **Auth model** | Pairing (cryptographic user ID — locked to owner after first DM) |
| **Encryption** | TLS to Telegram API (E2E only in secret chats, not bots) |
| **Message format** | Rich text, markdown, media, up to 4096 chars |
| **Attack surface** | DM prompt injection (but only from paired user — minimal risk) |
| **Stream mode** | `partial` — responses stream as they generate |

---

## 6. Phase 4 — Security Hardening

### 6.1 Gateway Binding

```jsonc
{
  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "GENERATED_DURING_ONBOARD",
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "controlUi": {
      "dangerouslyDisableDeviceAuth": false
    },
    "tailscale": { "mode": "off" }
  }
}
```

**Important:** There's a known bug where loopback failure silently falls back to `0.0.0.0` (all interfaces). After starting, ALWAYS verify:

```bash
ss -tlnp | grep 18789
# MUST show 127.0.0.1:18789, NOT 0.0.0.0:18789
```

Add this check to your monitoring (Phase 8).

### 6.2 Tool Restrictions

Capability-first with targeted denials:

```jsonc
{
  "tools": {
    "profile": "full",
    "deny": [
      "gateway",            // Prevents AI from modifying its own config
      "nodes",              // No device invocation
      "sessions_spawn",     // No spawning sub-sessions
      "sessions_send"       // No cross-session messaging
    ],
    "web": {
      "search": { "enabled": true },
      "fetch": { "enabled": true }
    },
    "exec": {
      "security": "full",
      "ask": "off"          // Set to "always" if you want confirmation prompts
    },
    "elevated": { "enabled": false }
  }
}
```

**What's denied and why:**
- `gateway` — zero-gating risk: AI could reconfigure itself
- `nodes` — no need for device invocation in single-VPS setup
- `sessions_spawn` / `sessions_send` — no cross-session operations needed

### 6.3 Disable Network Discovery

```jsonc
{
  "discovery": { "mdns": { "mode": "off" } }
}
```

OpenClaw broadcasts its presence via mDNS by default. Disable it.

### 6.4 Disable Config Writes from Chat

```jsonc
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "config": false
  }
}
```

### 6.5 Plugins — Selective Enable

```jsonc
{
  "plugins": {
    "enabled": true,
    "slots": { "memory": "memory-core" },
    "entries": {
      "telegram": { "enabled": true },
      "device-pair": { "enabled": true },
      "memory-core": { "enabled": true },
      "memory-lancedb": { "enabled": false }
    }
  }
}
```

### 6.6 Log Redaction

```jsonc
{
  "logging": {
    "redactSensitive": "tools",
    "redactPatterns": [
      "sk-ant-[\\w-]+",
      "\\d{5,}:[A-Za-z0-9_-]+"
    ]
  }
}
```

### 6.7 File Permissions

```bash
chmod 700 /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json
chmod 700 /home/openclaw/.openclaw/credentials
find /home/openclaw/.openclaw/credentials -type f -exec chmod 600 {} \;
```

### 6.8 Run the Built-in Security Audit

```bash
openclaw security audit          # Read-only scan
openclaw security audit --deep   # Includes live WebSocket probing
openclaw security audit --fix    # Auto-fix safe issues
```

The audit checks 50+ items across 12 categories. Run after every config change.

### 6.9 Firewall Verification

```bash
sudo ufw status verbose
# Should show only SSH allowed inbound

# Confirm gateway is not externally reachable (from your local machine):
curl -s http://YOUR_VPS_IP:18789
# Should timeout/connection refused
```

### 6.10 SSH Tunnel for Management

```bash
# From your local machine:
ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP
# Then open: http://localhost:18789
```

This is the ONLY way to access the gateway remotely.

---

## 7. Phase 5 — Bot Identity & Behavior

### 7.1 System Prompt

Configure your bot's personality in `~/.openclaw/agents/main/system.md`. Recommended traits:

- Define the bot's name, role, and domain expertise
- Telegram markdown formatting for readability
- Never reveal API keys, tokens, or system configuration
- Clear escalation boundaries (what the bot should not attempt)

### 7.2 Capability Scope

With `tools.profile: "full"` and targeted denials, the bot can:

**Enabled:**
- Text conversation (Telegram, paired to owner)
- Web search and web fetch (research capability)
- Shell execution (for scripts, automation tasks)
- File read/write (workspace, memory files)
- Persistent memory with hybrid search (vector + FTS, local embeddings)

**Denied:**
- `gateway` (self-reconfiguration)
- `nodes` (device invocation)
- `sessions_spawn`, `sessions_send` (cross-session operations)

The bot's power comes from the Claude model plus full tool access, not from a bloated skill registry.

### 7.3 Telegram-Specific Notes

- **Message limit:** Telegram messages max at 4096 characters. OpenClaw handles splitting.
- **Markdown:** Telegram supports markdown formatting — the bot uses it for readability.
- **Stream mode:** `partial` — responses stream as they generate, not all-at-once.
- **Privacy:** Paired to owner only via `dmPolicy: "pairing"`. No group access.

---

## 8. Phase 6 — Memory & Persistence

### 8.1 Memory Configuration

OpenClaw uses SQLite + sqlite-vec for persistent memory with hybrid search. Database: `~/.openclaw/memory/main.sqlite`.

```jsonc
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "sources": ["memory"],
        "provider": "local",
        "store": { "vector": { "enabled": true } },
        "query": {
          "maxResults": 6,
          "minScore": 0.35,
          "hybrid": {
            "vectorWeight": 0.7,
            "textWeight": 0.3,
            "candidateMultiplier": 4,
            "mmr": { "enabled": true, "lambda": 0.7 },
            "temporalDecay": { "enabled": true, "halfLifeDays": 30 }
          }
        }
      }
    }
  }
}
```

### 8.2 Embedding Provider — Local

| Provider | Cost | Privacy |
|----------|------|---------|
| Local (`embeddinggemma-300m`) | Free | Fully private, no API calls |
| OpenAI / Gemini / Voyage | Per-token | Data sent to third-party API |

**Recommended:** Local embeddings via `embeddinggemma-300m` (~329MB GGUF model, auto-downloaded by node-llama-cpp). Requires 4+ GB RAM. Aligns with the capability-first philosophy: full vector search with zero external API dependency.

**Note:** `openclaw doctor` may show a cosmetic false-positive about "no local model file found" — this is a detection path mismatch, not a real issue. Run `memory index --force` to verify it works.

### 8.3 Backup Strategy

Create a backup script (`~/scripts/backup.sh`) that backs up:

1. **Config** → `~/.openclaw/backups/config-YYYYMMDD-HHMMSS.json` (600 perms)
2. **Memory DB** → `~/.openclaw/backups/memory-YYYYMMDD-HHMMSS.sqlite` (600 perms)
3. **Memory files** → `~/.openclaw/backups/memory-files-YYYYMMDD-HHMMSS.tar.gz` (600 perms)

Schedule with cron for daily execution and add automatic retention pruning (e.g., 30-day).

```bash
# Example cron entry:
0 3 * * * /home/openclaw/scripts/backup.sh >> /home/openclaw/.openclaw/logs/backup.log 2>&1
```

A sanitized config template is included in this repo at `src/config/openclaw.json.example`.

---

## 9. Phase 7 — Systemd Service & Auto-Recovery

### 9.1 Systemd Unit File

```ini
# /etc/systemd/system/openclaw.service
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw
EnvironmentFile=/etc/openclaw/env

ExecStart=/usr/bin/openclaw gateway --port 18789
ExecStop=/bin/kill -SIGTERM $MAINPID

Restart=on-failure
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/openclaw/.openclaw /home/openclaw/workspace
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictRealtime=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
```

### 9.2 Secure Environment File

```bash
sudo mkdir -p /etc/openclaw
sudo tee /etc/openclaw/env > /dev/null << 'EOF'
# Only uncomment if using API key instead of setup-token:
# ANTHROPIC_API_KEY=sk-ant-...
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
OPENCLAW_STATE_DIR=/home/openclaw/.openclaw
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_DISABLE_BONJOUR=1
EOF
sudo chmod 600 /etc/openclaw/env
sudo chown root:openclaw /etc/openclaw/env
```

### 9.3 Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw
sudo systemctl status openclaw
```

### 9.4 Post-Start Verification

```bash
# Confirm loopback binding (CRITICAL)
ss -tlnp | grep 18789
# MUST show 127.0.0.1:18789

# Check logs
journalctl -u openclaw -f

# Confirm Telegram connection
# Look for: [Telegram] Connected
```

---

## 10. Phase 8 — Monitoring, Backups & Log Hygiene

### 10.1 Binding Verification Cron

Create a script that catches the 0.0.0.0 fallback bug:

```bash
#!/bin/bash
# /home/openclaw/scripts/verify-binding.sh
if ss -tlnp | grep ':18789' | grep -q '0.0.0.0'; then
    echo "CRITICAL: OpenClaw gateway bound to 0.0.0.0! Stopping."
    systemctl stop openclaw
fi
```

```bash
chmod +x /home/openclaw/scripts/verify-binding.sh
# Run every 5 minutes
(crontab -l; echo "*/5 * * * * /home/openclaw/scripts/verify-binding.sh") | crontab -
```

### 10.2 Log Rotation

```bash
# /etc/logrotate.d/openclaw
/home/openclaw/.openclaw/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0600 openclaw openclaw
}
```

### 10.3 Health Check Script

```bash
#!/bin/bash
# /home/openclaw/scripts/health-check.sh

if ! systemctl is-active --quiet openclaw; then
    echo "OpenClaw is down. Restarting..."
    systemctl start openclaw
fi

if ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/health | grep -q "200"; then
    echo "Gateway health check failed"
fi
```

### 10.4 Auto-Update with Security Audit

```bash
#!/bin/bash
# /home/openclaw/scripts/auto-update.sh

CURRENT_VERSION=$(openclaw --version 2>/dev/null)
sudo -u openclaw npm update -g openclaw
NEW_VERSION=$(openclaw --version 2>/dev/null)

if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo "$(date): Updated OpenClaw from $CURRENT_VERSION to $NEW_VERSION"
    systemctl restart openclaw
    sleep 5
    /home/openclaw/scripts/verify-binding.sh
fi

# Always run security audit
openclaw security audit --deep >> /home/openclaw/.openclaw/logs/audit.log 2>&1
```

```bash
chmod +x /home/openclaw/scripts/auto-update.sh
# Weekly: Sunday 4 AM
(crontab -l; echo "0 4 * * 0 /home/openclaw/scripts/auto-update.sh >> /home/openclaw/.openclaw/logs/update.log 2>&1") | crontab -
```

---

## 11. Phase 9 — Skills

### 11.1 Bundled vs. Community Skills

OpenClaw ships with ~50 **bundled skills** inside the npm package. These are official, maintained, and carry no supply chain risk. They live at `~/.npm-global/lib/node_modules/openclaw/skills/` and are completely separate from the ClawHub community registry.

**Key concept:** Bundled skills show as "missing" until their external CLI dependency is installed. Once the binary is in PATH, the skill automatically becomes "ready." No `clawhub install` required.

```bash
# Check what skills exist and what they need
openclaw skills list                  # Shows all 50 with status
openclaw skills info <skill-name>     # Shows dependencies + install options
```

**Recommended approach: Use bundled skills. Avoid community (ClawHub) skills entirely unless you have a specific need that bundled skills can't cover.**

### 11.2 Useful Bundled Skills for a VPS Bot

| Skill | CLI Dependency | Install Command (Linux) | What It Does |
|-------|---------------|------------------------|-------------|
| **github** | `gh` | `sudo apt install gh` | GitHub CLI — issues, PRs, CI runs, code review |
| **gh-issues** | `gh` | (same as above) | Fetch issues, spawn agents for fixes |
| **summarize** | `summarize` | `npm install -g @steipete/summarize` | Summarize URLs, PDFs, YouTube transcripts |
| **clawhub** | `clawhub` | `npm install -g clawhub` | Search/install community skills (if needed later) |
| **healthcheck** | (none) | Already ready | Host security hardening and audit scheduling |
| **weather** | (none) | Already ready | Weather via wttr.in / Open-Meteo |
| **tmux** | (none) | Already ready | Remote-control tmux sessions |
| **skill-creator** | (none) | Already ready | Create custom skills |

Some skills are **platform-specific** and won't work on a Linux VPS:
- `peekaboo`, `imsg`, `apple-notes`, `apple-reminders`, `things-mac`, `bear-notes` — **macOS only**
- `sonoscli`, `openhue`, `camsnap` — require local network hardware
- `openai-whisper`, `sag` — require audio hardware

### 11.3 Installing Bundled Skill Dependencies

```bash
# 1. Check what a skill needs
openclaw skills info github
# Output: Requirements: Binaries: ✗ gh

# 2. Install the dependency
sudo apt install gh                          # GitHub CLI (apt)
npm install -g @steipete/summarize           # Summarize (npm)
npm install -g clawhub                       # ClawHub CLI (npm)

# 3. Verify the skill is now ready
openclaw skills info github
# Output: Requirements: Binaries: ✓ gh

# 4. For skills requiring auth (like github), set up credentials:
gh auth login                                # Interactive or --with-token for headless
```

**Post-install checklist:**
```bash
# Verify nothing broke
openclaw security audit --deep               # Should show no new issues
ss -tlnp | grep 18789                        # Gateway still on loopback
openclaw skills list | grep "✓ ready"        # Confirm new skills active
```

**No gateway restart needed.** Bundled skills are detected dynamically based on binary availability.

### 11.4 The ClawHavoc Risk (Community Skills)

If you do consider community skills from ClawHub, be aware of the supply chain risks:

The ClawHavoc campaign (Feb 2026) revealed serious problems in the ClawHub ecosystem:

| Metric | Value |
|--------|-------|
| Confirmed malicious skills | 824+ |
| Single worst actor | hightower6eu — 314 malicious skills |
| Malware type | AMOS macOS infostealer, credential theft |
| Malicious rate at peak | ~20% of audited packages |

**Critical facts:**
- **Skills run IN-PROCESS with the Gateway.** A malicious skill has full access to the bot's process, memory, and API keys. There is NO sandboxing.
- **Prompt injection is NOT scanned for.** VirusTotal catches binary malware, not adversarial prompts embedded in SKILL.md files.
- **npm lifecycle scripts execute during `clawhub install`.** Classic supply chain vector.

### 11.5 Community Skill Vetting Checklist

Before installing ANY community skill from ClawHub:

- [ ] Author is known/trusted (established community member with 1K+ downloads)
- [ ] No VirusTotal flags
- [ ] No ClawHavoc association
- [ ] Manually read SKILL.md — no `eval()`, `fetch()` to unknown hosts, `exec()`, obfuscated code
- [ ] No npm lifecycle scripts in `package.json` (preinstall, postinstall, prepare)
- [ ] Does not require denied tools (gateway, nodes, sessions_spawn, sessions_send)
- [ ] Pin exact version after install — no auto-updates
- [ ] Run `openclaw security audit --deep` after installation
- [ ] Verify gateway binding hasn't changed: `ss -tlnp | grep 18789` shows 127.0.0.1

### 11.6 Summary

Your bot's power comes from the Claude model plus full tool access — not from a large skill registry. The bundled skills cover the most common needs (GitHub, summarization, health monitoring). Community skills from ClawHub carry real supply chain risk and should only be installed after thorough vetting.

---

## 12. Phase 10 — Autonomous Engagement (Cron)

OpenClaw includes a built-in cron system that lets the bot perform tasks on a schedule — without any user interaction. The most common use case is **autonomous engagement**: the bot periodically generates and posts content on its own.

### 12.1 The Cron System

OpenClaw's cron is not a system-level crontab. It's a built-in scheduler that runs inside the gateway process. Cron jobs trigger agent sessions at specified intervals, with full access to the bot's tools, memory, and configured model.

```bash
# Core cron commands
openclaw cron list                     # View all scheduled jobs
openclaw cron add [options]            # Create a new job
openclaw cron edit <jobId> [options]   # Modify an existing job
openclaw cron remove <jobId>           # Delete a job

# Note: cron edit requires --token for gateway auth
openclaw cron edit <jobId> --token <gateway-token> --model "anthropic/claude-haiku-4-5"
```

### 12.2 Use Cases

| Use Case | Description | Frequency |
|----------|-------------|-----------|
| **Autonomous engagement** | Bot generates and posts original content | Multiple times daily |
| **Scheduled health checks** | Run system diagnostics, report anomalies | Hourly or daily |
| **Digest generation** | Summarize accumulated messages or events | Daily |
| **Memory maintenance** | Re-index, prune, or consolidate memory | Weekly |

### 12.3 Setting Up Autonomous Engagement

The most powerful use of cron is giving your bot autonomous voice — it generates content on its own schedule, using its personality, memory, and tools.

```bash
openclaw cron add \
  --name "daily-engagement" \
  --cron "37 8,12,17,21 * * *" \
  --tz "Europe/Berlin" \
  --session isolated \
  --timeout 180 \
  --message "Generate an original post. Draw on your memory, personality, and current knowledge. Be authentic and interesting." \
  --model "anthropic/claude-haiku-4-5" \
  --thinking off \
  --announce
```

**What each flag does:**

| Flag | Purpose |
|------|---------|
| `--name` | Human-readable label for the job |
| `--cron` | Standard cron expression (minute hour day month weekday) |
| `--tz` | Timezone for schedule interpretation |
| `--session isolated` | Each run starts a fresh session (recommended — see 12.4) |
| `--timeout` | Maximum seconds per run (prevents runaway sessions) |
| `--message` | The prompt sent to the agent when the job fires |
| `--model` | Model override for this job (see 12.5 for cost guidance) |
| `--thinking off` | Disable extended thinking (unnecessary for routine posts) |
| `--announce` | Post output to the active channel (Telegram) |

**Prompt design matters.** The `--message` is the only input the agent receives for each run. Make it specific enough to produce good output but open enough to allow variety. The agent has full access to its memory, so it can reference past conversations and context.

### 12.4 Session Types for Cron

| Type | Behavior | Best For |
|------|----------|----------|
| `isolated` | Fresh session each run. No context from previous runs. | Autonomous engagement, scheduled tasks |
| `shared` | Continues the same session across runs. Context accumulates. | Multi-step workflows, running totals |

**Recommendation:** Use `isolated` for engagement posts. Each post should stand on its own. Shared sessions accumulate context (and cost) across runs, which is wasteful for independent posts and creates the risk of context growing unboundedly.

### 12.5 Model & Cost Optimization

Cron jobs are the easiest place to optimize costs because they're **deterministic workloads** — you know exactly what the bot will do, so you can choose the cheapest adequate model.

**Per-cron model override:**
```bash
# Use Haiku for automated posts (cheapest, fast)
openclaw cron edit <jobId> --model "anthropic/claude-haiku-4-5" --thinking off

# Use Sonnet for tasks requiring more nuance
openclaw cron edit <jobId> --model "anthropic/claude-sonnet-4"
```

**Priority chain:** Job-level model override > agent config default model.

**Cost comparison for 5 daily cron runs (~16K input tokens, ~800 output tokens each):**

| Model | Daily Input Cost | Daily Output Cost | Daily Total | Monthly |
|-------|-----------------|-------------------|-------------|---------|
| Opus | ~$0.40 | ~$0.10 | ~$0.50 | ~$15 |
| Sonnet | ~$0.24 | ~$0.06 | ~$0.30 | ~$9 |
| Haiku | ~$0.08 | ~$0.02 | ~$0.10 | ~$3 |

**Recommendation:** Start with Haiku. Autonomous engagement posts don't require deep reasoning — they need personality and fluency, which Haiku handles well. Upgrade to Sonnet only if quality is noticeably poor.

### 12.6 Security Considerations

The `cron` tool is one of OpenClaw's built-in tools. If it's not in your deny list, the AI can **create, modify, and delete its own cron jobs** during a conversation.

**Decision: Should you deny the `cron` tool?**

| Posture | Deny List | Implication |
|---------|-----------|-------------|
| **Conservative** | Add `cron` to deny list | Bot cannot create/modify scheduled tasks. You manage all cron via CLI. Safer. |
| **Capability-first** | Leave `cron` allowed | Bot can schedule its own tasks. More autonomous, but risk of unintended job creation. |

If you follow the capability-first posture from Phase 4, leaving `cron` allowed is reasonable — but monitor the job list periodically:

```bash
openclaw cron list   # Check for unexpected jobs
```

Alternatively, use group syntax to deny all automation tools at once:
```jsonc
{ "tools": { "deny": ["group:automation"] } }
// Denies both "cron" and "gateway"
```

### 12.7 Monitoring Cron Jobs

```bash
# List all jobs with their status and last run time
openclaw cron list

# Run logs are stored per-job
ls ~/.openclaw/cron/runs/<jobId>.jsonl

# Watch for cron activity in gateway logs
journalctl -u openclaw -f | grep -i cron
```

**What to watch for:**
- **Failed runs:** Check logs for timeout errors or model authentication failures
- **Unexpected jobs:** If the AI has `cron` tool access, verify no rogue jobs were created
- **Cost drift:** Each cron run costs tokens. Monitor via your cost tracking solution (see Phase 8)
- **Content quality:** Review the bot's autonomous posts periodically — especially after model downgrades

### 12.8 Summary

The cron system transforms your bot from a reactive assistant into an autonomous agent. Start with a single engagement job on the cheapest adequate model (Haiku), monitor quality and costs, then expand. Keep sessions isolated for independent tasks. Whether you deny the `cron` tool to the AI depends on your security posture — conservative setups deny it, capability-first setups allow it with monitoring.

---

## 13. Phase 11 — Async Pipeline (Local ↔ Bot)

Your bot runs 24/7 on a VPS. Your local AI assistant (e.g., Claude Code) runs on-demand in ephemeral sessions. A **pipeline** bridges them — enabling task delegation, escalation, and knowledge exchange without requiring both to be online simultaneously.

### 13.1 The Concept

The pipeline is a file-based message queue using three directories on the VPS:

```
~/.openclaw/pipeline/
├── inbox/      # Messages TO the bot (local assistant writes, bot reads)
├── outbox/     # Messages FROM the bot (bot writes, local assistant reads)
└── ack/        # Processed messages (archived after reading)
```

**Why files, not an API?**

| Approach | Pros | Cons |
|----------|------|------|
| **File-based (chosen)** | Simple, auditable, no extra services, survives restarts | Not real-time (~seconds latency via SSH) |
| **GitHub Issues/Files** | Versioned, accessible from anywhere | Requires `gh` auth, more complex setup |
| **Direct API relay** | Real-time | Opens network attack surface, custom server needed |
| **Telegram relay** | Always visible | Messages get lost in chat noise, no structure |

File-based pipelines are the simplest option that works. No extra services, no network exposure, no dependencies beyond SSH.

### 13.2 Directory Setup

```bash
# On the VPS (as the openclaw user):
mkdir -p ~/.openclaw/pipeline/{inbox,outbox,ack}
chmod 700 ~/.openclaw/pipeline
```

### 13.3 Message Format

Messages are JSON files with a timestamped filename for natural ordering:

```json
{
  "id": "20260220-143000-a1b2c3d4",
  "from": "local-assistant",
  "to": "bot",
  "timestamp": "2026-02-20T14:30:00Z",
  "type": "task",
  "subject": "Summarize today's Lattice posts",
  "body": "Compile and summarize all autonomous engagement posts from today.",
  "priority": "normal",
  "replyTo": null
}
```

**Message types:**

| Type | Direction | Purpose |
|------|-----------|---------|
| `task` | local → bot | Delegate work to the bot |
| `query` | local → bot | Ask the bot a question |
| `notification` | either | Informational, no response expected |
| `escalation` | bot → local | Bot can't handle something, needs local tools |
| `status` | bot → local | Progress report on a running task |

**Filename convention:** `YYYYMMDD-HHMMSS-<type>-<slug>.json`

### 13.4 Pipeline Scripts

Three management scripts handle the pipeline from your local machine via SSH:

**Send a message to the bot:**
```bash
#!/usr/bin/env bash
# pipeline-send: Send a message to bot's inbox
# Usage: ./send.sh <type> <subject> <body> [priority]

PIPELINE_DIR="~/.openclaw/pipeline"
SSH_HOST="your-vps-alias"

TYPE="${1:?Usage: send.sh <type> <subject> <body> [priority]}"
SUBJECT="${2:?Missing subject}"
BODY="${3:?Missing body}"
PRIORITY="${4:-normal}"

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
ID="${TIMESTAMP}-$(head -c 4 /dev/urandom | xxd -p)"
FILENAME="${TIMESTAMP}-${TYPE}-$(echo "$SUBJECT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 30).json"

MESSAGE=$(cat <<EOF
{
  "id": "${ID}",
  "from": "local-assistant",
  "to": "bot",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "type": "${TYPE}",
  "subject": "${SUBJECT}",
  "body": "${BODY}",
  "priority": "${PRIORITY}",
  "replyTo": null
}
EOF
)

ssh "$SSH_HOST" "cat > '${PIPELINE_DIR}/inbox/${FILENAME}'" <<< "$MESSAGE"
echo "Sent: ${FILENAME}"
```

**Read messages from the bot:**
```bash
#!/usr/bin/env bash
# pipeline-read: Read messages from bot's outbox
# Usage: ./read.sh [--peek] [--clear]

PIPELINE_DIR="~/.openclaw/pipeline"
SSH_HOST="your-vps-alias"

MODE="read"
[[ "${1:-}" == "--peek" ]] && MODE="peek"
[[ "${1:-}" == "--clear" ]] && MODE="clear"

FILES=$(ssh "$SSH_HOST" "ls -1 '${PIPELINE_DIR}/outbox/' 2>/dev/null | grep '.json$'" || true)

if [[ -z "$FILES" ]]; then
    echo "No messages from bot."
    exit 0
fi

while IFS= read -r file; do
    echo "--- ${file} ---"
    ssh "$SSH_HOST" "cat '${PIPELINE_DIR}/outbox/${file}'"
    if [[ "$MODE" == "clear" ]]; then
        ssh "$SSH_HOST" "mv '${PIPELINE_DIR}/outbox/${file}' '${PIPELINE_DIR}/ack/${file}'"
    fi
done <<< "$FILES"
```

**Check pipeline status:**
```bash
#!/usr/bin/env bash
# pipeline-status: Check queue depths
# Usage: ./status.sh

ssh "$SSH_HOST" "
    echo 'Inbox (pending for bot):' \$(ls -1 ~/.openclaw/pipeline/inbox/*.json 2>/dev/null | wc -l)
    echo 'Outbox (pending for you):' \$(ls -1 ~/.openclaw/pipeline/outbox/*.json 2>/dev/null | wc -l)
    echo 'Acknowledged:' \$(ls -1 ~/.openclaw/pipeline/ack/*.json 2>/dev/null | wc -l)
"
```

### 13.5 How the Bot Reads the Pipeline

The bot reads the inbox via its shell execution capability. Add a system prompt instruction (in `~/.openclaw/agents/main/system.md`) like:

```markdown
## Pipeline
Check ~/.openclaw/pipeline/inbox/ periodically or when asked. Process pending messages
and write responses to ~/.openclaw/pipeline/outbox/ in JSON format. Move processed
inbox messages to ~/.openclaw/pipeline/ack/.
```

Alternatively, use a cron job (Phase 10) to trigger pipeline processing on a schedule:

```bash
openclaw cron add \
  --name "pipeline-check" \
  --cron "*/15 * * * *" \
  --session isolated \
  --message "Check ~/.openclaw/pipeline/inbox/ for pending messages. Process any found and write responses to outbox." \
  --model "anthropic/claude-haiku-4-5"
```

### 13.6 Security Considerations

- **SSH is the transport.** Pipeline messages travel over your existing SSH connection — no new ports, no new attack surface.
- **File permissions matter.** The pipeline directory should be `700` — only the `openclaw` user can read/write.
- **Message content may be sensitive.** Task descriptions, code snippets, and architectural context flow through the pipeline. Treat it like any other credential-adjacent data.
- **The ack/ directory grows.** Add periodic cleanup — `find ~/.openclaw/pipeline/ack/ -mtime +30 -delete` in a cron job.
- **No authentication on messages.** Anyone with SSH access to the VPS can write to the inbox. If multiple users have VPS access, consider adding a `from` field validation.

### 13.7 Summary

The pipeline turns your bot from a standalone chatbot into one node of a distributed assistant system. Local → bot for delegation, bot → local for escalation. File-based means zero new infrastructure. Combine with cron (Phase 10) for automated pipeline processing.

---

## 14. Phase 12 — Cost Monitoring

Running a Claude-powered bot means ongoing API costs. Monitoring them prevents surprises and identifies optimization opportunities.

### 14.1 Built-in Usage Commands

OpenClaw includes session-level cost visibility out of the box. Use these in your Telegram chat with the bot:

| Command | What It Shows |
|---------|--------------|
| `/status` | Current session model, context usage, last response I/O tokens, estimated cost |
| `/usage off` | Disable per-response usage footer |
| `/usage tokens` | Show token counts after each response |
| `/usage full` | Show full breakdown: tokens, estimated cost, model |
| `/usage cost` | Local cost summary from session logs |
| `/context list` | Token breakdown per loaded file, tool, and system prompt |
| `/context detail` | Detailed per-item context analysis |

```bash
# From the CLI (not Telegram):
openclaw status --usage    # Provider quota windows and rate limit status
```

**Note:** `/usage full` is session-level — it must be typed in each new session. There is no global config key to enable it by default.

### 14.2 What to Monitor

| Metric | Why It Matters | How to Check |
|--------|---------------|-------------|
| **Per-message tokens** | Identifies bloated context or large responses | `/usage full` in Telegram |
| **Cron job costs** | Autonomous engagement is a fixed recurring cost | Parse `~/.openclaw/cron/runs/<jobId>.jsonl` |
| **Context size growth** | Sessions that accumulate context get expensive fast | `/context list` |
| **Bootstrap overhead** | System prompt + workspace files re-injected on every message | `/context detail` — look for workspace files |
| **Memory search tokens** | Each memory retrieval adds tokens to the context | Monitor `memorySearch.query.maxResults` setting |

### 14.3 Third-Party Monitoring Tools

For continuous dashboard monitoring beyond the built-in commands:

| Tool | What It Does | Install |
|------|-------------|---------|
| **ClawMetry** | Real-time dashboard — per-session cost, sub-agent activity, tool calls | `pipx install clawmetry` (Ubuntu 24.04+) |
| **ClawWatcher** | Dashboard for token usage, cost per model, skill activity | Community project |
| **tokscale** | CLI for tracking token usage from OpenClaw and other tools | `npm install -g tokscale` |

**ClawMetry setup:**
```bash
# Install (Ubuntu 24.04 — use pipx per PEP 668)
pipx install clawmetry

# Run as a systemd user service (loopback only)
# Create ~/.config/systemd/user/clawmetry.service
[Unit]
Description=ClawMetry Dashboard

[Service]
ExecStart=%h/.local/bin/clawmetry --port 8900 --host 127.0.0.1
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now clawmetry
loginctl enable-linger $(whoami)   # Keep service running after logout

# Access via SSH tunnel from your local machine:
ssh -L 8900:127.0.0.1:8900 openclaw@YOUR_VPS_IP
# Then open: http://localhost:8900
```

### 14.4 Cost Baselines

Establish baselines so you can spot anomalies. Here's a reference for estimating monthly costs:

**Per-token pricing (as of early 2026):**

| Model | Input (per MTok) | Output (per MTok) | Cached Read (per MTok) |
|-------|-----------------|-------------------|----------------------|
| Opus 4.6 | $5.00 | $25.00 | $0.50 (90% off) |
| Sonnet 4.6 | $3.00 | $15.00 | $0.30 (90% off) |
| Haiku 4.5 | $1.00 | $5.00 | $0.10 (90% off) |

Cache writes cost 1.25x input (5-min TTL) or 2.0x input (1-hr TTL). Cache reads are 0.1x input — the savings come from the system prompt being re-read (not re-processed) on every message after the first cache write.

**Typical workload cost estimates:**

| Workload | Model | Daily Messages | Estimated Monthly |
|----------|-------|---------------|-------------------|
| Light personal use | Sonnet | ~10 | ~$3-5 |
| Moderate use | Sonnet | ~30 | ~$10-15 |
| Heavy use + cron | Sonnet + Haiku cron | ~50 + 5 cron/day | ~$20-30 |
| Power use + Opus | Opus primary | ~50+ | ~$50-100+ |

### 14.5 Prompt Caching Configuration

Prompt caching is the single highest-impact optimization for a persistent bot. The system prompt (~3,000-5,000 tokens) plus bootstrap files (~10,000+ tokens) are re-sent on every message. With caching, subsequent messages pay 90% less for this repeated context.

**Requirement:** Prompt caching only works with API key auth, not setup-token (subscription) auth. See Phase 2 for the API key setup instructions.

```json
{
  "agents": {
    "defaults": {
      "models": {
        "anthropic/claude-sonnet-4": {
          "params": {
            "cacheRetention": "long"
          }
        }
      },
      "heartbeat": {
        "every": "55m"
      }
    }
  }
}
```

The heartbeat at 55 minutes keeps the cache warm within the 60-minute TTL. Without it, idle sessions lose their cache and the next message pays full input price.

### 14.6 Optimization Settings

These config changes reduce per-message token overhead without affecting functionality:

**Bootstrap file injection:**

| Setting | Default | Recommended | Effect |
|---------|---------|-------------|--------|
| `bootstrapMaxChars` | 20,000 | 10,000 | Community reports no functionality loss at 10K |
| `bootstrapTotalMaxChars` | 150,000 | 50,000 | Caps total bootstrap injection per message |
| AGENTS.md length | Varies | 20-60 lines max | Shorter personality prompt = less per-message cost |

**Context compaction:**

```json
{
  "compaction": {
    "memoryFlush": {
      "enabled": true,
      "softThresholdTokens": 40000
    }
  },
  "contextPruning": {
    "mode": "cache-ttl",
    "ttl": "6h",
    "keepLastAssistants": 3
  }
}
```

Compaction itself costs tokens (it's an LLM summarization call) but prevents the much larger cost of unbounded context growth in long Telegram sessions.

**Memory search tuning:**

Current config: 6 chunks × ~400 tokens = ~2,400 tokens per query. For cron tasks that don't need deep recall, reduce `maxResults` to 2-3 chunks. Raise `minScore` above 0.35 to filter low-relevance results.

### 14.7 Optimization Roadmap

Prioritized by impact and effort. Items marked with checkmarks are already implemented.

**Tier 1 — Quick wins (config changes only):**

| # | Action | Savings | Status |
|---|--------|---------|--------|
| 1 | Switch Lattice cron to Haiku | ~80% on cron costs | Done (Phase 10) |
| 2 | Enable `/usage full` for baseline monitoring | Visibility | Ready |
| 3 | Reduce `bootstrapMaxChars` to 10,000 | ~15% total input | Ready |
| 4 | Trim system prompt / AGENTS.md to <60 lines | 10-20% input | Ready |
| 5 | Disable extended thinking for cron | Variable | Done (Phase 10) |

**Tier 2 — Medium-term (auth/architecture changes):**

| # | Action | Savings | Status |
|---|--------|---------|--------|
| 6 | Switch to API key auth | Enables caching | Decided, not yet done |
| 7 | Enable prompt caching (`cacheRetention: "long"`) | 50-90% input | Blocked by #6 |
| 8 | Switch default model to Sonnet | 40% overall | Ready |
| 9 | Install ClawMetry | Monitoring | Ready |
| 10 | Configure context pruning | Variable | Ready |

**Tier 3 — Advanced (code/architecture changes):**

| # | Action | Savings | Effort |
|---|--------|---------|--------|
| 11 | Rule-based model routing (keyword → Haiku/Sonnet/Opus) | 60-70% | 2-4 hrs |
| 12 | Pre-generate Lattice posts via Batch API | 90%+ on cron | 2-4 hrs |
| 13 | Reduce memory chunks for cron tasks specifically | ~20% per cron | 1-2 hrs |

**Combined impact (Tier 1 + 2):** 70-85% reduction in total token costs.

### 14.8 Cron Cost Tracking

Each cron run logs its activity. To track per-job costs over time:

```bash
# Cron run logs (one JSONL file per job)
ls ~/.openclaw/cron/runs/

# Parse a job's runs for token counts
cat ~/.openclaw/cron/runs/<jobId>.jsonl | jq '.usage'
```

For a simple daily cost report, create a script that sums token usage across all cron runs for the day and multiplies by your model's rate.

### 14.9 Summary

Start with `/usage full` in every session to build intuition for your costs. Install ClawMetry when you want a dashboard. The biggest savings come from model tiering and prompt caching — not from micro-optimizing individual messages. With API key auth + caching + Haiku cron, expect 70-85% reduction over the uncached Opus baseline.

---

## 15. Security Threat Model

### 15.1 Attack Surfaces

| Surface | Threat | Mitigation |
|---------|--------|------------|
| **Gateway port** | External access if binding fails | Loopback + firewall + verification cron |
| **Telegram input** | Prompt injection via DM | Pairing (owner-only), system prompt hardening |
| **Anthropic API** | API key theft | Env var in systemd, 0600 permissions |
| **OpenClaw updates** | Supply chain compromise | Pin versions, review changelogs |
| **ClawHub plugins** | Malicious skills | Whitelist-only, audit before install |
| **mDNS discovery** | Network reconnaissance | mDNS disabled |
| **Memory database** | Data exfiltration | File permissions, encrypted disk |
| **Gateway tool** | AI self-reconfiguration | `gateway` in deny list |
| **Cron tool** | AI creating rogue scheduled tasks | Deny `cron` or monitor `cron list` |
| **Pipeline inbox** | Unauthorized message injection via SSH | File permissions 700, SSH key auth only |
| **Cost overrun** | Unbounded token spend from heavy use or rogue cron | Monitor with `/usage full`, set model tiers |
| **In-process skills** | Full process/memory/API key access | No community plugins by default |

### 15.2 Known CVEs

| CVE | Severity | Description | Status |
|-----|----------|-------------|--------|
| CVE-2026-25253 | 8.8 (High) | Control UI trusts `gatewayURL` query param | Patched in v2026.1.29 |
| CVE-2026-24763 | High | Command injection | Patched |
| CVE-2026-25157 | High | Command injection | Patched |

**Ensure you install OpenClaw version >= 2026.1.29.**

### 15.3 Incident Response

If you suspect compromise:

1. **Immediate:** `systemctl stop openclaw`
2. **Assess:** Check logs for unauthorized commands, outbound connections
3. **Rotate:** Change all API keys and tokens
4. **Audit:** `openclaw security audit --deep`
5. **Restore:** From known-good backup if needed

---

## 16. Configuration Reference

Complete `openclaw.json` with all recommended settings:

```jsonc
{
  "logging": {
    "redactSensitive": "tools",
    "redactPatterns": [
      "sk-ant-[\\w-]+",
      "\\d{5,}:[A-Za-z0-9_-]+"
    ]
  },

  "agents": {
    "defaults": {
      "models": { "anthropic/claude-sonnet-4-6": {} },
      "memorySearch": {
        "sources": ["memory"],
        "provider": "local",
        "store": { "vector": { "enabled": true } },
        "query": {
          "maxResults": 6,
          "minScore": 0.35,
          "hybrid": {
            "vectorWeight": 0.7,
            "textWeight": 0.3,
            "candidateMultiplier": 4,
            "mmr": { "enabled": true, "lambda": 0.7 },
            "temporalDecay": { "enabled": true, "halfLifeDays": 30 }
          }
        }
      },
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    }
  },

  "tools": {
    "profile": "full",
    "deny": ["gateway", "nodes", "sessions_spawn", "sessions_send"],
    "web": {
      "search": { "enabled": true },
      "fetch": { "enabled": true }
    },
    "elevated": { "enabled": false },
    "exec": { "security": "full", "ask": "off" }
  },

  "messages": { "ackReactionScope": "group-mentions" },
  "commands": { "native": "auto", "nativeSkills": "auto", "config": false },
  "session": { "dmScope": "per-channel-peer" },

  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "botToken": "REDACTED",
      "groups": {},
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },

  "discovery": { "mdns": { "mode": "off" } },

  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "controlUi": { "dangerouslyDisableDeviceAuth": false },
    "auth": {
      "mode": "token",
      "token": "REDACTED",
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "trustedProxies": [],
    "tailscale": { "mode": "off", "resetOnExit": false }
  },

  "plugins": {
    "enabled": true,
    "slots": { "memory": "memory-core" },
    "entries": {
      "telegram": { "enabled": true },
      "device-pair": { "enabled": true },
      "memory-core": { "enabled": true },
      "memory-lancedb": { "enabled": false }
    }
  }
}
```

---

## 17. Runbook: Common Operations

### Start / Stop / Restart

```bash
sudo systemctl start openclaw
sudo systemctl stop openclaw
sudo systemctl restart openclaw
sudo systemctl status openclaw
```

### View Logs

```bash
journalctl -u openclaw -f          # Live logs
openclaw logs --follow              # OpenClaw's own logs
journalctl -u openclaw -n 100      # Last 100 lines
```

### Update OpenClaw

```bash
sudo systemctl stop openclaw
sudo -u openclaw npm update -g openclaw
openclaw --version
sudo -u openclaw openclaw security audit --fix
sudo systemctl start openclaw
ss -tlnp | grep 18789              # Verify binding after restart
```

### Check Backup Health

```bash
crontab -l | grep backup
ls -lt ~/.openclaw/backups/ | head -5
tail -10 ~/.openclaw/logs/backup.log
```

### Emergency Shutdown

```bash
sudo systemctl stop openclaw
sudo ufw deny out to any port 18789
```

### Access Control UI (via SSH tunnel)

```bash
ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP
# Then open: http://localhost:18789
```

---

*Based on analysis of official OpenClaw docs (docs.openclaw.ai), security audits, and CVE databases. Config schemas verified against the official configuration reference.*
