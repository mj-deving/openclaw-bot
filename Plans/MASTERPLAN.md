# OpenClaw Telegram Bot (Gregor) -- MASTERPLAN

**Target:** Capable OpenClaw instance on VPS, Telegram-first, powered by Anthropic Claude
**Owner:** Marius Jonathan Jauernik
**Created:** 2026-02-18
**Updated:** 2026-02-20
**Status:** Phases 0-7 deployed and operational. Phase 8 (backups) deployed. Lattice engagement active.

> **Guiding philosophy:** *As capable as possible, while as secure as necessary.*
>
> Security exists to protect capability, not to prevent it. Every deny-list entry, every disabled feature must justify itself against the question: "Does removing this capability make Gregor meaningfully safer, or just less useful?" The answer determines the posture.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Phase 0 -- VPS Preparation](#2-phase-0--vps-preparation)
3. [Phase 1 -- OpenClaw Installation](#3-phase-1--openclaw-installation)
4. [Phase 2 -- Anthropic Provider Configuration](#4-phase-2--anthropic-provider-configuration)
5. [Phase 3 -- IRC Channel Setup (SKIPPED -- Telegram-first pivot)](#5-phase-3--irc-channel-setup-skipped)
6. [Phase 4 -- Security Hardening (Capability-First)](#6-phase-4--security-hardening-capability-first)
7. [Phase 5 -- Bot Identity & Behavior](#7-phase-5--bot-identity--behavior)
8. [Phase 6 -- Memory & Persistence](#8-phase-6--memory--persistence)
9. [Phase 7 -- Systemd Service & Auto-Recovery](#9-phase-7--systemd-service--auto-recovery)
10. [Phase 8 -- Monitoring, Backups & Log Hygiene](#10-phase-8--monitoring-backups--log-hygiene)
11. [Phase 8b -- Lattice Engagement System](#11-phase-8b--lattice-engagement-system)
12. [Phase 9 -- ClawHub Plugins (Future, Audited Only)](#12-phase-9--clawhub-plugins-future-audited-only)
13. [Phase 10 -- Our Repo Structure](#13-phase-10--our-repo-structure)
14. [Security Threat Model](#14-security-threat-model)
15. [Configuration Reference](#15-configuration-reference)
16. [Runbook: Common Operations](#16-runbook-common-operations)
17. [Decision Log](#17-decision-log)
18. [Open Questions -- Answered](#18-open-questions--answered)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                          VPS (213.199.32.18)                  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                OpenClaw Gateway v2026.2.17              │  │
│  │                (Node.js 22.x process)                   │  │
│  │                Port 18789 (loopback ONLY)              │  │
│  │                                                        │  │
│  │  ┌──────────┐  ┌────────┐  ┌─────────┐  ┌──────────┐ │  │
│  │  │ Telegram │  │ Agent  │  │ Memory  │  │ Cron     │ │  │
│  │  │ Bot API  │  │ Runtime│  │ SQLite  │  │ Lattice  │ │  │
│  │  │ (paired) │  │ Opus   │  │ + vec   │  │ 5x/day   │ │  │
│  │  └────┬─────┘  └───┬────┘  └────┬────┘  └────┬─────┘ │  │
│  │       │            │            │              │       │  │
│  │       │       ┌────┴─────┐  ┌───┴──────┐  ┌───┴────┐ │  │
│  │       │       │ Anthropic│  │ Local    │  │Lattice │ │  │
│  │       │       │ Claude   │  │ Embeddings│ │ API    │ │  │
│  │       │       │ API      │  │ gemma-300m│ │        │ │  │
│  │       │       └──────────┘  └──────────┘  └────────┘ │  │
│  └───────┼───────────────────────────────────────────────┘  │
│          │                                                   │
│          │ HTTPS (Bot API polling)                            │
│          ▼                                                   │
│  api.telegram.org   api.anthropic.com   lattice.demos.global │
│                                                              │
│  ~/.openclaw/pipeline/ ◄──── Isidore ↔ Gregor messaging      │
│  SSH tunnel ◄──── Local machine (management)                  │
└──────────────────────────────────────────────────────────────┘
```

**Key architectural decisions:**
- Gateway binds to **loopback only** (127.0.0.1) -- never exposed to the internet
- Outbound connections: Telegram Bot API, Anthropic API, Lattice (Demos) API
- Management access via **SSH tunnel only** -- no Tailscale, no public Control UI
- Plugins enabled selectively (memory-core, telegram, device-pair) -- not from ClawHub
- Single channel: **Telegram** (personal, paired to owner via device pairing)
- Isidore ↔ Gregor pipeline via `~/.openclaw/pipeline/` on VPS (inbox/outbox/ack)
- Gregor = always-on assistant (VPS); Isidore = session-based mentor (local Claude Code)
- **Posture:** Capability-first — tools.profile "full" with targeted deny list, not blanket lockdown

---

## 2. Phase 0 -- VPS Preparation

### 2.1 System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| RAM | 2 GB | 4 GB |
| Disk | 10 GB | 20 GB SSD |
| CPU | 1 vCPU | 2 vCPU |
| Network | IPv4, outbound to Anthropic + Telegram + Lattice | Same |

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
# Do NOT open port 18789 -- gateway stays on loopback
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

## 3. Phase 1 -- OpenClaw Installation

### 3.1 Install as the Dedicated User

```bash
# Switch to the openclaw user
sudo -u openclaw -i

# Install OpenClaw globally (MUST be >= 2026.1.29 for CVE patches)
npm install -g openclaw@latest
# Verify version is >= 2026.1.29 (patches CVE-2026-25253, CVE-2026-24763, CVE-2026-25157)
# If not, pin explicitly: npm install -g openclaw@2026.1.29

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
# Should show: 127.0.0.1:18789 -- NOT 0.0.0.0:18789

# Stop it (we'll configure before running for real)
openclaw gateway stop
```

---

## 4. Phase 2 -- Anthropic Provider Configuration

### 4.1 Authentication via Setup-Token (Claude Max Subscription)

Your Claude Max subscription can directly power OpenClaw via the **setup-token** method. No separate API account or API key purchase needed.

```bash
# Step 1: Generate a setup token via Claude Code CLI (on any machine with Claude Code)
claude setup-token

# Step 2: On the VPS (as the openclaw user), register it with OpenClaw
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
- Anthropic's terms note: "For production or multi-user workloads, API keys are usually the safer choice." For a personal Telegram bot, setup-token is fine.
- **Note (Jan 2026):** Anthropic may have restricted setup-token for non-Claude-Code use since ~Jan 9, 2026. If setup-token auth fails, proceed immediately to the API key fallback in 4.1b.

### 4.1b Fallback: Direct API Key (if setup-token doesn't work)

If setup-token fails, you can create a separate Anthropic API account at `console.anthropic.com` with pay-per-token pricing:

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
# Verify the provider is working
openclaw models status
# Should show: anthropic -- authenticated (setup-token)

# Test a query
openclaw chat --once "Hello, respond with just 'OK'"
# Should get a response from Claude
```

### 4.3 Model Selection

```bash
# Set the default model
openclaw config set provider.model "claude-opus-4"
```

| Model | Best For | Cost |
|-------|----------|------|
| `claude-opus-4` | Complex reasoning, long context | Highest |
| `claude-sonnet-4` | Good balance of quality/cost | Medium |
| `claude-haiku-4` | Fast responses, simple queries | Lowest |

**Selected:** `claude-opus-4-6` for Gregor. Best reasoning quality for a personal assistant. Model selection algorithm is a future TODO -- may dynamically switch models based on query complexity later.

### 4.4 Rate Limits & Cost Management

With setup-token (Max subscription), your rate limits are tied to your subscription tier. For a Telegram bot with cron jobs:

```jsonc
// In ~/.openclaw/openclaw.json
{
  "provider": {
    "name": "anthropic",
    "model": "claude-opus-4",
    // Restrict token usage per response
    "maxTokens": 1024
  }
}
```

Capping output tokens keeps responses concise and costs predictable. Telegram messages can be up to 4096 chars.

---

## 5. Phase 3 -- IRC Channel Setup (SKIPPED)

> **PIVOTED:** During deployment (2026-02-19), we pivoted to a Telegram-first architecture. IRC was never deployed. Telegram proved sufficient as the sole channel — personal, mobile-accessible, paired to owner, with richer message format. IRC remains documented below for reference if community-facing presence is needed later.

<details>
<summary>Original IRC plan (preserved for reference)</summary>

### 5.1 Pre-Requisites on Libera.Chat

Before connecting the bot, you need to:

1. **Register a nick** for the bot on Libera.Chat
2. **Register a channel** (if creating your own) or get permission to bring a bot to an existing channel

```bash
# From any IRC client, connect to irc.libera.chat:6697 (TLS)
# Register the bot's nick:
/msg NickServ REGISTER <password> <your-email>
# Verify via email link
```

**Bot nick:** `Gregor` (decided). Register this nick on Libera.Chat before proceeding.

**Pre-requisite:** Register YOUR personal IRC nick first, then register `Gregor` as the bot nick.

### 5.2 Add the IRC Channel to OpenClaw

```bash
# Add IRC as a channel
openclaw channels add --channel irc --account default
```

### 5.3 IRC Configuration

Edit `~/.openclaw/openclaw.json` -- the IRC section:

```jsonc
{
  "channels": {
    "irc": {
      // Connection
      "host": "irc.libera.chat",
      "port": 6697,
      "tls": true,
      "nick": "Gregor",

      // Authentication with NickServ
      "nickserv": {
        "enabled": true,
        "password": "YOUR_NICKSERV_PASSWORD"
      },

      // Channels to join
      "channels": ["#gregor"],

      // Access control (CRITICAL for security)
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",       // FLAT STRING (not an object!)
      "groupAllowFrom": [
        "yournick!*@*"                  // Global channel sender allowlist
      ],

      // Per-channel overrides
      "groups": {
        "#gregor": {
          "allowFrom": ["yournick!*@*"],
          "requireMention": true         // Bot only responds when mentioned
        }
      },

      // Per-sender tool restrictions (fine-grained control)
      "toolsBySender": {
        "yournick!*@*": { "profile": "messaging" },
        "*": { "profile": "minimal" }    // Everyone else gets minimal
      },

      // Who can DM the bot
      "allowFrom": [
        "yournick!*@*"  // Only you can trigger the bot initially
      ]
    }
  }
}
```

### 5.4 Environment Variable Overrides

For secrets, prefer env vars over config file values:

```bash
export IRC_NICKSERV_PASSWORD="your-nickserv-password"
```

Full list of IRC env overrides:

| Variable | Purpose |
|----------|---------|
| `IRC_HOST` | IRC server hostname |
| `IRC_PORT` | Connection port |
| `IRC_TLS` | Enable TLS (`true`/`false`) |
| `IRC_NICK` | Bot nickname |
| `IRC_USERNAME` | IRC username |
| `IRC_REALNAME` | IRC realname field |
| `IRC_PASSWORD` | Server password (if needed) |
| `IRC_CHANNELS` | Comma-separated channel list |
| `IRC_NICKSERV_PASSWORD` | NickServ auth password |

### 5.5 Access Control Deep-Dive

OpenClaw IRC uses a **two-gate** model:

**Gate 1 -- Channel access:** Which IRC channels can the bot listen in?
- `groupPolicy: "allowlist"` (flat string) + `channels: ["#gregor"]`
- Bot ignores messages from channels not in the `channels` list

**Gate 2 -- Sender access:** Who within those channels can trigger the bot?
- `groups."#channel".allowFrom: ["yournick!*@*"]` -- per-channel hostmask filter
- `groupAllowFrom: ["yournick!*@*"]` -- global channel sender allowlist
- `groups."#channel".requireMention: true` -- bot only responds when mentioned

**Gate 3 -- Per-sender tool restrictions:**
- `toolsBySender` -- assigns tool profiles per hostmask (most restrictive wins)

**Start restrictive, loosen later.** Begin with just your own nick in `allowFrom` and a single channel. Expand after you've verified behavior.

### 5.6 Testing the IRC Connection

```bash
# Start the gateway
openclaw gateway start

# Watch logs for IRC connection
openclaw logs --follow

# You should see:
# [IRC] Connecting to irc.libera.chat:6697 (TLS)
# [IRC] Identified with NickServ
# [IRC] Joined #gregor
```

Then from your regular IRC client, mention the bot in the channel:
```
<you> Gregor: hello, are you working?
<Gregor> Hello! I'm here and operational.
```

</details>

---

## 5b. Phase 3b -- Telegram Channel Setup ✅ DEPLOYED

Telegram is Gregor's **primary and sole channel** — personal, mobile-accessible, paired to owner. Bot: `@gregor_openclaw_bot`.

### 5b.1 Create a Telegram Bot via @BotFather

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a name (e.g., "Gregor (OpenClaw)") and username (e.g., `gregor_openclaw_bot`)
4. BotFather gives you a **bot token** (format: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
5. **Save this token securely** -- it goes in the systemd env file, NOT in openclaw.json

### 5b.2 Telegram Configuration

```jsonc
{
  "channels": {
    "telegram": {
      "enabled": true,

      // Access control -- CRITICAL
      "dmPolicy": "pairing",
      "allowFrom": [],  // Empty = pairing mode (you pair via first message)
      // NOTE: allowFrom takes NUMERIC user IDs only (not @usernames!)
      // After pairing, add your numeric ID here for explicit allowlist

      // Group policy (if you add the bot to groups later)
      "groupPolicy": "allowlist",       // FLAT STRING (not an object!)
      "groups": {}                       // No groups initially
    }
  }
}
```

### 5b.3 Bot Token as Environment Variable

Add to `/etc/openclaw/env`:

```bash
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
```

### 5b.4 Pairing Process

Telegram uses a **pairing** model -- the first person to DM the bot becomes the paired user:

1. Start the gateway: `openclaw gateway start`
2. Open Telegram, find your bot (`@gregor_openclaw_bot`)
3. Send any message (e.g., "hello")
4. OpenClaw generates a pairing code shown in the gateway logs
5. Confirm the pairing via the gateway logs or Control UI (via SSH tunnel)
6. Once paired, only YOUR Telegram account can interact with the bot

**This is why `dmPolicy: "pairing"` is recommended for Telegram** -- it's a one-time setup that locks the bot to your account. After pairing, no one else can DM the bot.

### 5b.5 Telegram Command Interface

Gregor exposes structured commands for Telegram interactions:

| Command | Purpose |
|---------|---------|
| `/ask <question>` | General question -- Gregor answers using Claude |
| `/research <topic>` | Web search + summarize -- uses allowed tools |
| `/status` | Report running tasks, pipeline status, uptime |
| `/escalate <description>` | Push task to Isidore pipeline (writes to `.pipeline/gregor-to-isidore/`) |
| `/review <github-url>` | Code review -- reads PR/commit via `gh` CLI, gives feedback |
| `/tasks` | Show active task board from `.pipeline/shared/active-tasks.md` |

These commands are implemented via the system prompt -- OpenClaw processes them as natural language patterns, not as traditional bot commands.

### 5b.6 Telegram Security Model

| Aspect | Detail |
|--------|--------|
| **Auth model** | Pairing (cryptographic user ID — locked to owner after first DM) |
| **Encryption** | TLS to Telegram API (E2E only in secret chats, not bots) |
| **Message format** | Rich text, markdown, media, up to 4096 chars |
| **Attack surface** | DM prompt injection (but only from paired user — minimal risk) |
| **Rate limits** | Telegram Bot API rate limits (30 msg/sec) |
| **Stream mode** | `partial` — responses stream as they generate |

---

## 6. Phase 4 -- Security Hardening (Capability-First) ✅ DEPLOYED

> **Philosophy shift (2026-02-20):** Originally "Maximum Lockdown" — deny everything, enable minimally. Now **"As capable as possible, while as secure as necessary."** The threat landscape (40K+ exposed instances, ClawHub supply chain attacks, real CVEs) is real, but the response is proportional: lock down what's dangerous, enable what's useful. Gregor runs with `tools.profile: "full"` and a targeted deny list, not blanket restriction.

### 6.1 Gateway Binding

```jsonc
{
  "gateway": {
    "bind": "loopback",        // ONLY 127.0.0.1
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "GENERATED_DURING_ONBOARD",  // Never share this
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "controlUi": {
      "dangerouslyDisableDeviceAuth": false  // NEVER set to true
    },
    "tailscale": {
      "mode": "off"  // No tailscale exposure
    }
  }
}
```

**Why loopback matters:** There's a known bug where loopback failure silently falls back to `0.0.0.0` (all interfaces). After starting, ALWAYS verify:

```bash
ss -tlnp | grep 18789
# MUST show 127.0.0.1:18789, NOT 0.0.0.0:18789
```

Add this check to your monitoring (Phase 8).

### 6.2 Single Channel -- Telegram Only

Only Telegram is enabled. All other channels disabled:

```jsonc
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "groups": {},
      "streamMode": "partial"
    }
    // All others (whatsapp, discord, signal, slack, irc) -- not configured
  }
}
```

### 6.3 Tool Restrictions

Capability-first with targeted denials. Gregor gets full tool access except for self-modification and cross-session operations:

```jsonc
{
  "agents": {
    "defaults": {
      "models": { "anthropic/claude-opus-4-6": {} },
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    }
  },
  "session": {
    "dmScope": "per-channel-peer"     // Isolate sessions per sender per channel
  },
  "tools": {
    "profile": "full",               // Full capability -- Gregor can read, write, exec, search
    "deny": [
      "gateway",            // Prevents AI from modifying its own config (zero-gating risk)
      "nodes",              // No device invocation
      "sessions_spawn",     // No spawning sub-sessions
      "sessions_send"       // No cross-session messaging
    ],
    "web": {
      "search": { "enabled": true },
      "fetch": { "enabled": true }
    },
    "exec": {
      "security": "full",            // Full shell access (needed for Lattice client.mjs, pipeline ops)
      "ask": "off"                    // No confirmation prompts (autonomous cron operation)
    },
    "elevated": {
      "enabled": false                // Elevated tools bypass ALL sandboxing -- keep off
    }
  }
}
```

**What's denied and why:**
- `gateway` — zero-gating on `config.apply`/`config.patch`: AI could reconfigure itself without checks
- `nodes` — no need for device invocation in a single-VPS setup
- `sessions_spawn` / `sessions_send` — Gregor doesn't need to spawn or message other OpenClaw sessions

**What's enabled and why:**
- `tools.profile: "full"` — Gregor needs filesystem access for pipeline ops, Lattice client, memory files
- `exec.security: "full"` — needed for `node client.mjs` (Lattice), shell operations in cron jobs
- `web.search` + `web.fetch` — research capability for answering questions with current information
- `cron` — OpenClaw internal cron runs Lattice engagement 5x/day

### 6.4 Disable Network Discovery

```jsonc
{
  "discovery": {
    "mdns": {
      "mode": "off"         // No mDNS broadcasting
    }
  }
}
```

OpenClaw broadcasts its presence via mDNS by default. This makes it discoverable on local networks. Disable it.

### 6.5 Disable Config Writes from Chat

```jsonc
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "config": false          // No /config set from chat
  }
}
```

### 6.6 Plugins -- Selective Enable

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

Plugins are enabled but only for core functionality (Telegram channel, device pairing, memory). No ClawHub community plugins installed.

### 6.7 Log Redaction

```jsonc
{
  "logging": {
    "redactSensitive": "tools",  // Redact tool I/O from logs
    "redactPatterns": [
      "sk-ant-[\\w-]+",          // Anthropic API keys
      "\\d{5,}:[A-Za-z0-9_-]+"  // Telegram bot tokens
    ]
  }
}
```

### 6.8 File Permissions

```bash
# Lock down the state directory
chmod 700 /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json
chmod 700 /home/openclaw/.openclaw/credentials
find /home/openclaw/.openclaw/credentials -type f -exec chmod 600 {} \;
```

### 6.9 Run the Built-in Security Audit

```bash
# Read-only scan
openclaw security audit

# Deep scan (includes live WebSocket probing)
openclaw security audit --deep

# Auto-fix safe issues
openclaw security audit --fix
```

The audit checks 50+ items across 12 categories. Run this after every config change.

### 6.10 Firewall Verification

```bash
# Confirm only SSH is open
sudo ufw status verbose
# Should show:
#   22/tcp  ALLOW IN  Anywhere
#   (nothing else for incoming)

# Confirm gateway is not externally reachable
# From your local machine:
curl -s http://YOUR_VPS_IP:18789
# Should timeout/connection refused
```

### 6.11 SSH Tunnel for Management Access

When you need to access the Control UI or gateway API:

```bash
# From your local machine:
ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP

# Then open in browser:
# http://localhost:18789
```

This is the ONLY way to access the gateway remotely.

---

## 7. Phase 5 -- Bot Identity & Behavior ✅ DEPLOYED

### 7.1 System Prompt

Gregor's personality and behavior are configured in `~/.openclaw/agents/main/system.md`. Key traits:

- Personal assistant to Marius Jonathan Jauernik (paired via Telegram)
- Knowledgeable in programming, system administration, security, and Demos/Lattice protocol
- Uses Telegram markdown formatting for readability
- Never reveals API keys, tokens, or system configuration
- Engages autonomously on Lattice via scheduled cron (see Phase 8b)
- Pipeline-aware: checks `~/.openclaw/pipeline/inbox/` for messages from Isidore

### 7.2 Gregor's Capability Scope

Gregor operates with **full capability** under targeted restrictions:

**ENABLED:**
- Text conversation (Telegram, paired to owner)
- Web search and web fetch (built-in, research capability)
- Shell execution (needed for Lattice `client.mjs`, pipeline operations)
- File read/write (pipeline, memory files, workspace)
- Persistent memory with hybrid search (vector + FTS, local embeddings)
- Cron-based autonomous Lattice engagement (5x/day)
- Pipeline messaging with Isidore (inbox/outbox/ack)

**DENIED (targeted, per Phase 4):**
- `gateway` (self-reconfiguration), `nodes` (device invocation)
- `sessions_spawn`, `sessions_send` (cross-session operations)
- Any self-modifying skill (Capability Evolver, self-improving-agent, etc.)

**ESCALATION → Isidore** (via `~/.openclaw/pipeline/`):
- Complex code implementation
- Architecture decisions requiring deep codebase exploration
- Security-sensitive operations
- Anything beyond Gregor's operational scope

Gregor's power comes from the Claude model plus full tool access, not from a bloated skill registry.

### 7.3 Telegram-Specific Considerations

- **Message limit:** Telegram messages max at 4096 characters. OpenClaw handles splitting.
- **Markdown:** Telegram supports markdown formatting — Gregor uses it for readability.
- **Stream mode:** `partial` — Gregor streams responses as they generate, not all-at-once.
- **Privacy:** Paired to owner only via `dmPolicy: "pairing"`. No group access.

---

## 8. Phase 6 -- Memory & Persistence ✅ DEPLOYED

### 8.1 Memory Configuration

OpenClaw uses SQLite + sqlite-vec for persistent memory with hybrid search. Database: `~/.openclaw/memory/main.sqlite`. Memory source files: `~/.openclaw/workspace/memory/*.md`.

```jsonc
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "sources": ["memory"],
        "provider": "local",            // Local embeddings via embeddinggemma-300m
        "store": {
          "vector": { "enabled": true }
        },
        "query": {
          "maxResults": 6,
          "minScore": 0.35,
          "hybrid": {
            "vectorWeight": 0.7,
            "textWeight": 0.3,
            "candidateMultiplier": 4,
            "mmr": {
              "enabled": true,
              "lambda": 0.7              // 0=max diversity, 1=max relevance
            },
            "temporalDecay": {
              "enabled": true,
              "halfLifeDays": 30         // 30-day half-life for recency boost
            }
          }
        }
      }
    }
  }
}
```

### 8.2 Embedding Provider -- Local (Deployed)

| Provider | Cost | Privacy | Status |
|----------|------|---------|--------|
| Local (`embeddinggemma-300m`) | Free | Fully private, no API calls | **ACTIVE** |
| OpenAI / Gemini / Voyage | Per-token | Data sent to third-party API | Not used |

**Deployed choice:** Local embeddings via `embeddinggemma-300m` (~329MB GGUF model, auto-downloaded by node-llama-cpp to `~/.node-llama-cpp/models/`). The VPS has 23GB RAM and 8 CPUs — more than sufficient. This aligns with the capability-first philosophy: full vector search capability with zero external API dependency.

**Current state (2026-02-20):** 2/2 files indexed, 5 chunks, 768-dim vectors. Search verified working (e.g., "Lattice protocol" → 0.724 score).

**Note:** `openclaw doctor` shows a cosmetic false-positive about "no local model file found" — this is a detection path mismatch, not a real issue. Runtime works correctly.

### 8.3 Backup Strategy ✅ DEPLOYED

Backup script: `~/scripts/backup.sh` (deployed 2026-02-20). Backs up three things:

1. **Config** → `~/.openclaw/backups/config-YYYYMMDD-HHMMSS.json` (600 perms)
2. **Memory DB** → `~/.openclaw/backups/memory-YYYYMMDD-HHMMSS.sqlite` (600 perms)
3. **Memory files** → `~/.openclaw/backups/memory-files-YYYYMMDD-HHMMSS.tar.gz` (600 perms)

Automatic 30-day retention (older files pruned). Logs to `~/.openclaw/logs/backup.log`.

```bash
# Cron (deployed):
0 3 * * * /home/openclaw/scripts/backup.sh >> /home/openclaw/.openclaw/logs/backup.log 2>&1
```

Sanitized config template committed to repo at `src/config/openclaw.json.example` (all tokens REDACTED). Script source in `src/scripts/backup.sh`.

---

## 9. Phase 7 -- Systemd Service & Auto-Recovery ✅ DEPLOYED

### 9.1 Systemd Unit File

The onboarding wizard creates this, but here's what it should look like for maximum security:

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

# Environment (secrets go here, NOT in openclaw.json)
# Note: If using setup-token auth, ANTHROPIC_API_KEY is not needed
# Environment=ANTHROPIC_API_KEY=sk-ant-...  # Only if using API key fallback
Environment=IRC_NICKSERV_PASSWORD=your-password
Environment=TELEGRAM_BOT_TOKEN=your-telegram-bot-token
Environment=OPENCLAW_STATE_DIR=/home/openclaw/.openclaw

# The actual command
# Official form uses `openclaw gateway --port 18789` (no "start --foreground")
ExecStart=/usr/bin/openclaw gateway --port 18789
ExecStop=/usr/bin/openclaw gateway stop

# Auto-restart on crash
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

### 9.2 Secure the API Key

**Do NOT put the API key in the unit file directly.** Use a systemd credential or environment file:

```bash
# Create a secure environment file
sudo mkdir -p /etc/openclaw
sudo tee /etc/openclaw/env > /dev/null << 'EOF'
# Anthropic auth: setup-token is handled by OpenClaw's credential store (~/.openclaw/credentials/)
# Only uncomment the line below if using API key fallback instead of setup-token:
# ANTHROPIC_API_KEY=sk-ant-...
IRC_NICKSERV_PASSWORD=your-password
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
EOF
sudo chmod 600 /etc/openclaw/env
sudo chown root:openclaw /etc/openclaw/env
```

Then in the unit file, replace the `Environment=` lines with:

```ini
EnvironmentFile=/etc/openclaw/env
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

## 10. Phase 8 -- Monitoring, Backups & Log Hygiene (partially deployed)

### 10.1 Binding Verification Cron

Create a script that checks the gateway hasn't fallen back to 0.0.0.0:

```bash
#!/bin/bash
# /home/openclaw/scripts/verify-binding.sh
if ss -tlnp | grep ':18789' | grep -q '0.0.0.0'; then
    echo "CRITICAL: OpenClaw gateway bound to 0.0.0.0! Stopping."
    systemctl stop openclaw
    # Optionally: send alert (email, webhook, etc.)
fi
```

```bash
chmod +x /home/openclaw/scripts/verify-binding.sh
# Run every 5 minutes
echo "*/5 * * * * /home/openclaw/scripts/verify-binding.sh" | crontab -u openclaw -
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

# Check if process is running
if ! systemctl is-active --quiet openclaw; then
    echo "OpenClaw is down. Restarting..."
    systemctl start openclaw
fi

# Check if gateway responds on loopback
if ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/health | grep -q "200"; then
    echo "Gateway health check failed"
fi
```

### 10.4 Auto-Update with Security Audit

```bash
#!/bin/bash
# /home/openclaw/scripts/auto-update.sh
# Auto-update OpenClaw and run security audit afterward

CURRENT_VERSION=$(openclaw --version 2>/dev/null)
sudo -u openclaw npm update -g openclaw
NEW_VERSION=$(openclaw --version 2>/dev/null)

if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo "$(date): Updated OpenClaw from $CURRENT_VERSION to $NEW_VERSION"
    systemctl restart openclaw
    sleep 5
    # Verify binding after restart
    /home/openclaw/scripts/verify-binding.sh
fi

# Always run security audit (weekly)
openclaw security audit --deep >> /home/openclaw/.openclaw/logs/audit.log 2>&1
```

```bash
chmod +x /home/openclaw/scripts/auto-update.sh
# Weekly: update check + security audit (Sunday 4am)
echo "0 4 * * 0 /home/openclaw/scripts/auto-update.sh >> /home/openclaw/.openclaw/logs/update.log 2>&1" | crontab -u openclaw -
```

### 10.5 Backup Strategy (Deployed)

**Local VPS backups** are handled by `~/scripts/backup.sh` running via cron at 3 AM daily (see Phase 6, Section 8.3).

**Git repo backup** is handled differently than originally planned: instead of a VPS-side git push, the sanitized config template (`src/config/openclaw.json.example`) is maintained in the local `openclaw-bot` repo by Isidore. This is simpler and avoids needing git credentials on the VPS.

Backup files on VPS are retained for 30 days with automatic pruning.

---

## 10b. Phase 8b -- Lattice Engagement System ✅ DEPLOYED

Gregor autonomously engages on the Lattice network (Demos protocol) via OpenClaw's built-in cron system.

### 10b.1 What is Lattice?

Lattice is the social/engagement layer of the Demos protocol — a decentralized governance platform. Gregor participates as an agent with a DID:key identity, posting research insights, commenting on discussions, and building reputation (EXP).

### 10b.2 Cron Schedule

```
37 8,11,15,18,21 * * *  (Europe/Berlin timezone)
```

Five engagements per day, staggered at non-round minutes (`:37`) to avoid bot-like patterns.

### 10b.3 Engagement Principles

- **Quality over volume** — only post/comment when genuinely adding value
- **Stagger activity** — don't dump everything at once
- **Read the room** — check feed activity before posting
- **Technical depth** — leverage Demos docs research for substantive comments
- **Privacy** — never mention the human's name, faith, or personal details

### 10b.4 Architecture

- **Job:** `lattice-engage` (OpenClaw cron job, `sessionTarget: "isolated"`)
- **Client:** `~/.openclaw/workspace/memory/lattice/client.mjs` (API wrapper)
- **Queued posts:** `~/.openclaw/workspace/memory/lattice/queued-posts.json`
- **Research:** `~/.openclaw/workspace/memory/lattice/DEMOS-RESEARCH.md`
- **Delivery:** Announces to Telegram (owner gets notified of each engagement summary)
- **Timeout:** 180 seconds per engagement session

### 10b.5 Pipeline Integration

Each cron run checks `~/.openclaw/pipeline/inbox/` first for messages from Isidore before proceeding to Lattice engagement. This ensures pipeline communication takes priority.

---

## 11. Phase 9 -- ClawHub Skills (Future, Audited Only)

**NOT for initial deployment.** This phase happens later after the bot is stable and you've identified specific needs. For the full ecosystem analysis, see `Plans/CLAWHUB-SKILLS-AND-GREGOR-ARCHITECTURE.md`.

### 11.1 The ClawHavoc Risk -- Full Breakdown

The ClawHavoc campaign (Feb 2026) revealed deep supply chain problems:

| Metric | Value |
|--------|-------|
| **Registry before cleanup** | 5,705 skills |
| **Suspicious skills removed** | 2,419 |
| **Registry after cleanup** | 3,286 skills |
| **Registry now (Feb 19, 2026)** | 8,630 non-suspicious skills (grown back faster than moderation) |
| **Confirmed malicious (initial)** | 341 |
| **Confirmed malicious (ongoing)** | 824+ |
| **Single worst actor** | hightower6eu -- 314 malicious skills by one account |
| **Malware type** | AMOS macOS infostealer, credential theft, data exfiltration |
| **Malicious rate at peak** | ~20% of audited packages |

**Critical architectural facts:**
- **Skills run IN-PROCESS with the Gateway.** A malicious skill has full access to Gregor's process, memory, and API keys. There is NO sandboxing. This is an OpenClaw architectural limitation, not fixable with better scanning.
- **Prompt injection is NOT scanned for.** VirusTotal catches binary malware, not adversarial prompts in SKILL.md files.
- **npm lifecycle scripts execute during `clawhub install`.** `preinstall`/`postinstall` scripts are a classic supply chain vector.

### 11.2 The steipete Factor

Peter Steinberger (steipete) created OpenClaw and authored **9 of the top 14 most-downloaded skills** on ClawHub. His skills are essentially the platform's standard library (28.1K downloads on `gog`, 22.1K on `wacli`, 21.5K on `summarize`, 20.7K on `github`).

**Risk:** steipete joined OpenAI on Feb 15, 2026. OpenClaw continues under a foundation, but the most trusted contributor is no longer maintaining the ecosystem. This means:
- His existing skills may not get security patches promptly
- No new reference-quality skills from the platform creator
- Community skills have no benchmark author to compare against

**Mitigation:** Pin exact versions of his skills. Monitor for security advisories. Accept that his existing published code is the highest-quality available.

### 11.3 Skill Whitelist -- Three Tiers

**Tier 1 -- Install (vetted, essential):**

| Skill | Author | Purpose | Requires Denied Tools? |
|-------|--------|---------|----------------------|
| `github` | steipete | GitHub CLI for pipeline communication, PR review | No |
| `summarize` | steipete (Nix) | URL/file summarization for research tasks | No |

**Tier 2 -- Consider after bot is stable (needs evaluation):**

| Skill | Author | Purpose | Concern |
|-------|--------|---------|---------|
| `bird` | steipete (Nix) | X/Twitter monitoring | Requires Twitter API key |
| `gogcli` | steipete (Nix) | Google services | Requires Google OAuth -- large attack surface |
| `exa-web-search-free` | community | Enhanced web search | Need to vet author and code |

**Tier 3 -- Never install:**

| Skill | Reason |
|-------|--------|
| Capability Evolver | Self-modifying agent code -- antithetical to lockdown posture |
| self-improving-agent | Autonomous self-modification |
| Any browser skill | `browser` tool denied in Phase 4 |
| Any coding-agent | Gregor doesn't spawn sub-agents |
| moltbook / agentchat | Agent-to-agent social networking -- unnecessary attack surface |
| Any skill by hightower6eu | Known malicious actor (314 skills) |
| Any skill < 500 downloads with unknown author | Below trust threshold |

**Policy: 4 skills maximum.** `github` + `summarize` + `web_search` (built-in) + `clawdhub` (registry search only). Every additional skill is attack surface. Gregor's power comes from the Claude model, not from community skills.

### 11.4 Vetting Checklist (Before Installing ANY Skill)

- [ ] Author is known/trusted (steipete, established community member with 1K+ downloads)
- [ ] No VirusTotal flags on any file in the skill package
- [ ] No ClawHavoc association (check author history, account age)
- [ ] Manually read SKILL.md -- no `eval()`, `fetch()` to unknown hosts, `exec()`, obfuscated code
- [ ] No npm lifecycle scripts in `package.json` (`preinstall`, `postinstall`, `prepare`)
- [ ] Does not require any denied tools (`gateway`, `cron`, `group:runtime`, `group:fs`, `browser`, etc.)
- [ ] Pin exact version after install -- disable auto-updates for skills
- [ ] Run `openclaw security audit --deep` after installation

### 11.5 Re-enabling Plugins

```jsonc
{
  "plugins": {
    "enabled": true,
    "allow": [
      // Only explicitly approved plugins (NOT "allowList"!)
      "github",
      "summarize"
    ]
  }
}
```

---

## 12. Phase 10 -- Our Repo Structure

Configuration management, documentation, and deployment scripts (NOT the OpenClaw source code itself):

```
openclaw-bot/
├── CLAUDE.md                          # Project context for Isidore
├── CLAUDE.local.md                    # Session continuity (gitignored)
├── README.md                          # Public documentation
├── Plans/
│   ├── MASTERPLAN.md                  # This file
│   ├── MASTERPLAN-EXPLAINED.md        # Reasoning behind every decision
│   ├── RESEARCH-OFFICIAL-DOCS.md      # Official docs research findings
│   ├── IRC-REGISTRATION-GUIDE.md      # Libera.Chat registration (reference)
│   └── CLAWHUB-SKILLS-AND-GREGOR-ARCHITECTURE.md
├── src/
│   ├── config/
│   │   └── openclaw.json.example      # Sanitized config template (REDACTED tokens)
│   ├── scripts/
│   │   └── backup.sh                  # Memory/config backup (deployed to VPS)
│   └── pipeline/
│       ├── read.sh                    # Read pipeline inbox
│       ├── send.sh                    # Send pipeline message
│       └── status.sh                  # Pipeline status check
└── openclaw-vs-pai-comparison.md      # OpenClaw vs PAI deep comparison
```

**VPS-side pipeline** (not in git — lives at `~/.openclaw/pipeline/` on VPS):
```
~/.openclaw/pipeline/
├── inbox/          # Messages from Isidore → Gregor
├── outbox/         # Messages from Gregor → Isidore
├── ack/            # Acknowledged/processed messages
└── PROTOCOL.md     # Message format specification
```

---

## 13. Security Threat Model

### 13.1 Attack Surfaces

| Surface | Threat | Mitigation |
|---------|--------|------------|
| **Gateway port** | External access if binding fails | Loopback + firewall + verification cron |
| **Telegram input** | Prompt injection via DM messages | Pairing (owner-only), no group access, system prompt hardening |
| **Anthropic API** | API key theft | Env var in systemd, 0600 permissions, no config in git |
| **OpenClaw updates** | Supply chain compromise | Pin versions, review changelogs before updating |
| **ClawHub plugins** | Malicious skills | Plugins disabled at launch, audit process for future |
| **mDNS discovery** | Network reconnaissance | mDNS disabled |
| **Memory database** | Data exfiltration | File permissions, encrypted disk |
| **Gateway tool** | AI self-reconfiguration | `gateway` in deny list |
| **Workspace injection** | .md files loaded as trusted context | Owner-controlled workspace, pipeline protocol validation |
| **Lattice API** | Engagement data exposure, API abuse | Cron rate limiting (5x/day), quality-first engagement policy |
| **HTTP fingerprinting** | Instance identification | OpenClaw sends identifiable User-Agent headers |
| **In-process skills** | Malicious skill gets full process/memory/API key access (no sandboxing) | Plugins disabled; whitelist-only installs; steipete-only trust model |
| **Ecosystem maintenance** | steipete (creator, top contributor) joined OpenAI Feb 15 2026 | Pin skill versions; monitor advisories; accept maintenance lag risk |
| **npm lifecycle scripts** | `clawhub install` runs preinstall/postinstall -- supply chain vector | Vetting checklist checks package.json scripts before any install |

### 13.2 Known CVEs to Track

| CVE | Severity | Description | Status |
|-----|----------|-------------|--------|
| CVE-2026-25253 | 8.8 (High) | Control UI trusts `gatewayURL` query param | Patched in v2026.1.29 |
| CVE-2026-24763 | High | Command injection | Patched |
| CVE-2026-25157 | High | Command injection | Patched |

**Action:** Ensure you install a version newer than `2026.1.29`.

### 13.3 Incident Response

If you suspect compromise:

1. **Immediate:** `systemctl stop openclaw`
2. **Assess:** Check logs for unauthorized commands, outbound connections
3. **Rotate:** Change all API keys (Anthropic, NickServ password)
4. **Audit:** `openclaw security audit --deep`
5. **Restore:** From known-good backup if needed

---

## 14. Configuration Reference

### 14.1 Deployed Configuration (Capability-First)

```jsonc
// ~/.openclaw/openclaw.json -- AS CAPABLE AS POSSIBLE, AS SECURE AS NECESSARY
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
      "models": { "anthropic/claude-opus-4-6": {} },
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

### 14.2 Environment Variables

```bash
# /etc/openclaw/env (chmod 600, owned by root:openclaw)
# Anthropic auth handled via setup-token (Max subscription) -- stored in ~/.openclaw/credentials/
TELEGRAM_BOT_TOKEN=...
OPENCLAW_STATE_DIR=/home/openclaw/.openclaw
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_DISABLE_BONJOUR=1
```

Note: IRC env vars (`IRC_NICKSERV_PASSWORD`, etc.) are no longer needed — IRC was dropped in the Telegram-first pivot.

---

## 15. Runbook: Common Operations

### Start / Stop / Restart

```bash
sudo systemctl start openclaw
sudo systemctl stop openclaw
sudo systemctl restart openclaw
sudo systemctl status openclaw
```

### View Logs

```bash
# Live logs
journalctl -u openclaw -f

# OpenClaw's own logs
openclaw logs --follow

# Last 100 lines
journalctl -u openclaw -n 100
```

### Update OpenClaw

```bash
# 1. Stop the service
sudo systemctl stop openclaw

# 2. Update
sudo -u openclaw npm update -g openclaw

# 3. Check version
openclaw --version

# 4. Run security audit
sudo -u openclaw openclaw security audit --fix

# 5. Restart
sudo systemctl start openclaw

# 6. Verify binding
ss -tlnp | grep 18789
```

### Check Backup Health

```bash
# Verify backup cron
crontab -l | grep backup

# Check last backup
ls -lt ~/.openclaw/backups/ | head -5

# Check backup log
tail -10 ~/.openclaw/logs/backup.log
```

### Check Lattice Cron Health

```bash
# View cron job config
cat ~/.openclaw/cron/jobs.json | jq '.jobs[0].state'

# View recent runs
tail -5 ~/.openclaw/cron/runs/*.jsonl | jq '.status, .summary'
```

### Emergency Shutdown

```bash
sudo systemctl stop openclaw
sudo ufw deny out to any port 18789  # block even loopback if paranoid
```

### Access Control UI (via SSH tunnel)

```bash
# From your local machine (uses ~/.ssh/config Host vps):
ssh -L 18789:127.0.0.1:18789 vps
# Then open: http://localhost:18789 in your browser
```

---

## 16. Decision Log

| Decision | Chosen | Rationale |
|----------|--------|-----------|
| **Guiding philosophy** | **As capable as possible, as secure as necessary** | Security protects capability, not replaces it |
| Deployment target | VPS (213.199.32.18) | Always-on, dedicated hardware |
| AI provider | Anthropic (Max subscription via setup-token) | Best quality, user preference, no separate API cost |
| Auth method | Setup-token (API key as fallback) | Max subscription directly powers the bot |
| ~~IRC network~~ | ~~Libera.Chat~~ → **DROPPED** | Telegram-first pivot — IRC never deployed |
| Security posture | ~~Maximum lockdown~~ → **Capability-first** | tools.profile "full" with targeted denials, not blanket restriction |
| Gateway binding | Loopback only | No external exposure |
| Remote access | SSH tunnel only | No Tailscale, no public UI |
| Plugins | Enabled (core only: telegram, device-pair, memory-core) | No ClawHub community plugins |
| Service manager | systemd | Standard Linux, auto-restart |
| Secrets storage | systemd env file + config (600 perms) | Bot token in config (paired access only) |
| Tool profile | **Full** + targeted deny list | Gregor needs exec, fs, web for Lattice + pipeline |
| Default model | claude-opus-4-6 | Best reasoning quality for personal assistant |
| Channel count | ~~IRC + Telegram~~ → **Telegram only** | Paired to owner, sufficient for all use cases |
| Bot nick | Gregor (`@gregor_openclaw_bot`) | User's choice |
| VPS OS | Ubuntu 24.04 LTS | Matches recommended, best supported |
| Bot purpose | General + code + security + Lattice engagement | Multi-domain assistant + autonomous social engagement |
| Subscription | Claude Max $100/mo (5x Pro) | Generous rate limits for bot + cron |
| Web search + fetch | Both enabled | Research capability for questions and Lattice engagement |
| Embedding provider | **Local** (embeddinggemma-300m) | Free, private, VPS has 23GB RAM, no external API dependency |
| Memory | Persistent hybrid search (vector + FTS) | Local embeddings, 768-dim, temporal decay |
| Backups | VPS daily cron + sanitized config in repo | 30-day retention, 600 perms, no secrets in git |
| Pipeline architecture | ~~GitHub .pipeline/~~ → **VPS `~/.openclaw/pipeline/`** | Direct filesystem, faster, no git round-trip |
| Lattice engagement | Autonomous cron, 5x/day, quality-first | DID:key identity, Demos protocol participation |
| Exec security | `full` (was `deny`) | Needed for `node client.mjs`, pipeline scripts, cron tasks |

---

## 17. Open Questions -- ANSWERED

All questions resolved (2026-02-19):

| # | Question | Answer | Impact |
|---|----------|--------|--------|
| 1 | **Bot nick** | `Gregor` | Used in IRC config, NickServ registration, system prompt |
| 2 | **IRC channels** | Create new (`#gregor`) + join existing (TBD) | Both in `channels` array, new one registered on Libera.Chat |
| 3 | **Allowed users** | Nick not yet registered on Libera.Chat | Phase 0 prerequisite: register user nick before bot nick |
| 4 | **VPS details** | Ubuntu 24.04 LTS | Matches recommended OS, no install script changes needed |
| 5 | **Bot purpose** | General assistant + code/tech help + security research | Multi-purpose system prompt, broad tool profile |
| 6 | **Anthropic tier** | Claude Max $100/mo (5x Pro usage) | Generous rate limits for IRC bot usage |
| 7 | **Browser tool** | Web search only (`web_search` allowed, `browser` denied) | Remove `web_search` from deny list, keep `browser` denied |
| 8 | **Memory scope** | Yes, persistent memory across sessions | Memory config stays as planned (mmr + temporalDecay enabled) |
| 9 | **Update policy** | Auto-update with security audit after each | Add update cron + audit to Phase 8 |
| 10 | **Backup location** | VPS + sanitized config committed to this repo | Backup script pushes to `openclaw-bot` repo (no secrets) |

**Remaining pre-implementation tasks:**
- Register YOUR nick on Libera.Chat (needed before bot nick registration)
- Register `Gregor` as bot nick on Libera.Chat
- Decide which existing channel(s) to join (besides `#gregor`)
- Determine your IRC hostmask for `allowFrom` (available after registration)

---

## Execution Order

```
Phase 0  ─── VPS prep (OS, user, firewall, Node.js)              ✅ DONE
  │
Phase 1  ─── Install OpenClaw                                     ✅ DONE
  │
Phase 2  ─── Configure Anthropic                                  ✅ DONE
  │
Phase 3  ─── IRC channel setup                                    ⏭️ SKIPPED (Telegram-first pivot)
  │
Phase 3b ─── Telegram channel setup                               ✅ DONE
  │
Phase 4  ─── Security hardening (capability-first)                ✅ DONE
  │
Phase 5  ─── Bot identity & system prompt                         ✅ DONE
  │
Phase 6  ─── Memory (local embeddings, hybrid search)             ✅ DONE (2026-02-20)
  │
Phase 7  ─── Systemd service                                      ✅ DONE
  │
Phase 8  ─── Backups (daily cron, 30-day retention)               ✅ DONE (2026-02-20)
  │
Phase 8b ─── Lattice engagement (5x/day cron)                     ✅ DONE (2026-02-19)
  │
  ▼
LIVE ═══════════════════════════════ @gregor_openclaw_bot
  │
Phase 8  ─── Monitoring scripts (verify-binding, health-check)    🔜 TODO
  │
Phase 9  ─── ClawHub plugins (if ever needed, audited only)       🔜 FUTURE
  │
Phase 10 ─── Repo structure maintenance                           🔄 ONGOING
```

---

*This plan is based on exhaustive analysis of the centminmod/explain-openclaw repository (199 files, 5.6MB), the official OpenClaw docs (docs.openclaw.ai), 3 independent security audits, CVE databases, and community research. Config schemas verified against official configuration reference. Updated 2026-02-20: philosophy pivot from "Maximum Lockdown" to "As capable as possible, while as secure as necessary." IRC dropped (Telegram-first pivot). Local embeddings deployed. Lattice engagement system documented. Backup system deployed. Configuration reference updated to match actual VPS state. See `Plans/CLAWHUB-SKILLS-AND-GREGOR-ARCHITECTURE.md` for the ClawHub ecosystem deep-dive.*
