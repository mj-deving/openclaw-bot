# Standalone-Host Runbook — 1 to 3 OpenClaw Bots on a Fresh VPS

A copy-paste runbook for bringing up 1-3 OpenClaw bots on a dedicated
VPS (no demos-node or other foreign tenants to work around). Baked in:
every gotcha learned during the 2026-04-24 Gregor rebuild.

Target: fresh Ubuntu 24.04 LTS VPS → first bot answering Telegram DMs
in ~30 minutes. Each additional bot on the same host adds ~10 minutes.

For a deeper dive into why each piece exists, see `GUIDE.md`.
For architecture and config conventions, see `CLAUDE.md`.

---

## 1. Pick a VPS

| Load | CPU | RAM | Swap | Disk | Example |
|---|---|---|---|---|---|
| 1 bot | 2 vCPU | 4 GB | 2 GB | 20 GB | Hetzner CX22 |
| 2-3 bots | 4 vCPU | 8 GB | 4 GB | 40 GB | Hetzner CX32 |
| 2-3 bots + local LLM compaction | 6-8 vCPU | 16 GB | 4 GB | 60 GB | Hetzner CX42 |

OS: Ubuntu 24.04 LTS or Debian 12. Public IPv4 required (for Telegram
long-poll outbound + provider API calls). IPv6 optional.

**Do not skip swap.** Today's debug session traced to OOM-killing when
another tenant's process leaked memory. Even 2 GB of swap buys graceful
degradation instead of silent terminated-process errors.

---

## 2. Initial host setup (as root)

```bash
# 2.1 — updates + baseline tools
apt-get update && apt-get -y upgrade
apt-get install -y ufw python3 python3-pip zstd git

# 2.2 — add swap if provider didn't (skip if free -h shows Swap > 0)
fallocate -l 4G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
free -h

# 2.3 — firewall (before bots; you can still SSH during setup)
ufw allow 22/tcp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# 2.4 — Node.js 22 LTS via NodeSource
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
node --version   # expect v22.x
```

---

## 3. Create bot users

Repeat for each bot. Example for Gregor + Dismas:

```bash
# 3.1 — create users with locked passwords (key-only auth)
useradd -m -s /bin/bash openclaw
useradd -m -s /bin/bash dismas
passwd -l openclaw
passwd -l dismas

# 3.2 — give your SSH key access (repeat for each user)
mkdir -p /home/openclaw/.ssh /home/dismas/.ssh
echo "<paste your pubkey>" >> /home/openclaw/.ssh/authorized_keys
echo "<paste your pubkey>" >> /home/dismas/.ssh/authorized_keys
chown -R openclaw:openclaw /home/openclaw/.ssh
chown -R dismas:dismas /home/dismas/.ssh
chmod 700 /home/openclaw/.ssh /home/dismas/.ssh
chmod 600 /home/openclaw/.ssh/authorized_keys /home/dismas/.ssh/authorized_keys

# 3.3 — enable user-systemd persistence across reboots (for Ollama + ad-hoc user services)
loginctl enable-linger openclaw
loginctl enable-linger dismas
```

Add SSH aliases to your local `~/.ssh/config`:

```
Host gregor-vps
    HostName <vps-ip>
    User openclaw
    IdentityFile ~/.ssh/<key>
    IdentitiesOnly yes

Host dismas-vps
    HostName <vps-ip>
    User dismas
    IdentityFile ~/.ssh/<key>
    IdentitiesOnly yes
```

---

## 4. Install scoped sudo wrappers (recommended)

On a standalone host with no foreign tenant to protect, you can skip
this and give each bot `NOPASSWD: ALL`. But keeping the wrapper pattern
gives you auditable, reproducible privilege surfaces and makes future
multi-tenant migration trivial.

```bash
# 4.1 — as root on the VPS
cd /root
git clone https://github.com/mj-deving/openclaw-hardened.git
cd openclaw-hardened/src/scripts/vps-admin-wrappers

# 4.2 — review + install for openclaw
./install-wrappers.sh

# verify
sudo -l -U openclaw
```

For Dismas, duplicate the pattern: create a parallel set of
`dismas-*` wrappers and `/etc/sudoers.d/dismas-restricted-admin`.
See the commit history for the `openclaw-*` wrapper set for the
template (same file structure, s/openclaw/dismas/ and different
unit-install destinations).

---

## 5. Install shared Ollama (embedding + optional compaction)

Ollama runs under one user on loopback; all bots point at
`127.0.0.1:11434`. Embedding requests carry just the query text — no
cross-bot data leakage.

Pick a host user for Ollama. Simplest: use the first bot user
(`openclaw`) since Ollama is small and its service will persist
alongside the bot's other user-systemd units.

```bash
# 5.1 — as openclaw
mkdir -p ~/.local/bin ~/.local/share/ollama

# 5.2 — fetch the LATEST release URL programmatically
cd /tmp
TAG=$(curl -s https://api.github.com/repos/ollama/ollama/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
echo "installing Ollama $TAG"
curl -fsSL -o ollama.tar.zst "https://github.com/ollama/ollama/releases/download/${TAG}/ollama-linux-amd64.tar.zst"

# 5.3 — extract (note: zstd archive, not tgz; the official tgz URL 404s)
tar --use-compress-program=unzstd -xf ollama.tar.zst -C ~/.local/share/ollama/
rm ollama.tar.zst
ln -sf ~/.local/share/ollama/bin/ollama ~/.local/bin/ollama
grep -q ".local/bin" ~/.profile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
export PATH="$HOME/.local/bin:$PATH"
ollama --version

# 5.4 — install the user-level systemd unit
mkdir -p ~/.config/systemd/user
cp /root/openclaw-hardened/src/config/systemd-templates/ollama.service \
   ~/.config/systemd/user/ollama.service
# (if repo isn't in openclaw's home, scp the template over first)

systemctl --user daemon-reload
systemctl --user enable --now ollama.service
systemctl --user status ollama.service --no-pager --lines=3

# 5.5 — pull embedding model
ollama pull nomic-embed-text:v1.5

# 5.6 — (optional) pull local summarizer for compaction
# skip this if you're using OpenRouter for compaction
ollama pull qwen3:4b-instruct-2507
```

Verify:

```bash
curl -s http://127.0.0.1:11434/api/embed \
  -d '{"model":"nomic-embed-text:v1.5","input":"hello"}' \
  | python3 -c 'import json,sys; e=json.load(sys.stdin)["embeddings"][0]; print("dims:", len(e))'
# expect: dims: 768
```

---

## 6. Per-bot deployment

Everything below applies to one bot. Repeat for each.
Example uses `openclaw`/Gregor; swap names for each bot.

### 6.1 — Install the OpenClaw CLI (as the bot user)

```bash
# as openclaw
mkdir -p ~/.npm-global
npm config set prefix "$HOME/.npm-global"
grep -q npm-global ~/.profile || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.profile
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g openclaw
openclaw --version
mkdir -p ~/.openclaw/credentials ~/.openclaw/agents/main/agent ~/.openclaw/workspace/memory
```

### 6.2 — Stage the provider auth

**OAuth providers (Codex, Anthropic setup-token)** require a local
browser auth flow; the auth-profiles.json file then SCPs to the VPS:

```bash
# from your local machine
openclaw setup  # or the provider-specific login command
# authenticate in browser, confirm ~/.openclaw/agents/main/agent/auth-profiles.json exists locally
scp ~/.openclaw/agents/main/agent/auth-profiles.json \
    gregor-vps:/home/openclaw/.openclaw/agents/main/agent/auth-profiles.json
ssh gregor-vps chmod 600 ~/.openclaw/agents/main/agent/auth-profiles.json
```

**API-key providers (OpenRouter, direct OpenAI, etc.)**: extend the
file via stdin so the key never appears in shell history or argv:

```bash
# from your local machine — assumes OPENROUTER_API_KEY is in local env
python3 -c "
import os, json
print(json.dumps({'provider': 'openrouter', 'type': 'api_key', 'apiKey': os.environ['OPENROUTER_API_KEY']}))
" | ssh gregor-vps 'python3 -c "
import json, sys, os
new = json.loads(sys.stdin.read())
path = \"/home/openclaw/.openclaw/agents/main/agent/auth-profiles.json\"
p = json.load(open(path)) if os.path.exists(path) else {\"version\": 1, \"profiles\": {}}
p[\"profiles\"][\"openrouter:<your-id>\"] = new
with open(path, \"w\") as f:
    json.dump(p, f, indent=2)
os.chmod(path, 0o600)
print(\"profiles:\", list(p[\"profiles\"].keys()))
"'
```

### 6.3 — Write openclaw.json

The skeleton below is the research-tuned minimum. Fill in the
capitalised placeholders before shipping it to the VPS.

Key gotchas baked in:
- `agents.defaults.model` is **singular string**, not `models` map (map silently falls back to `openai/...` provider lookup)
- `channels.telegram.streaming` is an **object** `{mode: "off"}`, not a string
- `channels.telegram.allowFrom` is the allowlist field (not `dmAllowUsers`)
- `channels.telegram.groupPolicy` is **required**
- `memorySearch.minScore: 0.55` (community norm; default 0.35 is too loose)
- `memorySearch.query.hybrid.temporalDecay.halfLifeDays: 45` for personal assistants

```bash
ssh gregor-vps 'python3 <<PYEOF
import json, os, secrets
config = {
    "meta": {"lastTouchedVersion": "2026.4.22"},
    "auth": {
        "profiles": {
            # Provider profiles declared here must also exist in
            # auth-profiles.json with their actual credentials.
            "openai-codex:YOUR@EMAIL": {"provider": "openai-codex", "mode": "oauth"},
            "openrouter:YOUR-ID": {"provider": "openrouter", "mode": "api_key"}
        }
    },
    "agents": {
        "defaults": {
            "model": "openai-codex/gpt-5.4",   # SINGULAR — required for Codex
            "maxConcurrent": 4,
            "subagents": {"maxConcurrent": 8},
            "memorySearch": {
                "enabled": True,
                "provider": "ollama",
                "model": "nomic-embed-text:v1.5",
                "remote": {"baseUrl": "http://127.0.0.1:11434"},
                "sources": ["memory"],
                "store": {"vector": {"enabled": True}},
                "query": {
                    "maxResults": 6,
                    "minScore": 0.55,
                    "hybrid": {
                        "vectorWeight": 0.7,
                        "textWeight": 0.3,
                        "candidateMultiplier": 4,
                        "mmr": {"enabled": True, "lambda": 0.7},
                        "temporalDecay": {"enabled": True, "halfLifeDays": 45}
                    }
                }
            },
            "compaction": {
                "mode": "safeguard",
                "provider": "openrouter",
                "model": "anthropic/claude-haiku-4-5",
                "keepRecentTokens": 20000,
                "reserveTokens": 8000,
                "memoryFlush": {
                    "enabled": True,
                    "softThresholdTokens": 40000,
                    "prompt": "Write any lasting notes to memory/YYYY-MM-DD.md (use todays date); reply with NO_REPLY if nothing to store."
                },
                "qualityGuard": {"enabled": True},
                "timeoutSeconds": 60
            }
        }
    },
    "tools": {
        "profile": "full",
        "alsoAllow": ["cron"],
        "deny": ["gateway", "nodes", "sessions_spawn", "sessions_send"],
        "web": {"search": {"enabled": True}, "fetch": {"enabled": True}},
        "elevated": {"enabled": False},
        "exec": {"security": "full", "ask": "off"}
    },
    "channels": {
        "telegram": {
            "enabled": True,
            "botToken": "PASTE_BOTFATHER_TOKEN_HERE",
            "dmPolicy": "allowlist",
            "allowFrom": [YOUR_TELEGRAM_USER_ID],
            "groupPolicy": "allowlist",
            "groups": {},
            "errorPolicy": "once",
            "errorCooldownMs": 30000,
            "streaming": {"mode": "off"}
        }
    },
    "gateway": {
        "port": 18789,  # change per bot: 18789, 18790, 18791, ...
        "mode": "local",
        "bind": "loopback",
        "auth": {
            "mode": "token",
            "token": secrets.token_urlsafe(32),
            "rateLimit": {"maxAttempts": 10, "windowMs": 60000, "lockoutMs": 300000, "exemptLoopback": True}
        }
    },
    "plugins": {
        "enabled": True,
        "slots": {"memory": "memory-core"},
        "entries": {
            "telegram": {"enabled": True},
            "device-pair": {"enabled": True},
            "memory-core": {"enabled": True},
            "memory-lancedb": {"enabled": False}
        }
    }
}
path = "/home/openclaw/.openclaw/openclaw.json"
with open(path, "w") as f: json.dump(config, f, indent=2)
os.chmod(path, 0o600)
PYEOF
openclaw config validate'
```

### 6.4 — Install systemd unit + hardening drop-in

```bash
# 6.4a — stage the unit files (as the bot user)
ssh gregor-vps 'mkdir -p ~/staging'
scp src/config/systemd-templates/openclaw.service gregor-vps:/home/openclaw/staging/openclaw.service
scp src/config/systemd-templates/hardening.conf   gregor-vps:/home/openclaw/staging/hardening.conf

# For a second bot, edit the copies in ~/staging/ first:
#   - change `openclaw.service` to `dismas.service` (service name)
#   - change User=/Group=/WorkingDirectory= to dismas
#   - change port 18789 -> 18790
#   - hardening.conf ReadWritePaths=/home/openclaw -> /home/dismas
#   - Description field

# 6.4b — install via scoped wrappers (requires sudoers drop-in from step 4)
ssh gregor-vps 'sudo /usr/local/sbin/openclaw-install-unit
sudo /usr/local/sbin/openclaw-install-hardening
sudo /usr/local/sbin/openclaw-gateway-enable'
```

If you skipped the scoped-wrapper pattern, install as root directly:

```bash
# as root
install -m 0644 -o root -g root /home/openclaw/staging/openclaw.service /etc/systemd/system/openclaw.service
mkdir -p /etc/systemd/system/openclaw.service.d
install -m 0644 -o root -g root /home/openclaw/staging/hardening.conf /etc/systemd/system/openclaw.service.d/hardening.conf
systemctl daemon-reload
systemctl enable openclaw
```

### 6.5 — Start + verify

```bash
ssh gregor-vps 'sudo /usr/local/sbin/openclaw-gateway-start'
# ... or: sudo systemctl start openclaw

# wait ~30s for first-boot plugin installs (subsequent starts take ~10s)
sleep 30

ssh gregor-vps 'systemctl is-active openclaw
ss -tlnp 2>/dev/null | grep 18789
export PATH="$HOME/.npm-global/bin:$PATH"
openclaw channels status --probe
openclaw memory status | head -6
openclaw capability model run --model openrouter/anthropic/claude-haiku-4-5 --prompt "Reply with exactly: OK"'
```

Expected:

```
active
LISTEN 0  511  127.0.0.1:18789  ...
- Telegram default: ..., connected, mode:polling, bot:@yourbot, ..., works
Memory Search (main)
Provider: ollama (requested: ollama)
Model: nomic-embed-text:v1.5
...
OK
```

### 6.6 — First DM test

Send a DM from the allowlisted user to the bot. Watch:

```bash
ssh gregor-vps 'sudo /usr/local/sbin/openclaw-gateway-logs | tail -20'
```

You should see `[telegram] ... message from ...` and
`[telegram] sendMessage ok chat=YOUR_ID ...` within ~5s.

---

## 7. Repeat for bots 2 and 3

Same six sub-steps in §6, with these per-bot diffs:

- Bot user (`dismas`, `bot3`, ...)
- Telegram bot token + user allowlist
- Gateway port (18790, 18791, ...)
- Service name everywhere (`dismas.service`, `bot3.service`)
- `ReadWritePaths=/home/<user>` in hardening.conf
- Separate set of scoped wrappers (or share root-direct install)

Each bot gets its own auth profile (or shares the same OpenRouter key —
separate profile names either way, like `openrouter:gregor` and
`openrouter:dismas`).

Ollama is shared. No per-bot Ollama instance needed.

---

## 8. Post-setup hardening (optional, recommended)

- **Per-user egress filtering** — restrict each bot user to HTTPS + DNS
  outbound only. See GUIDE §7.4.
- **auditd** on `~/.openclaw/openclaw.json` + `~/.openclaw/agents/*/auth-profiles.json`.
  See GUIDE §7.15.
- **Defense plugin** — install the 6-layer prompt-injection defense.
  See `Reference/DEFENSE-SYSTEM.md`.
- **ClawKeeper** for continuous config drift detection.
  See `Reference/CLAWKEEPER.md`.
- **Revoke install-phase sudoers** — remove `openclaw-install-nodejs`
  and `openclaw-install-ufw` entries from sudoers drop-in once install
  is verified. One-time tools, no reason to leave them granted.

---

## 9. Known gotchas (cheat sheet)

| Symptom | Cause | Fix |
|---|---|---|
| "No API key found for provider openai" | Auth profile at `~/.openclaw/auth-profiles.json` instead of per-agent path | Move to `~/.openclaw/agents/main/agent/auth-profiles.json` |
| `agent model: openai/gpt-5.4` when expected Codex | Used `models` map in config | Use `agents.defaults.model` singular string |
| Every CLI command spits validation error | Invalid config file | `openclaw config validate` for clean error |
| Gateway active but no Telegram activity | Codex ACP can't write to `~/.codex/` | Ensure `ReadWritePaths=/home/<user>` covers whole home |
| `systemd-analyze verify` fails on install-unit | Wrapper's tmpfile missing .service suffix | Use private tmpdir + correct filename (fixed in ef5a291) |
| `agents.defaults: Unrecognized key authProfile` | Wrong field path | Auth profiles go under top-level `auth.profiles`, not under `agents.defaults` |
| Telegram "channels.telegram: additional properties" | Used invalid field names | Check `openclaw config schema` for the valid list |
| `error=terminated` on every Codex run | OOM-killed | Add swap; cap RAM per service with `MemoryMax=` |
| Ollama service dies on reboot | `Linger=no` | `loginctl enable-linger <user>` (root, one-time) |
| Plugin install fails on restart loop | `ReadWritePaths` too narrow | Widen to full user home |
| "Failed to prepare filename .../...: Invalid argument" | tmpfile without unit-type suffix | See install-unit wrapper fix |

---

## 10. Total time estimate

| Step | Time |
|---|---|
| §1 pick VPS, provision | 5 min |
| §2 host setup | 5 min |
| §3 users | 3 min |
| §4 wrappers | 3 min |
| §5 Ollama + embedding model | 8 min (mostly download) |
| §6 first bot | 10 min |
| §7 each additional bot | 8 min |
| §8 optional hardening | +30 min |

**First bot answering DMs: ~35 minutes from fresh VPS.**
**Each additional bot on the same host: +8 minutes.**

---

## See also

- `GUIDE.md` — comprehensive setup guide with deep rationale (15 phases, 3 parts, 8 appendices)
- `CLAUDE.md` — architecture, conventions, ongoing-ops commands
- `Reference/COST-AND-ROUTING.md` — provider pricing, model routing
- `Reference/CONTEXT-ENGINEERING.md` — memory + compaction deep dive
- `Reference/IDENTITY-AND-BEHAVIOR.md` — system-prompt engineering
- `src/scripts/vps-admin-wrappers/` — scoped sudo wrappers (source)
- `src/config/systemd-templates/` — reference unit + hardening templates
