# The OpenClaw Masterplan

**Deploy your own AI-powered Telegram bot on a VPS in under an hour.**

This guide walks you through every step — from a blank Ubuntu server to a fully operational, security-hardened OpenClaw bot powered by Anthropic Claude. No prior OpenClaw experience needed.

> **Guiding philosophy:** *As capable as possible, while as secure as necessary.*
>
> Security exists to protect capability, not to prevent it. Every deny-list entry, every disabled feature must justify itself against the question: "Does removing this capability make the bot meaningfully safer, or just less useful?"

---

## Table of Contents

**Part 1: Get It Running**
1. [Phase 1 — VPS Setup & Hardening](#phase-1--vps-setup--hardening)
2. [Phase 2 — Install OpenClaw](#phase-2--install-openclaw)
3. [Phase 3 — Authenticate with Anthropic](#phase-3--authenticate-with-anthropic)
4. [Phase 4 — Connect Telegram](#phase-4--connect-telegram)
5. [Phase 5 — Your First Conversation](#phase-5--your-first-conversation)
6. [Phase 6 — Run as a Service](#phase-6--run-as-a-service)

**Part 2: Make It Solid**
7. [Phase 7 — OpenClaw Security](#phase-7--openclaw-security)
8. [Phase 8 — Bot Identity & Behavior](#phase-8--bot-identity--behavior)
9. [Phase 9 — Memory & Persistence](#phase-9--memory--persistence)
10. [Phase 10 — Backups & Monitoring](#phase-10--backups--monitoring)

**Part 3: Make It Smart**
11. [Phase 11 — Skills](#phase-11--skills)
12. [Phase 12 — Autonomous Engagement (Cron)](#phase-12--autonomous-engagement-cron)
13. [Phase 13 — Cost Management & Optimization](#phase-13--cost-management--optimization)

**Appendices**
- [A — Architecture Overview](#appendix-a--architecture-overview)
- [B — Async Pipeline (Local ↔ Bot)](#appendix-b--async-pipeline-local--bot)
- [C — Running Multiple Bots](#appendix-c--running-multiple-bots)
- [D — Security Threat Model](#appendix-d--security-threat-model)
- [E — Configuration Reference](#appendix-e--configuration-reference)
- [F — Runbook: Common Operations](#appendix-f--runbook-common-operations)
- [G — References](#appendix-g--references)

---

# Part 1: Get It Running

> **Goal:** Go from a blank VPS to a working Telegram bot you can talk to.

---

## Phase 1 — VPS Setup & Hardening

Before installing anything, secure your server. This phase takes the most time but protects everything that follows.

### 1.1 What You Need

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| RAM | 2 GB | 4 GB |
| Disk | 10 GB | 20 GB SSD |
| CPU | 1 vCPU | 2 vCPU |
| Network | IPv4, outbound HTTPS | Same |

You also need:
- **An Anthropic API key** — create one at [console.anthropic.com](https://console.anthropic.com) (Phase 3)
- **A Telegram account** — to create a bot via @BotFather (Phase 4)

### 1.2 First Login & System Update

SSH into your fresh VPS:

```bash
ssh root@YOUR_VPS_IP
```

Update everything:

```bash
apt update && apt upgrade -y
```

### 1.3 Create a Dedicated User

**Never run OpenClaw as root.** Create a dedicated `openclaw` user:

```bash
# Create user with home directory
useradd -m -s /bin/bash openclaw

# Set a strong password (you'll disable password login shortly)
passwd openclaw

# Give the user sudo access (needed for initial setup only)
usermod -aG sudo openclaw
```

### 1.4 SSH Key Authentication

Set up SSH keys so you can log in without a password. **On your local machine:**

```bash
# Generate a key pair (if you don't have one)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy your public key to the VPS
ssh-copy-id openclaw@YOUR_VPS_IP

# Test that key login works
ssh openclaw@YOUR_VPS_IP
```

Once key login works, **disable password authentication:**

```bash
# On the VPS, edit SSH config
sudo nano /etc/ssh/sshd_config
```

Set these values:

```
PermitRootLogin no
PasswordAuthentication no
AllowUsers openclaw
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

> **Important:** Keep your current SSH session open while testing! Open a NEW terminal and verify you can still log in before closing the old session.

### 1.5 Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
# Do NOT open port 18789 — the gateway stays on loopback only
sudo ufw enable
```

Verify:

```bash
sudo ufw status verbose
# Should show: SSH allowed, everything else denied inbound
```

### 1.6 Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 1.7 Install Node.js

OpenClaw requires Node.js 22.x:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

Verify:

```bash
node --version   # Should be >= 22.12.0
npm --version
```

### 1.8 Disk Encryption (Optional)

If your VPS provider supports LUKS or encrypted volumes, enable it. OpenClaw stores credentials as plaintext files protected only by Unix permissions.

### ✅ Phase 1 Checkpoint

- [ ] Logged in as `openclaw` user (not root)
- [ ] SSH key auth works, password auth disabled
- [ ] Firewall active (only SSH allowed inbound)
- [ ] Node.js 22.x installed
- [ ] System fully updated

---

## Phase 2 — Install OpenClaw

### 2.1 Install as the Dedicated User

```bash
# Switch to the openclaw user (if not already)
sudo -u openclaw -i

# Set up npm global directory (avoids permission issues)
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install OpenClaw (MUST be >= 2026.1.29 for security patches)
npm install -g openclaw@latest

# Verify
openclaw --version
```

### 2.2 Alternative: One-Line Install

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

This auto-detects missing Node.js and installs it.

### 2.3 Directory Structure

After installation, OpenClaw creates:

```
/home/openclaw/
├── .openclaw/                  # State directory (auto-created)
│   ├── openclaw.json           # Main configuration
│   ├── credentials/            # OAuth tokens, API keys
│   ├── memory/                 # SQLite memory database
│   ├── agents/                 # Agent workspace + system prompts
│   └── logs/                   # Gateway logs
└── workspace/                  # Agent working directory
```

### ✅ Phase 2 Checkpoint

- [ ] `openclaw --version` shows >= 2026.1.29
- [ ] Running as the `openclaw` user, not root

---

## Phase 3 — Authenticate with Anthropic

OpenClaw needs an Anthropic API key to talk to Claude. This is separate from any Claude subscription you might have.

### 3.1 Get an API Key

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create an account (or log in)
3. Go to **API Keys** → **Create Key**
4. Copy the key (starts with `sk-ant-...`)
5. Add billing — costs are per-token (see Phase 13 for estimates)

### 3.2 Configure OpenClaw

```bash
# Set the API key
openclaw config set provider.name anthropic
openclaw config set provider.apiKey "sk-ant-YOUR-KEY-HERE"

# Set the default model (Sonnet = best balance of quality and cost)
openclaw config set provider.model "claude-sonnet-4"
```

### 3.3 Verify Authentication

```bash
# Check provider status
openclaw models status
# Should show: anthropic — authenticated

# Test with a quick message
openclaw chat --once "Hello, respond with just 'OK'"
# Should print: OK
```

If you see errors, run:

```bash
openclaw doctor
```

### 3.4 Choose Your Model

| Model | Best For | Approximate Cost |
|-------|----------|-----------------|
| `claude-sonnet-4` | Daily use — good quality, reasonable cost | ~$3/MTok input |
| `claude-haiku-4` | Automated tasks, simple queries | ~$1/MTok input |
| `claude-opus-4` | Complex reasoning, long context | ~$5/MTok input |

**Start with Sonnet.** You can always switch later.

### ✅ Phase 3 Checkpoint

- [ ] `openclaw models status` shows authenticated
- [ ] `openclaw chat --once "test"` returns a response
- [ ] API key stored securely (we'll lock down permissions in Phase 7)

---

## Phase 4 — Connect Telegram

### 4.1 Create a Bot via @BotFather

1. Open Telegram and search for `@BotFather`
2. Send `/newbot`
3. Choose a **name** (display name) and **username** (must end in `bot`)
4. BotFather gives you a **bot token** — looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`
5. **Save this token** — you'll need it in a moment

### 4.2 Configure Telegram in OpenClaw

Edit `~/.openclaw/openclaw.json` and add the Telegram channel:

```jsonc
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "YOUR_BOT_TOKEN_HERE",
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "groups": {},
      "streamMode": "partial"
    }
  }
}
```

**What these settings mean:**
- `dmPolicy: "pairing"` — the first person to DM the bot becomes the paired owner. Only they can talk to it.
- `groupPolicy: "allowlist"` — the bot ignores all group chats unless you explicitly add them.
- `streamMode: "partial"` — responses stream as they generate (not all-at-once).

### 4.3 Start the Gateway and Pair

```bash
# Start the gateway
openclaw gateway start

# Watch the logs for the pairing prompt
openclaw logs --follow
```

Now open Telegram and send your bot a message (anything — "hello" works). The logs will show a **pairing code**. Confirm the pairing in the logs or via the Control UI (through SSH tunnel).

Once paired, **only your Telegram account can talk to the bot.**

### ✅ Phase 4 Checkpoint

- [ ] Bot created via @BotFather
- [ ] Token configured in `openclaw.json`
- [ ] Gateway running, pairing complete
- [ ] You can send messages and get responses

---

## Phase 5 — Your First Conversation 🎉

**Congratulations!** If you completed Phase 4, you have a working AI-powered Telegram bot. Take a moment to try it out:

1. **Send a greeting** — "Hello! What can you do?"
2. **Ask something useful** — "What's the weather in Berlin?" or "Explain quantum computing simply"
3. **Test its tools** — "Search the web for today's top news"
4. **Check the connection** — Send `/status` to see model info and session stats

This is your bot. It's running Claude on your own server, talking to you through Telegram, with no third parties in between (except Anthropic's API and Telegram's servers).

**Before continuing:** Stop the gateway for now. We'll set it up as a proper service next.

```bash
openclaw gateway stop
```

> **Everything from here on makes the bot better** — more secure, more capable, more reliable. But it already works. The rest is enhancement.

---

## Phase 6 — Run as a Service

Running OpenClaw as a systemd service means it starts automatically on boot, restarts on crashes, and runs in the background.

### 6.1 Create the Environment File

Secrets go here (not in `openclaw.json`):

```bash
sudo mkdir -p /etc/openclaw
sudo tee /etc/openclaw/env > /dev/null << 'EOF'
ANTHROPIC_API_KEY=sk-ant-YOUR-KEY-HERE
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
OPENCLAW_STATE_DIR=/home/openclaw/.openclaw
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_DISABLE_BONJOUR=1
EOF
sudo chmod 600 /etc/openclaw/env
sudo chown root:openclaw /etc/openclaw/env
```

### 6.2 Create the Systemd Unit

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

ExecStart=/home/openclaw/.npm-global/bin/openclaw gateway --port 18789
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

Save this file, then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw
```

### 6.3 Verify the Service

```bash
# Check it's running
sudo systemctl status openclaw

# Verify loopback binding (CRITICAL — see Phase 7 for why)
ss -tlnp | grep 18789
# MUST show 127.0.0.1:18789, NOT 0.0.0.0:18789

# Check logs
journalctl -u openclaw -f

# Send a Telegram message to confirm it works
```

### ✅ Phase 6 Checkpoint

- [ ] Service starts on boot (`systemctl is-enabled openclaw` → enabled)
- [ ] Gateway bound to 127.0.0.1:18789 (NOT 0.0.0.0)
- [ ] Telegram messages work through the service
- [ ] Service restarts on failure (`systemctl show openclaw -p Restart` → on-failure)

---

# Part 2: Make It Solid

> **Goal:** Harden the bot's security, configure its personality, and set up persistence.

---

## Phase 7 — OpenClaw Security

Your VPS is hardened (Phase 1). Now harden OpenClaw itself.

### 7.1 Gateway Binding

The gateway MUST listen on loopback only. **There's a known bug where binding failure silently falls back to 0.0.0.0 (all interfaces).** Always verify after starting.

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

Verification (run this after every restart):

```bash
ss -tlnp | grep 18789
# MUST show 127.0.0.1:18789 — if it shows 0.0.0.0:18789, stop immediately!
```

### 7.2 Tool Restrictions

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

**Why these specific denials:**
- `gateway` — prevents the AI from reconfiguring itself (zero-gating risk)
- `nodes` — no need for device invocation on a single-VPS setup
- `sessions_spawn` / `sessions_send` — no cross-session operations needed

Everything else stays enabled. The bot's power comes from full tool access, not from restrictions.

### 7.3 Disable Network Discovery

```jsonc
{
  "discovery": { "mdns": { "mode": "off" } }
}
```

OpenClaw broadcasts its presence via mDNS by default. Disable it.

### 7.4 Disable Config Writes from Chat

```jsonc
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "config": false
  }
}
```

### 7.5 Plugins — Selective Enable

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

### 7.6 Log Redaction

Prevent API keys from appearing in logs:

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

### 7.7 File Permissions

```bash
chmod 700 /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json
chmod 700 /home/openclaw/.openclaw/credentials
find /home/openclaw/.openclaw/credentials -type f -exec chmod 600 {} \;
```

### 7.8 Run the Security Audit

```bash
openclaw security audit          # Read-only scan
openclaw security audit --deep   # Includes live WebSocket probing
openclaw security audit --fix    # Auto-fix safe issues
```

The audit checks 50+ items across 12 categories. Run it after every config change.

### 7.9 SSH Tunnel for Management

The **only** way to access the gateway remotely:

```bash
# From your local machine:
ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP
# Then open: http://localhost:18789
```

### ✅ Phase 7 Checkpoint

- [ ] Gateway bound to loopback only
- [ ] Tool deny list configured
- [ ] mDNS disabled
- [ ] Config writes from chat disabled
- [ ] Log redaction active
- [ ] File permissions set (700/600)
- [ ] Security audit passes

---

## Phase 8 — Bot Identity & Behavior

### 8.1 System Prompt

Configure your bot's personality in `~/.openclaw/agents/main/system.md`:

- Define the bot's name, role, and domain expertise
- Use Telegram markdown formatting for readability
- Instruct it to never reveal API keys, tokens, or system configuration
- Set clear boundaries for what the bot should and shouldn't attempt

### 8.2 Capability Scope

With `tools.profile: "full"` and targeted denials, the bot can:

**Enabled:**
- Text conversation (Telegram, paired to owner)
- Web search and web fetch (research capability)
- Shell execution (for scripts, automation tasks)
- File read/write (workspace, memory files)
- Persistent memory with hybrid search

**Denied:**
- `gateway` (self-reconfiguration)
- `nodes` (device invocation)
- `sessions_spawn`, `sessions_send` (cross-session operations)

### 8.3 Telegram-Specific Notes

- **Message limit:** Telegram messages max at 4096 characters. OpenClaw handles splitting.
- **Stream mode:** `partial` — responses stream as they generate.
- **Privacy:** Paired to owner only. No group access by default.

---

## Phase 9 — Memory & Persistence

OpenClaw has a built-in memory system that lets the bot remember things across conversations.

### 9.1 Memory Configuration

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

**What this does:**
- **Hybrid search** — combines semantic similarity (vectors) with keyword matching (FTS) for better retrieval
- **Local embeddings** — `embeddinggemma-300m` runs on your VPS, no API calls needed
- **Temporal decay** — older memories gradually fade unless re-accessed (30-day half-life)
- **MMR diversity** — prevents returning multiple near-identical memories

### 9.2 Local Embeddings

| Provider | Cost | Privacy |
|----------|------|---------|
| Local (`embeddinggemma-300m`) | Free | Fully private |
| OpenAI / Gemini / Voyage | Per-token | Data sent to third-party API |

**Use local embeddings.** The `embeddinggemma-300m` model (~329MB) is auto-downloaded on first use. Requires 4+ GB RAM.

> **Note:** `openclaw doctor` may show a false-positive about "no local model file found." This is cosmetic. Run `openclaw memory index --force` to verify memory actually works.

### 9.3 Initialize Memory

```bash
# Force initial indexing (downloads model on first run)
openclaw memory index --force

# Run again to confirm it works
openclaw memory index --force

# Verify
openclaw memory status --deep
```

### ✅ Phase 9 Checkpoint

- [ ] Memory config in `openclaw.json`
- [ ] `openclaw memory status --deep` shows healthy
- [ ] Local embeddings working (no external API calls)

---

## Phase 10 — Backups & Monitoring

### 10.1 Backup Script

Back up the three critical things: config, memory database, and memory files.

```bash
#!/bin/bash
# /home/openclaw/scripts/backup.sh

BACKUP_DIR="$HOME/.openclaw/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# Config
cp ~/.openclaw/openclaw.json "$BACKUP_DIR/config-$TIMESTAMP.json"
chmod 600 "$BACKUP_DIR/config-$TIMESTAMP.json"

# Memory database
cp ~/.openclaw/memory/main.sqlite "$BACKUP_DIR/memory-$TIMESTAMP.sqlite"
chmod 600 "$BACKUP_DIR/memory-$TIMESTAMP.sqlite"

# Memory files
tar czf "$BACKUP_DIR/memory-files-$TIMESTAMP.tar.gz" -C ~/.openclaw memory/
chmod 600 "$BACKUP_DIR/memory-files-$TIMESTAMP.tar.gz"

# Prune backups older than 30 days
find "$BACKUP_DIR" -mtime +30 -delete

echo "$(date): Backup complete"
```

Schedule it:

```bash
chmod +x ~/scripts/backup.sh
# Daily at 3 AM
(crontab -l 2>/dev/null; echo "0 3 * * * /home/openclaw/scripts/backup.sh >> /home/openclaw/.openclaw/logs/backup.log 2>&1") | crontab -
```

### 10.2 Binding Verification

A cron job that catches the 0.0.0.0 binding bug:

```bash
#!/bin/bash
# /home/openclaw/scripts/verify-binding.sh
if ss -tlnp | grep ':18789' | grep -q '0.0.0.0'; then
    echo "CRITICAL: Gateway bound to 0.0.0.0! Stopping."
    systemctl stop openclaw
fi
```

```bash
chmod +x ~/scripts/verify-binding.sh
# Every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/openclaw/scripts/verify-binding.sh") | crontab -
```

### 10.3 Health Check

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

### 10.4 Log Rotation

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

### 10.5 Auto-Update with Security Audit

```bash
#!/bin/bash
# /home/openclaw/scripts/auto-update.sh

export PATH="$HOME/.npm-global/bin:$PATH"

CURRENT_VERSION=$(openclaw --version 2>/dev/null)
npm update -g openclaw
NEW_VERSION=$(openclaw --version 2>/dev/null)

if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    echo "$(date): Updated OpenClaw from $CURRENT_VERSION to $NEW_VERSION"
    sudo systemctl restart openclaw
    sleep 5
    /home/openclaw/scripts/verify-binding.sh
fi

# Always run security audit
openclaw security audit --deep >> ~/.openclaw/logs/audit.log 2>&1
```

```bash
chmod +x ~/scripts/auto-update.sh
# Weekly: Sunday 4 AM
(crontab -l 2>/dev/null; echo "0 4 * * 0 /home/openclaw/scripts/auto-update.sh >> /home/openclaw/.openclaw/logs/update.log 2>&1") | crontab -
```

### ✅ Phase 10 Checkpoint

- [ ] Daily backups running (`crontab -l` shows backup entry)
- [ ] Binding verification running every 5 minutes
- [ ] Log rotation configured
- [ ] Auto-update scheduled weekly

---

# Part 3: Make It Smart

> **Goal:** Unlock advanced capabilities — skills, automation, and cost optimization.

---

## Phase 11 — Skills

### 11.1 Bundled vs. Community Skills

OpenClaw ships with ~50 **bundled skills** inside the npm package. These are official, maintained, and carry no supply chain risk. They're completely separate from the ClawHub community registry.

**Key concept:** Bundled skills show as "missing" until their external CLI dependency is installed. Once the binary is in PATH, the skill automatically becomes "ready." No `clawhub install` required.

```bash
openclaw skills list                  # Shows all 50 with status
openclaw skills info <skill-name>     # Shows dependencies
```

### 11.2 Useful Skills for a VPS Bot

| Skill | CLI Dependency | Install Command | What It Does |
|-------|---------------|-----------------|-------------|
| **github** | `gh` | `sudo apt install gh` | GitHub CLI — issues, PRs, code review |
| **gh-issues** | `gh` | (same as above) | Fetch issues, spawn agents for fixes |
| **summarize** | `summarize` | `npm install -g @steipete/summarize` | Summarize URLs, PDFs, YouTube |
| **clawhub** | `clawhub` | `npm install -g clawhub` | Search/install community skills |
| **healthcheck** | (none) | Already ready | System health and audit scheduling |
| **weather** | (none) | Already ready | Weather via wttr.in |
| **tmux** | (none) | Already ready | Remote-control tmux sessions |
| **skill-creator** | (none) | Already ready | Create custom skills |

Some skills are **macOS-only** and won't work on Linux (peekaboo, imsg, apple-notes, etc.).

### 11.3 Installing Skill Dependencies

```bash
# 1. Check what a skill needs
openclaw skills info github

# 2. Install the dependency
sudo apt install gh
npm install -g @steipete/summarize

# 3. Verify it's ready
openclaw skills list | grep "ready"

# 4. For auth-requiring skills:
gh auth login
```

**No gateway restart needed.** Skills are detected dynamically.

### 11.4 Community Skills — Proceed with Caution

If you consider community skills from ClawHub, be aware: the **ClawHavoc campaign** (Feb 2026) planted 800+ malicious packages on ClawHub. Skills run IN-PROCESS with full access to the bot's memory and API keys. There is NO sandboxing.

**Vetting checklist before installing any community skill:**

- [ ] Author has 1K+ downloads and is a known community member
- [ ] No VirusTotal flags
- [ ] Manually read the source — no `eval()`, `exec()`, `fetch()` to unknown hosts
- [ ] No npm lifecycle scripts (`preinstall`, `postinstall`)
- [ ] Does not require denied tools
- [ ] Pin exact version after install
- [ ] Run `openclaw security audit --deep` after installation

**Recommendation:** Stick with bundled skills. They cover the most common needs.

---

## Phase 12 — Autonomous Engagement (Cron)

OpenClaw's built-in cron system lets the bot perform tasks on a schedule — without user interaction.

### 12.1 How Cron Works

OpenClaw's cron runs inside the gateway process (not system crontab). It triggers agent sessions at specified intervals with full tool and memory access.

```bash
openclaw cron list                     # View jobs
openclaw cron add [options]            # Create a job
openclaw cron edit <jobId> [options]   # Modify a job
openclaw cron remove <jobId>          # Delete a job
```

### 12.2 Example: Daily Engagement Posts

```bash
openclaw cron add \
  --name "daily-engagement" \
  --cron "37 8,12,17,21 * * *" \
  --tz "Europe/Berlin" \
  --session isolated \
  --timeout 180 \
  --message "Generate an original post. Draw on your memory and personality. Be authentic." \
  --model "anthropic/claude-haiku-4-5" \
  --thinking off \
  --announce
```

**What each flag does:**

| Flag | Purpose |
|------|---------|
| `--cron` | Standard cron expression (minute hour day month weekday) |
| `--tz` | Timezone for the schedule |
| `--session isolated` | Fresh session each run (recommended) |
| `--timeout` | Max seconds per run |
| `--model` | Override model for this job (Haiku = cheapest) |
| `--thinking off` | Disable extended thinking (unnecessary for posts) |
| `--announce` | Post output to Telegram |

### 12.3 Model Selection for Cron

Use the cheapest model that produces good output:

| Model | Monthly Cost (5 runs/day) | Quality |
|-------|--------------------------|---------|
| Haiku | ~$3 | Good for engagement posts |
| Sonnet | ~$9 | Better for nuanced content |
| Opus | ~$15 | Overkill for most cron tasks |

**Start with Haiku.** Upgrade if quality is poor.

### 12.4 Security Note

If the `cron` tool is not in your deny list, the AI can create its own scheduled jobs. Monitor periodically:

```bash
openclaw cron list   # Check for unexpected jobs
```

Add `cron` to your deny list if you want full control over scheduling.

---

## Phase 13 — Cost Management & Optimization

### 13.1 Built-in Cost Tracking

Use these commands in Telegram or CLI:

| Command | What It Shows |
|---------|--------------|
| `/status` | Session model, context usage, estimated cost |
| `/usage full` | Full breakdown: tokens, cost, model |
| `/context list` | Token breakdown per loaded file |

### 13.2 Prompt Caching (Biggest Savings)

The system prompt and bootstrap files are re-sent on every message. With API key auth, prompt caching saves 90% on this repeated content:

```jsonc
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

The heartbeat keeps the cache warm within the 60-minute TTL.

### 13.3 Cost Baselines

| Model | Input (per MTok) | Output (per MTok) | Cached (per MTok) |
|-------|-----------------|-------------------|-------------------|
| Opus 4.6 | $5.00 | $25.00 | $0.50 |
| Sonnet 4.6 | $3.00 | $15.00 | $0.30 |
| Haiku 4.5 | $1.00 | $5.00 | $0.10 |

**Typical monthly estimates:**

| Usage | Model | Estimated Monthly |
|-------|-------|-------------------|
| Light (~10 msgs/day) | Sonnet | ~$3-5 |
| Moderate (~30 msgs/day) | Sonnet | ~$10-15 |
| Heavy + cron | Sonnet + Haiku cron | ~$20-30 |

### 13.4 Optimization Settings

```jsonc
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

### 13.5 Third-Party Monitoring

| Tool | What It Does | Install |
|------|-------------|---------|
| **ClawMetry** | Real-time cost dashboard | `pipx install clawmetry` |
| **ClawWatcher** | Token usage dashboard | Community project |

**ClawMetry setup:**

```bash
pipx install clawmetry

# Create systemd user service
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/clawmetry.service << 'EOF'
[Unit]
Description=ClawMetry Dashboard

[Service]
ExecStart=%h/.local/bin/clawmetry --port 8900 --host 127.0.0.1
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now clawmetry
loginctl enable-linger $(whoami)

# Access via SSH tunnel:
# ssh -L 8900:127.0.0.1:8900 openclaw@YOUR_VPS_IP
# Then open: http://localhost:8900
```

---

# Appendices

---

## Appendix A — Architecture Overview

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

**Key points:**
- Gateway binds to **loopback only** — never exposed to the internet
- Outbound only: Telegram Bot API + Anthropic API
- Management via **SSH tunnel** — no public Control UI
- **Capability-first:** `tools.profile "full"` with targeted deny list

---

## Appendix B — Async Pipeline (Local ↔ Bot)

A file-based message queue for delegating tasks between your local machine and the bot.

### Directory Setup

```bash
mkdir -p ~/.openclaw/pipeline/{inbox,outbox,ack}
chmod 700 ~/.openclaw/pipeline
```

### How It Works

```
Local machine  ──SSH──>  VPS: ~/.openclaw/pipeline/inbox/   (tasks TO bot)
Local machine  <──SSH──  VPS: ~/.openclaw/pipeline/outbox/  (results FROM bot)
                         VPS: ~/.openclaw/pipeline/ack/     (processed messages)
```

### Message Format

```json
{
  "id": "20260220-143000-a1b2c3d4",
  "from": "local-assistant",
  "to": "bot",
  "timestamp": "2026-02-20T14:30:00Z",
  "type": "task",
  "subject": "Summarize today's posts",
  "body": "Compile and summarize all autonomous engagement posts from today.",
  "priority": "normal"
}
```

### Bot Integration

Add to the bot's system prompt (`~/.openclaw/agents/main/system.md`):

```markdown
## Pipeline
Check ~/.openclaw/pipeline/inbox/ periodically. Process pending messages
and write responses to ~/.openclaw/pipeline/outbox/ in JSON format.
Move processed inbox messages to ~/.openclaw/pipeline/ack/.
```

Or use a cron job:

```bash
openclaw cron add \
  --name "pipeline-check" \
  --cron "*/15 * * * *" \
  --session isolated \
  --message "Check ~/.openclaw/pipeline/inbox/ for pending messages." \
  --model "anthropic/claude-haiku-4-5"
```

Pipeline scripts for send/read/status are included in `src/pipeline/`.

---

## Appendix C — Running Multiple Bots

You can run multiple OpenClaw instances on the same VPS — each with its own config, Telegram bot, and personality. This is useful for testing or running specialized bots.

### Setup

1. **Create a new system user** for each bot:
   ```bash
   sudo useradd -m -s /bin/bash openclaw-bot2
   ```

2. **Install OpenClaw** for the new user (same as Phase 2)

3. **Use a different gateway port:**
   ```jsonc
   { "gateway": { "port": 18790 } }
   ```

4. **Create a new Telegram bot** via @BotFather

5. **Create a separate systemd service:**
   ```bash
   # /etc/systemd/system/openclaw-bot2.service
   # Same as the main service but with:
   #   User=openclaw-bot2
   #   WorkingDirectory=/home/openclaw-bot2
   #   EnvironmentFile=/etc/openclaw/env-bot2
   #   ExecStart=... --port 18790
   ```

Each bot is completely isolated — separate config, memory, credentials, and Telegram channel.

---

## Appendix D — Security Threat Model

### Attack Surfaces

| Surface | Threat | Mitigation |
|---------|--------|------------|
| **Gateway port** | External access if binding fails | Loopback + firewall + verification cron |
| **Telegram input** | Prompt injection via DM | Pairing (owner-only), system prompt hardening |
| **Anthropic API** | API key theft | Env var in systemd, 0600 permissions |
| **OpenClaw updates** | Supply chain compromise | Pin versions, review changelogs |
| **ClawHub plugins** | Malicious skills (in-process, full access) | Bundled-only, audit before install |
| **mDNS discovery** | Network reconnaissance | mDNS disabled |
| **Memory database** | Data exfiltration | File permissions, encrypted disk |
| **Gateway tool** | AI self-reconfiguration | `gateway` in deny list |
| **Cron tool** | AI creating rogue scheduled tasks | Deny `cron` or monitor `cron list` |
| **Cost overrun** | Unbounded token spend | Monitor with `/usage full`, set model tiers |

### Known CVEs

| CVE | Severity | Description | Status |
|-----|----------|-------------|--------|
| CVE-2026-25253 | 8.8 (High) | Control UI trusts `gatewayUrl` query param — 1-click RCE | Patched in v2026.1.29 |
| CVE-2026-24763 | High | Command injection | Patched |
| CVE-2026-25157 | High | Command injection | Patched |

**Always use OpenClaw >= 2026.1.29.**

### Incident Response

1. **Stop:** `sudo systemctl stop openclaw`
2. **Assess:** Check logs for unauthorized commands
3. **Rotate:** Change all API keys and tokens
4. **Audit:** `openclaw security audit --deep`
5. **Restore:** From known-good backup if needed

---

## Appendix E — Configuration Reference

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
      "models": { "anthropic/claude-sonnet-4": {} },
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
      "groupPolicy": "allowlist",
      "groups": {},
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
      "token": "GENERATED_DURING_ONBOARD",
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "tailscale": { "mode": "off" }
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

> **Note:** Remove `botToken` from the config and use the environment file (`/etc/openclaw/env`) instead. Secrets should never be in config files that might get committed to git.

---

## Appendix F — Runbook: Common Operations

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
journalctl -u openclaw -n 100      # Last 100 lines
```

### Update OpenClaw

```bash
sudo systemctl stop openclaw
sudo -u openclaw bash -c 'export PATH="$HOME/.npm-global/bin:$PATH" && npm update -g openclaw'
openclaw --version
sudo -u openclaw openclaw security audit --fix
sudo systemctl start openclaw
ss -tlnp | grep 18789              # Verify binding after restart
```

### Check Backups

```bash
crontab -l | grep backup
ls -lt ~/.openclaw/backups/ | head -5
```

### Emergency Shutdown

```bash
sudo systemctl stop openclaw
sudo ufw deny out to any port 18789
```

### Access Control UI

```bash
# From your local machine:
ssh -L 18789:127.0.0.1:18789 openclaw@YOUR_VPS_IP
# Open: http://localhost:18789
```

---

## Appendix G — References

### Official Documentation

- [docs.openclaw.ai](https://docs.openclaw.ai) — Main documentation site
- [docs.openclaw.ai/llms.txt](https://docs.openclaw.ai/llms.txt) — Full documentation index (200+ pages)
- [Gateway Security](https://docs.openclaw.ai/gateway/security/index.md)
- [Authentication](https://docs.openclaw.ai/gateway/authentication.md)
- [Configuration Reference](https://docs.openclaw.ai/gateway/configuration-reference.md)
- [Telegram Channel](https://docs.openclaw.ai/channels/telegram.md)
- [Memory System](https://docs.openclaw.ai/concepts/memory.md)
- [Tools](https://docs.openclaw.ai/tools/index.md)
- [ClawHub](https://docs.openclaw.ai/tools/clawhub.md)
- [Sandboxing](https://docs.openclaw.ai/gateway/sandboxing.md)
- [Network Model](https://docs.openclaw.ai/gateway/network-model.md)
- [Linux/Systemd](https://docs.openclaw.ai/platforms/linux.md)

### Security & CVE Sources

- [NVD CVE-2026-25253](https://nvd.nist.gov/vuln/detail/CVE-2026-25253) — 8.8 High, 1-click RCE via `gatewayUrl` query param (patched v2026.1.29)
- [GHSA-g8p2-7wf7-98mq](https://github.com/openclaw/openclaw/security/advisories/GHSA-g8p2-7wf7-98mq) — GitHub advisory
- [SOCRadar CVE Analysis](https://socradar.io/blog/cve-2026-25253-rce-openclaw-auth-token/)
- [Adversa.ai Security Guide](https://adversa.ai/blog/openclaw-security-101-vulnerabilities-hardening-2026/)

### GitHub Issues

- [#14845](https://github.com/openclaw/openclaw/issues/14845) — Service file not regenerated on upgrade
- [#1380](https://github.com/openclaw/openclaw/issues/1380) — Binds to Tailscale IP instead of loopback
- [#8823](https://github.com/openclaw/openclaw/issues/8823) — CLI RPC probe hardcodes `ws://127.0.0.1`
- [#16299](https://github.com/openclaw/openclaw/issues/16299) — TUI hardcodes localhost, ignores bind mode
- [#7626](https://github.com/openclaw/openclaw/issues/7626) — Gateway ignores `gateway.port` config
- [#16365](https://github.com/openclaw/openclaw/issues/16365) — Subscription auth feature request

### Blog & Threat Intelligence

- [VirusTotal Partnership](https://openclaw.ai/blog/virustotal-partnership) — ClawHub skill scanning
- [VirusTotal: Automation to Infection](https://blog.virustotal.com/2026/02/from-automation-to-infection-how.html) — ClawHavoc campaign analysis
- [THN: Infostealer targets OpenClaw](https://thehackernews.com/2026/02/infostealer-steals-openclaw-ai-agent.html) — Vidar variant
- [THN: CVE-2026-25253](https://thehackernews.com/2026/02/openclaw-bug-enables-one-click-remote.html) — 1-click RCE coverage

---

*Config schemas verified against [docs.openclaw.ai/gateway/configuration-reference.md](https://docs.openclaw.ai/gateway/configuration-reference.md).*
