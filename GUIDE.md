# The OpenClaw Deployment Guide

**Deploy a security-hardened, self-hosted AI agent — from a blank server to production.**

OpenClaw is an open-source AI agent gateway that bridges multiple messaging platforms — Telegram, WhatsApp, Discord, iMessage, Slack, and more. This guide uses Telegram as the starting interface — it's the fastest path to a working bot — but the security model, memory configuration, skill architecture, and cost patterns you'll learn here apply to any channel OpenClaw supports. Works with any LLM provider: Anthropic, OpenAI, OpenRouter (with free models), and 20+ others. No prior OpenClaw experience needed.

> **Guiding philosophy:** *Maximum capability, minimum attack surface.*
>
> Security exists to protect capability, not to prevent it. Every deny-list entry, every disabled feature must justify itself against the question: "Does removing this capability make the bot meaningfully safer, or just less useful?"
>
> This guide includes the *reasoning* behind every major decision — not just the steps. Look for the indented "Why?" blocks throughout.
>
> **How this was built:** Deep research into every domain where OpenClaw has leverage — security, memory, skills, context engineering, cost optimization — combined with official documentation and hands-on deployment experience on a live VPS.

---

## Table of Contents

**Part 1: Get It Running**
1. [Phase 1 — VPS Setup & Hardening](#phase-1--vps-setup--hardening)
2. [Phase 2 — Install OpenClaw](#phase-2--install-openclaw)
3. [Phase 3 — Choose Your AI Provider](#phase-3--choose-your-ai-provider)
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
14. [Phase 14 — Context Engineering](#phase-14--context-engineering)

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

> **Why this phase order?** The phases are ordered to minimize risk at each step. Harden the OS *before* installing OpenClaw (no window of exposure). Configure the AI provider *before* Telegram (so the bot can respond when it first connects). Set up Telegram *before* hardening OpenClaw (easier to debug issues before lockdown). Add skills and cron *after* the base is stable (debug one layer at a time). Cost monitoring comes last because you need real workloads running before you can meaningfully measure.

---

## Phase 1 — VPS Setup & Hardening

Before installing anything, secure your server. This phase takes the most time but protects everything that follows.

> **Why VPS?** OpenClaw supports four deployment options: VPS, Mac mini, Cloudflare Moltworker, and Docker Model Runner. VPS wins for a Telegram bot because it's always-on without relying on your local machine, systemd gives you auto-restart and security sandboxing, and it's the most thoroughly documented path in the OpenClaw ecosystem. Mac mini ties you to physical hardware. Moltworker lacks egress filtering and is rated "proof-of-concept" grade. Docker Model Runner needs GPU hardware for decent quality. VPS is the production-grade choice.

### 1.1 What You Need

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| RAM | 2 GB | 4 GB |
| Disk | 10 GB | 20 GB SSD |
| CPU | 1 vCPU | 2 vCPU |
| Network | IPv4, outbound HTTPS | Same |

You also need:
- **An LLM API key** — from Anthropic, OpenAI, OpenRouter, or any supported provider (Phase 3)
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

**Never run OpenClaw as root.** A dedicated user means even if OpenClaw is fully compromised, the attacker can only access `~/.openclaw/` and `~/workspace/` — they can't escalate privileges, read other users' files, or modify system binaries.

Create a dedicated `openclaw` user:

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

OpenClaw requires Node.js 22.x (not Bun — the OpenClaw docs note "known bugs" with Bun as runtime. Use Node for the OpenClaw process itself; Bun is fine for development tooling):

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

## Phase 3 — Choose Your AI Provider

OpenClaw works with **any LLM provider** — not just one. This guide is provider-agnostic: pick what fits your budget, privacy needs, and quality expectations.

### 3.1 How to Choose

The decision comes down to four factors:

| Factor | Cloud API (Anthropic, OpenAI) | Gateway (OpenRouter) | Local (Ollama) |
|--------|------------------------------|---------------------|----------------|
| **Quality** | Best available (frontier models) | Same models, via intermediary | Significantly lower (see benchmarks below) |
| **Cost** | Pay-per-token ($1-5/MTok) | Same rates + free tier | Free (but costs hardware/electricity) |
| **Privacy** | Data sent to one provider | Data crosses two trust boundaries | 100% on-machine |
| **Speed** | 50-100+ tokens/sec | Same as provider | 8-15 tok/sec on CPU (see below) |
| **Prompt caching** | Anthropic: yes. OpenAI: yes. | Depends on underlying provider | N/A |

> **Want the best quality?** Anthropic's Claude Sonnet or OpenAI's GPT-4o — both are frontier models with prompt caching support.
>
> **On a budget?** OpenRouter gives you access to free models and [smart routing](https://openrouter.ai/docs/guides/routing/routers/auto-router) (powered by NotDiamond) that picks the optimal model per query. No extra cost.
>
> **Maximum privacy?** Ollama runs everything locally — zero API calls, zero cloud. But quality and speed are substantially lower without a GPU.
>
> **Already have a key?** Any provider works. It's a single config change to switch later.

### 3.1.1 Why API Key Auth (Not Setup-Token)

If you're using Anthropic with a Claude Max subscription, you might see the `setup-token` auth method documented. **Use an API key instead.** Here's why:

**Setup-token does not support prompt caching.** The bot's bootstrap context is re-sent on every single message at full input cost. With API key auth and `cacheRetention: "long"`, that context is cached and reused — dramatically reducing per-message cost.

**In practice, setup-token is fine for initializing and testing your bot** — send a few messages, verify everything works. But for any real workload (daily conversations, scheduled tasks, skill usage), token costs add up fast without caching. Personal usage showed setup-token auth burning through tokens at a rate that made sustained use impractical. API key auth with prompt caching is necessary for production workloads.

**The switch is trivial:** Create an API key at [console.anthropic.com](https://console.anthropic.com), set it in your config, enable `cacheRetention: "long"` (see Phase 13). One config change, immediate improvement.

### 3.2 Configure Your Provider

Pick your provider and run the matching commands:

**Anthropic:**
```bash
openclaw config set provider.name anthropic
openclaw config set provider.apiKey "sk-ant-YOUR-KEY-HERE"
openclaw config set provider.model "claude-sonnet-4"
```

**OpenAI:**
```bash
openclaw config set provider.name openai
openclaw config set provider.apiKey "sk-YOUR-KEY-HERE"
openclaw config set provider.model "gpt-4o"
```

**OpenRouter:**
```bash
openclaw config set provider.name openrouter
openclaw config set provider.apiKey "sk-or-YOUR-KEY-HERE"
openclaw config set provider.model "openrouter/auto"
```

> **OpenRouter's `auto` model** is powered by [NotDiamond](https://openrouter.ai/docs/guides/routing/routers/auto-router) — it analyzes your prompt and routes to the optimal model from a curated set. No extra cost. Also available: `openrouter/auto:floor` (cheapest) and `openrouter/auto:nitro` (fastest).

**Ollama (local models):**
```bash
# Install Ollama first: https://ollama.ai
ollama pull llama3.3:8b  # ~5 GB download, runs on CPU

# Configure OpenClaw
openclaw config set provider.name ollama
openclaw config set provider.apiKey "ollama-local"
openclaw config set provider.model "llama3.3:8b"
```

> **Ollama** runs models entirely on your VPS. No API calls, no cloud, no cost. OpenClaw [auto-detects](https://docs.openclaw.ai/providers/ollama) Ollama at `localhost:11434`.
>
> **Reality check — speed:** Without a GPU, models run on CPU only. On a typical 8-core VPS, expect **8-15 tokens/sec** with a quantized 7B model (Q4_K_M via llama.cpp) — roughly 1-3 words per second. Cloud APIs return 50-100+ tok/sec. Larger models (13B+) drop to 1-5 tok/sec on CPU. Memory bandwidth is the bottleneck, not core count. ([llama.cpp CPU benchmarks](https://github.com/ggml-org/llama.cpp/discussions/3167))
>
> **Reality check — quality:** The gap between a 7B local model and a frontier cloud model is measurable:
>
> | Benchmark | Llama 3.1 8B | Qwen 2.5 7B | Claude Sonnet | GPT-4o |
> |-----------|:------------:|:-----------:|:-------------:|:------:|
> | MMLU (knowledge) | 69 | 75 | 89 | 89 |
> | HumanEval (coding) | 73 | 85 | 92 | 90 |
> | GSM8K (math) | 85 | 92 | 93 | ~95 |
> | MMLU-Pro (hard reasoning) | 47 | 56 | 79 | — |
>
> *Sources: [Meta Llama 3.1 evals](https://github.com/meta-llama/llama-models/blob/main/models/llama3_1/eval_details.md), [Qwen2.5 blog](https://qwenlm.github.io/blog/qwen2.5-llm/), [Anthropic system card](https://anthropic.com/claude-sonnet-4-6-system-card), [OpenAI benchmarks](https://llm-stats.com/benchmarks/humaneval)*
>
> The gap depends on the task: basic math is near-parity, coding is modest (~7 points), but broad knowledge (~14 points) and hard reasoning (~23 points) show frontier models in a different league. Local models are great for experimenting, privacy-sensitive tasks, or as a free fallback — but for daily use where quality matters, an API provider is worth the cost.

### 3.3 Verify Authentication

```bash
# Check provider status
openclaw models status
# Should show your provider — authenticated

# Test with a quick message
openclaw chat --once "Hello, respond with just 'OK'"
# Should print: OK
```

If you see errors, run:

```bash
openclaw doctor
```

### 3.4 Popular Models

| Model | Provider | Best For | Approximate Cost |
|-------|----------|----------|-----------------|
| `claude-sonnet-4` | Anthropic | Daily use — quality + speed balance | ~$3/MTok input |
| `claude-haiku-4` | Anthropic | Automated tasks, simple queries | ~$1/MTok input |
| `claude-opus-4` | Anthropic | Complex reasoning, long context | ~$5/MTok input |
| `gpt-4o` | OpenAI | General purpose, multimodal | ~$2.50/MTok input |
| `gpt-4o-mini` | OpenAI | Budget-friendly, fast | ~$0.15/MTok input |
| `openrouter/auto` | OpenRouter | Cost-optimized routing across all models | Varies by query |
| `google/gemini-2.0-flash` | OpenRouter | Fast, cheap, good for simple tasks | ~$0.10/MTok input |
| `qwen2.5-coder:7b` | Ollama | Local coding model (~4 GB RAM, ~8 tok/s on CPU) | Free |
| `llama3.3:8b` | Ollama | Local general purpose (~5 GB RAM, ~7 tok/s on CPU) | Free |

**Start with one model.** You can always switch later — it's just a config change.

> **Tip:** You can configure multiple models and switch between them. See Phase 13 for cost optimization strategies including model routing.

### ✅ Phase 3 Checkpoint

- [ ] `openclaw models status` shows authenticated with your chosen provider
- [ ] `openclaw chat --once "test"` returns a response
- [ ] API key stored securely (we'll lock down permissions in Phase 7)

---

## Phase 4 — Connect Telegram

> **Why Telegram?** OpenClaw supports Telegram, WhatsApp, IRC, Discord, Slack, and more. Telegram stands out for personal bots: rich markdown formatting, mature and free Bot API, no inbound ports needed (the bot polls Telegram's servers via HTTPS), and DMs are private by default. The `pairing` policy cryptographically ties the bot to your account — after pairing, it ignores everyone else. Zero attack surface from random users.

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

This is your bot. It's running your chosen AI model on your own server, talking to you through Telegram, fully under your control.

**Before continuing:** Stop the gateway for now. We'll set it up as a proper service next.

```bash
openclaw gateway stop
```

> **Everything from here on makes the bot better** — more secure, more capable, more reliable. But it already works. The rest is enhancement.

---

## Phase 6 — Run as a Service

Running OpenClaw as a systemd service means it starts automatically on boot, restarts on crashes, and runs in the background.

### 6.1 Create the Environment File

Secrets go in a root-owned env file, not in `openclaw.json`. Why? The JSON config is readable by the `openclaw` user — and the AI agent has file-read tools. A root-owned env file (0600, loaded by systemd at startup) means the agent can't read its own API keys from disk. Defense in depth.

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

# Security hardening — each directive eliminates a class of attacks.
# Combined, these are more restrictive than Docker defaults.
NoNewPrivileges=true          # No privilege escalation (no setuid/capabilities)
ProtectSystem=strict          # Filesystem read-only except listed paths
ProtectHome=read-only         # Can't modify other users' files
ReadWritePaths=/home/openclaw/.openclaw /home/openclaw/workspace
PrivateTmp=true               # Isolated /tmp (no cross-process tmp attacks)
ProtectKernelTunables=true    # Can't modify /proc/sys
ProtectKernelModules=true     # Can't load kernel modules (no rootkits)
ProtectControlGroups=true     # Can't modify cgroups
RestrictNamespaces=true       # Can't create namespaces (no container escape)
RestrictRealtime=true         # Can't monopolize CPU
MemoryDenyWriteExecute=true   # Can't create W+X memory (blocks shellcode)

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

> **The security philosophy:** *As capable as possible, while as secure as necessary.* The bot runs with `tools.profile: "full"` because a bot that can't do things isn't useful. The real threats aren't capability — they're *self-modification*. The `gateway` tool lets the AI reconfigure itself with zero permission checks. The `nodes`/`sessions` tools add multi-device attack surface with no benefit for a single bot. Deny those. Enable everything else. With Telegram pairing limiting who can message the bot, the attack surface is already small.

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

### 7.2.1 How Permissions Work (The Four-Layer Pipeline)

Tool access is resolved through four layers, applied in sequence. **Each layer can only restrict, never expand:**

```
Layer 1: Tool Profile (base allowlist — "full", "coding", "messaging", "minimal")
    ↓
Layer 2: Provider-specific profiles (tools.byProvider)
    ↓
Layer 3: Global + per-agent allow/deny lists (what you configured above)
    ↓
Layer 4: Sandbox-specific policies
```

**Three rules govern the pipeline:**
1. **Deny always wins.** At every layer, deny overrides allow.
2. **Non-empty allow creates implicit deny.** If you specify `allow: ["read", "exec"]`, everything else is implicitly denied.
3. **Per-agent overrides can only further restrict** — not expand beyond global settings.

For bulk management, OpenClaw provides **tool groups** you can deny/allow as a unit:

| Group | Contains |
|-------|----------|
| `group:runtime` | exec, process |
| `group:fs` | read, write, edit, apply_patch |
| `group:sessions` | Session management tools |
| `group:memory` | memory_search, memory_get |
| `group:web` | web_search, web_fetch |
| `group:automation` | cron, gateway |

> **Why this matters for skills (Phase 11):** Skills cannot escalate permissions. A skill is a teaching document — it guides the agent to use tools that are already available. If a tool is denied, the skill's instructions simply won't work. The defense is this permission pipeline, not the skill itself.
>
> For the full permission model including provider-specific profiles and sandbox policies, see [Reference/SKILLS-AND-TOOLS.md](Reference/SKILLS-AND-TOOLS.md).

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

The **only** way to access the gateway remotely. Tailscale is documented as an alternative, but adds another trust boundary (your traffic routes through their coordination server), another service to maintain, and zero capability you don't already have with SSH. If you later want phone access where SSH tunneling is awkward, it's a single config change — `gateway.tailscale.mode: "serve"`.

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

OpenClaw has a built-in memory system that lets the bot remember things across conversations. Before configuring it, here's how it actually works.

### 9.1 How Memory Works (ELI5)

```
  You write things            The bot reads them later
  in markdown files           when you ask questions
       │                              ▲
       ▼                              │
┌─────────────┐    "index"    ┌──────────────┐    "search"    ┌─────────┐
│  .md files  │ ──────────►  │  Brain DB     │ ──────────►   │ Results │
│  (raw text) │   chop up    │  (SQLite)     │   find best   │ (top 6) │
└─────────────┘   + digest   └──────────────┘   matches      └─────────┘
```

**Writing memories** — The bot's memory lives as plain markdown files in `~/.openclaw/workspace/memory/`. That's it. Plain text. You (or the bot) just write `.md` files in that folder.

**Indexing (the meat grinder)** — When you run `openclaw memory index`, each file gets chopped into chunks (400 tokens each, 80 overlap). A tiny local AI model (`embeddinggemma-300m`, ~329MB) turns each chunk into a list of 768 numbers — an "embedding vector" that captures what the text *means*, not just the words. These vectors get stored in `~/.openclaw/memory/main.sqlite`.

```
    Your .md file
    ┌──────────────────────────────────┐
    │ "I am an OpenClaw bot. I was     │
    │ created by my owner. I engage    │
    │ on Lattice for the Demos         │
    │ protocol..."                     │
    └──────────────────────────────────┘
                  │
                  ▼  CHOP into chunks (400 tokens each)
          ┌───────────┬───────────┬─────┐
          │  Chunk 1  │  Chunk 2  │ ... │
          └─────┬─────┴─────┬─────┴─────┘
                │           │
                ▼           ▼
          ┌─────────────────────────┐
          │   embeddinggemma-300m   │  ◄── tiny AI brain (329MB)
          │   (runs LOCALLY)       │      NO data sent anywhere
          └───────────┬────────────┘
                      │
                turns each chunk into 768 numbers
                      │
                      ▼
          ┌──────────────────────────┐
          │  main.sqlite             │
          │  ┌────┬────────┬───────┐ │
          │  │ id │ text   │ vec   │ │
          │  ├────┼────────┼───────┤ │
          │  │ 1  │ "My na │ [0.2…]│ │
          │  │ 2  │ "I eng │ [0.4…]│ │
          │  └────┴────────┴───────┘ │
          └──────────────────────────┘
```

**Searching (the magic part)** — When the bot gets a question, two searches happen simultaneously:

```
  Question: "What do you know about Lattice?"
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   VECTOR SEARCH           TEXT SEARCH
   (meaning-based)         (word-based)
        │                       │
        │  Turn question        │  Just look for
        │  into 768 numbers,    │  the word "Lattice"
        │  find chunks with     │  in the text
        │  similar numbers      │
        ▼                       ▼
        └───────────┬───────────┘
                    │
                    ▼  COMBINE (hybrid)
              ┌─────────────┐
              │ 70% vector  │  ◄── meaning matters more
              │ 30% text    │  ◄── but exact words help too
              └──────┬──────┘
                     │
                     ▼  then two more tricks:
              ┌─────────────┐
              │ MMR filter  │  ◄── "don't repeat yourself"
              │ (diversity) │      picks DIFFERENT chunks
              └──────┬──────┘
                     │
                     ▼
              ┌─────────────┐
              │ Time decay   │  ◄── newer memories rank higher
              │ (30-day      │      old stuff fades (but never
              │  half-life)  │      fully disappears)
              └──────┬──────┘
                     │
                     ▼
              Top 6 results (if score > 0.35)
              injected into the bot's context
```

**The key idea:** The 768 numbers capture the *meaning* of the text. "Lattice protocol" and "Demos network engagement" would have *similar* numbers even though they use different words.

**TL;DR:**

```
  📝 You write notes in markdown files
       ↓
  🔪 Files get chopped into small pieces
       ↓
  🧠 Tiny local AI turns each piece into a "meaning fingerprint"
       ↓
  💾 Fingerprints stored in a database
       ↓
  🔍 When the bot gets a question, it finds pieces with the most similar fingerprint
       ↓
  💬 Those pieces get stuffed into the prompt so the AI can answer with memories
```

### 9.2 Why We Configure It This Way

OpenClaw ships with memory support, but **the local embedding setup below is NOT the default installation.** Out of the box, OpenClaw uses cloud-based OpenAI embeddings — your conversation text gets sent to OpenAI's API for vectorization. This guide deliberately switches to a local-first setup that requires explicit configuration:

| Choice | Default (Cloud) | This Guide (Local) | Why We Switch |
|--------|-----------------|-------------------|---------------|
| **Embedding provider** | OpenAI API | `embeddinggemma-300m` (local) | No data leaves VPS |
| **Cost** | Per-token API charges | Free | Zero ongoing cost |
| **Privacy** | Text sent to OpenAI | 100% on-machine | Full data sovereignty |
| **Dependencies** | Needs OpenAI API key | Self-contained | One fewer external service |
| **RAM** | None (cloud) | ~4 GB for model | Trade RAM for privacy |

We also evaluated external memory plugins (mem0, memory-lancedb, ClawHub community packages) and concluded none were worth the added complexity or risk. The full analysis is in [Reference/MEMORY-PLUGIN-RESEARCH.md](Reference/MEMORY-PLUGIN-RESEARCH.md).

**Bottom line:** The config below switches embeddings to local and tunes search for quality. It's not the default — it's better.

### 9.3 Memory Configuration

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

### 9.4 Local Embeddings

| Provider | Cost | Privacy |
|----------|------|---------|
| Local (`embeddinggemma-300m`) | Free | Fully private |
| OpenAI / Gemini / Voyage | Per-token | Data sent to third-party API |

**Use local embeddings.** The `embeddinggemma-300m` model (~329MB) is auto-downloaded on first use. Requires 4+ GB RAM.

> **Note:** `openclaw doctor` may show a false-positive about "no local model file found." This is cosmetic. Run `openclaw memory index --force` to verify memory actually works.

### 9.5 Initialize Memory

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

A cron job that catches the 0.0.0.0 binding bug. This exists because of a specific OpenClaw source code issue: when loopback binding fails (port conflict, transient error), the gateway silently falls back to `0.0.0.0` — no warning, no log entry. Your gateway becomes internet-facing without you knowing. This script is a compensating control; if OpenClaw fixes the bug upstream, it becomes a harmless no-op.

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

### 11.1 How Skills Work

Before installing anything, understand what skills actually are. OpenClaw agents gain capabilities through three mechanisms:

| Mechanism | What It Is | Key Property |
|-----------|-----------|-------------|
| **Native tools** | Built-in functions (exec, read, write, etc.) | Execute actions — governed by tool policy |
| **Skills** | SKILL.md instruction files | Educate the agent — guide existing tools |
| **MCP servers** | External processes via Model Context Protocol | Separate process — not yet available (see 11.8) |

**The critical distinction: tools *execute*, skills *educate*.** A skill cannot do anything the agent's tools can't already do — it just teaches the agent HOW to use tools for a specific purpose. This means a malicious skill can't bypass your deny list (Phase 7), but it CAN trick the agent into misusing tools it already has.

**Token cost:** Each loaded skill adds ~24 tokens to the system prompt on every LLM call. Denied tools automatically exclude their associated skills from injection — so your deny list saves tokens too.

### 11.2 Bundled vs. Community Skills

OpenClaw ships with ~50 **bundled skills** inside the npm package. These are official, maintained, and carry no supply chain risk. They're completely separate from the ClawHub community registry (8,600+ skills, but also the target of the "ClawHavoc" campaign — 800+ malicious packages in Feb 2026).

**Key concept:** Bundled skills show as "missing" until their external CLI dependency is installed. Once the binary is in PATH, the skill automatically becomes "ready." No `clawhub install` required.

```bash
openclaw skills list                  # Shows all 50 with status
openclaw skills info <skill-name>     # Shows dependencies
```

### 11.3 Useful Skills for a VPS Bot

| Skill | CLI Dependency | Install Command | What It Does |
|-------|---------------|-----------------|-------------|
| **github** | `gh` | `sudo apt install gh` | GitHub CLI — issues, PRs, code review |
| **gh-issues** | `gh` | (same as above) | Fetch issues, spawn agents for fixes |
| **summarize** | `summarize` | `npm install -g @steipete/summarize` | Summarize URLs, PDFs, YouTube |
| **clawhub** | `clawhub` | `npm install -g clawhub` | Search/install community skills |
| **healthcheck** | (none) | Already ready | System health and audit scheduling |
| **weather** | (none) | Already ready | Weather via wttr.in |
| **tmux** | (none) | Already ready | Remote-control tmux sessions |
| **skill-creator** | (none) | Already ready | Create custom skills (see 11.5) |

Some skills are **macOS-only** and won't work on Linux (peekaboo, imsg, apple-notes, etc.).

### 11.4 Installing Skill Dependencies

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

### 11.5 Creating Custom Skills

When bundled skills don't cover a workflow, create your own. A skill is just a SKILL.md file with YAML frontmatter:

```bash
# Create the skill directory
mkdir -p ~/.openclaw/skills/my-skill/

# Create SKILL.md
cat > ~/.openclaw/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: Brief description of what this teaches the agent
---

# My Skill

## When to Use
- Trigger condition 1
- Trigger condition 2

## How to Use
Step-by-step instructions for the agent...

## Examples
Show the agent concrete examples of invocation and expected output.
EOF

# Verify it loaded (no restart needed)
openclaw skills list | grep my-skill
```

Skills can also include supporting files:

```
my-skill/
├── SKILL.md              # Required — agent instructions
├── scripts/              # Optional — code the agent can exec
├── references/           # Optional — on-demand context (not injected every message)
└── assets/               # Optional — templates, boilerplate
```

> **Tip:** The bundled `skill-creator` skill automates this process. Ask your bot: "Create a skill for [purpose]" and it walks through a six-step workflow.
>
> For the full SKILL.md specification (frontmatter fields, gating via metadata, skill precedence hierarchy), see [Reference/SKILLS-AND-TOOLS.md](Reference/SKILLS-AND-TOOLS.md).

### 11.6 Expanding Capabilities (Decision Framework)

Not everything needs a skill. Use this decision tree when your bot needs a new capability:

```
Need new capability?
  │
  ├── Is it a CLI tool? → Install the binary, document in TOOLS.md
  │                        (simplest path — the exec tool handles it)
  │
  ├── Does it need multi-step guidance? → Create a skill (11.5)
  │                        (structured instructions beyond what TOOLS.md provides)
  │
  ├── Does it need per-agent scoping? → Agent tool overrides
  │                        (different tool profiles for main vs cron agents)
  │
  └── Does it need process isolation / formal tool schemas? → Wait for MCP (11.8)
```

**The simplest expansion** is just installing a CLI binary and telling the bot about it in a workspace TOOLS.md file. The exec tool makes every binary in PATH available — no skill needed for straightforward tools.

### 11.7 Community Skills — Proceed with Caution

If you consider community skills from ClawHub, understand the ecosystem reality:

**The ClawHavoc campaign (Feb 2026):** 824+ malicious skills planted by organized actors. Attack payloads included credential stealers (Atomic macOS Stealer), memory poisoning via SOUL.md/MEMORY.md modifications, and social engineering "prerequisites" that tricked users into running attacker-supplied shell commands. The cleanup removed 2,419 skills. The registry rebounded to 8,630+ — growing faster than moderation can keep up.

**The architectural problem:** Skills run IN-PROCESS with the gateway. No sandboxing. A malicious skill has full access to process memory, API keys, and all tools. Current ClawHub scanning (VirusTotal) catches binary malware but **cannot detect adversarial prompts** in SKILL.md files.

**Vetting checklist before installing any community skill:**

- [ ] Author has 1K+ downloads and is a known community member
- [ ] No VirusTotal flags
- [ ] Manually read the source — no `eval()`, `exec()`, `fetch()` to unknown hosts
- [ ] No npm lifecycle scripts (`preinstall`, `postinstall`)
- [ ] Does not require denied tools
- [ ] Pin exact version after install (`clawhub install skill@1.2.3`)
- [ ] Run `openclaw security audit --deep` after installation

**Recommendation:** Stick with bundled skills. They cover the most common needs. For the full supply chain threat model, attack vectors, and SecureClaw security auditing tool, see [Reference/SKILLS-AND-TOOLS.md](Reference/SKILLS-AND-TOOLS.md).

### 11.8 MCP Servers (Future)

The **Model Context Protocol (MCP)** is a standard for exposing tool schemas via external processes. Unlike skills (which educate the agent using existing tools), MCP servers run as separate child processes with their own code execution — closer to plugins than instruction files.

**Current status:** Native MCP support is not yet in OpenClaw mainline. Community PR #21530 is open and under review (Feb 2026). The `mcpServers` config key is currently ignored.

**When it lands, treat each MCP server as untrusted code.** MCP servers inherit the spawning user's filesystem and network permissions with no built-in tool-level access control. Audit each server package with the same rigor as npm dependencies.

> For proposed configuration format and detailed security implications, see [Reference/SKILLS-AND-TOOLS.md](Reference/SKILLS-AND-TOOLS.md).

### ✅ Phase 11 Checkpoint

- [ ] Understand the three extension mechanisms (tools, skills, MCP)
- [ ] Bundled skills activated for your needs (`openclaw skills list`)
- [ ] Know how to create a custom skill if needed
- [ ] Community skills avoided (or thoroughly vetted)

---

## Phase 12 — Autonomous Engagement (Cron)

OpenClaw's built-in cron system lets the bot perform tasks on a schedule — without user interaction. A bot that only responds when spoken to feels passive; scheduled posts give it persistent presence. The cron runs inside the gateway process (no external scheduler), supports per-job model overrides (Haiku for cheap routine posts), and uses isolated sessions so cron runs can't leak info from private conversations.

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

Even with API key auth and prompt caching, understanding token flow matters. Cron costs compound silently (5 runs/day adds up), subscription metering has rolling windows and weekly caps, and you can't optimize what you don't measure. This phase establishes baselines.

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

## Phase 14 — Context Engineering

Phase 13 showed you where tokens go and what they cost. This phase is about spending them wisely — structuring what the bot sees on every call so it gets maximum value from every token in the context window.

> **Why this matters:** The bot's context window is a fixed budget. Workspace files, memory chunks, conversation history, and tool results all compete for space. Poorly structured context means the bot pays for information it doesn't need while missing information it does. The deep reference for everything in this phase is [Reference/CONTEXT-ENGINEERING.md](Reference/CONTEXT-ENGINEERING.md).

### 14.1 Understand the Context Stack

Every LLM call assembles these components in order:

```
[Tool schemas]                  ← Fixed per session (~5-10K tokens)
[System prompt + workspace]     ← Re-injected every message (~bootstrap files)
[Memory chunks]                 ← Retrieved per-search (up to 6 chunks)
[Conversation history]          ← Grows with each turn
[Latest user message]           ← Always new
```

**Key insight:** Everything in workspace gets re-injected on every single message. This is the biggest lever you can pull.

> **Checkpoint:** Run `/context detail` in your bot. Note which workspace files exist and their sizes.

### 14.2 Trim Workspace Files

The workspace directory (`~/.openclaw/workspace/`) is brute-force injected into every call. Apply this decision framework:

**Keep in workspace** (needed every message):
- Bot identity and personality
- Core behavioral rules
- Security constraints and tool restrictions

**Move to memory** (only needed when relevant):
- Historical facts, project context
- Learned preferences, past conversation summaries
- Reference material, documentation

```bash
# Check your current workspace files
ls -la ~/.openclaw/workspace/

# Check token impact
# In Telegram or CLI:
/context detail
```

> **Rule of thumb:** If removing a file from a random message wouldn't break the bot, it belongs in `memory/` where it gets retrieved by relevance instead of injected every time.

### 14.3 Tune Memory Retrieval

Your memory search config controls how much context the retrieval system adds per call. The current defaults work, but tuning them can reduce noise:

```jsonc
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "query": {
          "maxResults": 6,           // Try 4 — fewer high-quality chunks beat more medium ones
          "minScore": 0.35,          // Try 0.40-0.45 — empty retrieval > noisy retrieval
          "hybrid": {
            "vectorWeight": 0.7,     // Good default for hybrid search
            "textWeight": 0.3,
            "mmr": {
              "enabled": true,       // Deduplicates similar memory chunks
              "lambda": 0.7
            }
          }
        }
      }
    }
  }
}
```

> **How to test:** After changing a value, have a normal conversation and compare response quality. If the bot misses context it used to catch, back off. If responses stay the same or improve, keep the tighter setting.

### 14.4 Session Continuity

Two mechanisms keep context alive across conversations:

**Compaction** — When context nears the window limit, OpenClaw auto-summarizes older history, keeping recent messages verbatim. You can also trigger it manually:
```
/compact Focus on decisions and open questions
```

**Memory flush** — Runs before compaction to persist important facts to `memory/` files before they get summarized away. This is your cross-session continuity mechanism:

```jsonc
{
  "compaction": {
    "memoryFlush": {
      "enabled": true,              // Persist context before compaction discards it
      "softThresholdTokens": 40000  // Trigger at 40K tokens
    }
  }
}
```

Without memory flush, compaction permanently discards older context. With it, key facts survive in memory files and get retrieved in future conversations when relevant.

### 14.5 Context Pruning

Tool results (file reads, web searches) are the fastest-growing context consumer and become irrelevant quickly. Pruning removes stale tool output from the in-memory prompt without rewriting the session transcript:

```jsonc
{
  "contextPruning": {
    "mode": "cache-ttl",
    "ttl": "6h",                    // Tool results expire after 6 hours
    "keepLastAssistants": 3         // Always keep the last 3 responses
  }
}
```

If the bot does heavy tool use, consider a shorter TTL. If conversations are long but tool-light, the defaults work fine.

### 14.6 Cache-Friendly Architecture

When prompt caching is enabled (Phase 13), the structure of your context affects cache hit rates:

- **Static content first, dynamic content last.** Tool schemas and system prompt are cached as a prefix. Memory chunks and conversation history change — they go after.
- **Never modify earlier conversation turns.** The cache depends on prefix stability. Append-only conversations maximize cache hits.
- **Avoid dynamic content in workspace files.** Timestamps, session IDs, or counters that change per-call break the cache prefix, potentially causing zero cache hits (see [OpenClaw issue #19534](https://github.com/openclaw/openclaw/issues/19534)).

> **Verify caching works:** After a conversation, check your API logs or ClawMetry for `cache_read_input_tokens > 0`. If it's always zero, dynamic content in the system prompt may be breaking the cache.

### 14.7 Priority Checklist

In order of impact:

1. Enable prompt caching (`cacheRetention: "long"`) — Phase 13.2
2. Verify cache hits are actually occurring — check `cache_read_input_tokens`
3. Audit workspace files with `/context detail` — move non-essential files to memory
4. Enable `memoryFlush` — preserves context across sessions
5. Test raising `minScore` to 0.40 — reduces low-relevance memory noise
6. Enable MMR — deduplicates similar memory chunks
7. Test reducing `maxResults` to 4 — less context waste if quality holds
8. Monitor token distribution via ClawMetry — data-driven tuning from here

> **Deep reference:** [Reference/CONTEXT-ENGINEERING.md](Reference/CONTEXT-ENGINEERING.md) has the full internals — bootstrap injection mechanics, memory search pipeline, cache invalidation rules, and context overflow handling.

---

## Known Tradeoffs & Open Questions

Transparency about what's still being evaluated:

1. **`tools.deny` completeness** — The deny list blocks known-dangerous tools (gateway, nodes, sessions), but OpenClaw has 50+ tools. New tools may be added in updates. Review new tool additions after each OpenClaw update.

2. **Haiku quality for autonomous posts** — Cron jobs use Haiku to save costs. Whether Haiku produces posts that meet quality standards over time requires monitoring. If quality degrades, reverting to Sonnet is a single cron edit.

3. **Long-term maintenance** — OpenClaw is transitioning to a foundation model after its creator joined OpenAI (Feb 2026). How this affects release cadence, security patches, and backward compatibility is unknown. This guide is designed to be resilient to upstream changes: version pinning, minimal external dependencies, bundled-only skills.

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
│  │       │       │ Your LLM │  │ Local    │             │  │
│  │       │       │ Provider │  │ Embeddings│             │  │
│  │       │       │ API      │  │ gemma-300m│             │  │
│  │       │       └──────────┘  └──────────┘             │  │
│  └───────┼───────────────────────────────────────────────┘  │
│          │                                                   │
│          │ HTTPS (Bot API polling)                            │
│          ▼                                                   │
│  api.telegram.org              your-provider-api.com          │
│                                                              │
│  SSH tunnel ◄──── Local machine (management)                  │
└──────────────────────────────────────────────────────────────┘
```

**Key points:**
- Gateway binds to **loopback only** — never exposed to the internet
- Outbound only: Telegram Bot API + your LLM provider API
- Management via **SSH tunnel** — no public Control UI
- **Capability-first:** `tools.profile "full"` with targeted deny list

---

## Appendix B — Async Pipeline (Local ↔ Bot)

A file-based message queue for delegating tasks between your local machine and the bot. Why files over a real-time API? SSH is already there (no new auth, ports, or software), JSON files are inspectable with `ls`/`cat`/`jq`, processed messages move to `ack/` for a full audit trail, and the tasks it handles (summarize, scan, research) aren't time-critical — the bottleneck is human attention, not message latency.

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

These are listed not because they're currently exploitable (all patched) but for three reasons: version pinning (you know the minimum safe version), attack pattern awareness (CVE-2026-25253 reveals fragility in the WebSocket auth model — that class of vulnerability may recur), and audit context (when `openclaw security audit --deep` runs, you understand what it's checking).

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

### Providers & Model Research

- [OpenClaw Ollama Provider](https://docs.openclaw.ai/providers/ollama) — Official Ollama integration docs
- [OpenRouter Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router) — Smart routing powered by NotDiamond
- [OpenRouter Free Models Router](https://openrouter.ai/docs/guides/routing/routers/free-models-router) — Zero-cost model access
- [OpenRouter Integration Guide](https://openrouter.ai/docs/guides/guides/openclaw-integration) — OpenClaw-specific setup
- [Ollama Hardware Guide](https://www.arsturn.com/blog/ollama-hardware-guide-what-you-need-to-run-llms-locally) — CPU, GPU & RAM requirements
- [Running LLMs on VPS Without GPU](https://mangohost.net/blog/how-to-run-llama-3-or-ollama-on-a-vps-without-a-gpu-the-no-nonsense-guide-for-ai-tinkerers/) — Practical CPU-only guide
- [RAM Requirements for Local LLMs](https://apxml.com/courses/getting-started-local-llms/chapter-2-preparing-local-environment/hardware-ram) — Model size to memory mapping
- [Complete Guide to Running LLMs Locally](https://www.ikangai.com/the-complete-guide-to-running-llms-locally-hardware-software-and-performance-essentials/) — Hardware and performance essentials

### Memory System Research

- [Reference/MEMORY-PLUGIN-RESEARCH.md](Reference/MEMORY-PLUGIN-RESEARCH.md) — Full mem0 evaluation and built-in memory optimization strategy

---

*Config schemas verified against [docs.openclaw.ai/gateway/configuration-reference.md](https://docs.openclaw.ai/gateway/configuration-reference.md).*
