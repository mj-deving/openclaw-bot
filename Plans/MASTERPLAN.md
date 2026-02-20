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
11. [Phase 9 — ClawHub Skills (Optional)](#11-phase-9--clawhub-skills-optional)
12. [Security Threat Model](#12-security-threat-model)
13. [Configuration Reference](#13-configuration-reference)
14. [Runbook: Common Operations](#14-runbook--common-operations)

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

### 4.1b Fallback: Direct API Key

If setup-token fails, create a separate Anthropic API account at `console.anthropic.com` with pay-per-token pricing:

```bash
# Option A: Environment variable (preferred for secrets)
export ANTHROPIC_API_KEY="sk-ant-..."

# Option B: Edit config directly
openclaw config set provider.name anthropic
openclaw config set provider.apiKey "sk-ant-..."
```

**Note:** The API account is separate from your Claude Max subscription. Costs are per-token (~$3/MTok input, ~$15/MTok output for Sonnet).

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

## 11. Phase 9 — ClawHub Skills (Optional)

**Not required for initial deployment.** Only consider after the bot is stable and you've identified specific needs.

### 11.1 The ClawHavoc Risk

The ClawHavoc campaign (Feb 2026) revealed supply chain problems in the ClawHub ecosystem:

| Metric | Value |
|--------|-------|
| Confirmed malicious skills | 824+ |
| Single worst actor | hightower6eu — 314 malicious skills |
| Malware type | AMOS macOS infostealer, credential theft |
| Malicious rate at peak | ~20% of audited packages |

**Critical facts:**
- **Skills run IN-PROCESS with the Gateway.** A malicious skill has full access to the bot's process, memory, and API keys. There is NO sandboxing.
- **Prompt injection is NOT scanned for.** VirusTotal catches binary malware, not adversarial prompts.
- **npm lifecycle scripts execute during `clawhub install`.** Classic supply chain vector.

### 11.2 Vetting Checklist

Before installing ANY skill:

- [ ] Author is known/trusted (established community member with 1K+ downloads)
- [ ] No VirusTotal flags
- [ ] No ClawHavoc association
- [ ] Manually read SKILL.md — no `eval()`, `fetch()` to unknown hosts, `exec()`, obfuscated code
- [ ] No npm lifecycle scripts in `package.json`
- [ ] Does not require denied tools
- [ ] Pin exact version after install
- [ ] Run `openclaw security audit --deep` after installation

### 11.3 Recommended Approach

Keep installed skills to an absolute minimum. The bot's power comes from the Claude model plus full tool access, not from community skills. `web_search` (built-in) covers most research needs.

---

## 12. Security Threat Model

### 12.1 Attack Surfaces

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
| **In-process skills** | Full process/memory/API key access | No community plugins by default |

### 12.2 Known CVEs

| CVE | Severity | Description | Status |
|-----|----------|-------------|--------|
| CVE-2026-25253 | 8.8 (High) | Control UI trusts `gatewayURL` query param | Patched in v2026.1.29 |
| CVE-2026-24763 | High | Command injection | Patched |
| CVE-2026-25157 | High | Command injection | Patched |

**Ensure you install OpenClaw version >= 2026.1.29.**

### 12.3 Incident Response

If you suspect compromise:

1. **Immediate:** `systemctl stop openclaw`
2. **Assess:** Check logs for unauthorized commands, outbound connections
3. **Rotate:** Change all API keys and tokens
4. **Audit:** `openclaw security audit --deep`
5. **Restore:** From known-good backup if needed

---

## 13. Configuration Reference

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

## 14. Runbook: Common Operations

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
