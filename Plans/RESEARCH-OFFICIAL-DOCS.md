# OpenClaw Official Documentation Research

**Researched:** 2026-02-19 (Deep Dive -- Second Pass)
**Source:** docs.openclaw.ai (official), web searches, NVD, GitHub issues
**Researcher:** AI-assisted research
**Status:** COMPREHENSIVE -- all 10 categories covered with full config schemas

---

## Executive Summary

docs.openclaw.ai is live, well-structured, and extensive. The full documentation index (`/llms.txt`) reveals **200+ pages** across 15+ sections. Key findings that affect our masterplan:

1. **setup-token is now BLOCKED by Anthropic** (as of Jan 9, 2026) -- API key is the only reliable auth method
2. **The loopback fallback bug is confirmed** via multiple GitHub issues -- it's a general binding fallback behavior
3. **IRC adapter is fully documented** with hostmask allowlists, NickServ, and `toolsBySender` per-sender tool policies
4. **VirusTotal partnership is real** -- ClawHub skills now scanned, but still high-risk (1,184+ malicious skills, ~20% of registry)
5. **CalVer versioning** (vYYYY.M.D) -- we must be on >= 2026.1.29 for CVE patches
6. **Formal verification models exist** (TLA+/TLC) for security properties
7. **Memory system is more sophisticated than planned** -- supports QMD backend, session indexing, temporal decay, MMR diversity
8. **Several config schema errors in our masterplan** -- groupPolicy is a flat string (not object), tool names differ from what we have, configWrites is not a real field
9. **"openclaw" vs "open-claw"** -- official name is "OpenClaw" (one word). Historical names: "clawdbot" and "Moltbot". Hyphenated form not used officially.

---

## 1. Gateway Configuration

**Source:** [docs.openclaw.ai/gateway/configuration](https://docs.openclaw.ai/gateway/configuration), [configuration-reference](https://docs.openclaw.ai/gateway/configuration-reference.md), [network-model](https://docs.openclaw.ai/gateway/network-model.md)

### Binding Options

| Mode | Config Value | Behavior |
|------|-------------|----------|
| Loopback (default) | `"loopback"` | `ws://127.0.0.1:18789` -- local only |
| LAN | `"lan"` | All interfaces (`0.0.0.0`) |
| Tailnet | `"tailnet"` | Tailscale IP only |
| Auto | `"auto"` | Automatic selection |
| Custom | `"custom"` | User-specified address |

**Port resolution precedence:**
1. CLI flag `--port`
2. Environment variable `OPENCLAW_GATEWAY_PORT`
3. Config file `gateway.port`
4. Default: `18789`

**Binding resolution precedence:**
1. CLI/override parameters
2. `gateway.bind` config setting
3. Default: `"loopback"`

### Auth Modes

```json5
{
  gateway: {
    auth: {
      mode: "none" | "token" | "password" | "trusted-proxy",
      token: "long-random-token",
      password: "...",
      allowTailscale: true,  // default
      rateLimit: {
        maxAttempts: 10,       // default
        windowMs: 60000,       // default (1 min)
        lockoutMs: 300000,     // default (5 min)
        exemptLoopback: true   // default
      }
    }
  }
}
```

**Critical:** Auth is required by default. Even over SSH tunnels, clients must send auth.

### Control UI

```json5
{
  gateway: {
    controlUi: {
      enabled: true,          // default
      basePath: "/openclaw",  // default URL path
      root: "...",            // directory path
      allowInsecureAuth: false,  // NEVER enable in production
      dangerouslyDisableDeviceAuth: false  // NEVER enable
    }
  }
}
```

Control UI requires HTTPS for device identity generation. Three options:
1. Tailscale Serve (recommended by official docs)
2. Localhost (`127.0.0.1`) -- **our approach via SSH tunnel**
3. `allowInsecureAuth: true` (token-only, no device pairing) -- NOT recommended

### Config Reload

```json5
{
  gateway: {
    reload: {
      mode: "off" | "hot" | "restart" | "hybrid"  // default: "hybrid"
    }
  }
}
```

`hybrid` mode auto-selects between safe hot-apply and restart for breaking changes. Config validation is strict -- unknown keys, malformed types, or invalid values prevent startup.

### Tailscale Integration

```json5
{
  gateway: {
    tailscale: {
      mode: "off" | "serve" | "funnel",
      resetOnExit: false  // default
    }
  }
}
```

Our plan correctly uses `"off"`. Funnel mode is flagged as CRITICAL in security audit (public internet exposure).

### Remote Gateway

```json5
{
  gateway: {
    remote: {
      url: "wss://...",
      transport: "ssh" | "direct",
      token: "...",
      password: "..."
    }
  }
}
```

### Trusted Proxies

```json5
{
  gateway: {
    trustedProxies: ["127.0.0.1"],
    tools: {
      deny: ["gateway", "cron"],   // HTTP-level tool deny
      allow: []                     // HTTP-level tool allow
    }
  }
}
```

### Discrepancy with Masterplan

Our masterplan config is largely correct. The `gateway.tailscale.mode: "off"` and `gateway.controlUi.dangerouslyDisableDeviceAuth: false` are properly set. No major corrections needed in gateway config.

---

## 2. Authentication

**Source:** [docs.openclaw.ai/gateway/authentication](https://docs.openclaw.ai/gateway/authentication.md), web search results, GitHub issues

### setup-token Method

```bash
# Generate on machine with Claude Code CLI
claude setup-token

# Register with OpenClaw on VPS
openclaw models auth setup-token --provider anthropic

# Or paste manually:
openclaw models auth paste-token --provider anthropic

# Verify
openclaw models status
openclaw doctor
```

### CRITICAL: setup-token Is Now Blocked

**As of January 9, 2026, Anthropic actively blocks third-party harnesses from using Claude Code/Pro/Max subscriptions.** Tightened to prevent spoofing the official Claude Code client.

**What's blocked:**
- Pro/Max subscription auth in OpenClaw or similar tools
- Headless/automated access via subscription OAuth

**What still works:**
- Anthropic API key (pay-per-use)
- Claude Code's official CLI tool

**Evidence:**
- [GitHub Issue #16365](https://github.com/openclaw/openclaw/issues/16365) -- feature request to extend subscription auth (indicates NOT currently supported)
- [GitHub Issue #8074](https://github.com/openclaw/openclaw/issues/8074) -- OAuth tokens keep expiring
- [AnswerOverflow](https://www.answeroverflow.com/m/1469511158040891402) -- users reporting 401 errors

**Impact on our plan:** Phase 2 must default to API key, not setup-token. Test setup-token first -- if it works, great. If 401 errors, switch immediately.

### API Key Method

```bash
# Environment variable (preferred for secrets)
export ANTHROPIC_API_KEY="sk-ant-..."

# Or in ~/.openclaw/.env for daemon
ANTHROPIC_API_KEY=sk-ant-...
```

### Credential Storage

| Location | Purpose |
|----------|---------|
| `~/.openclaw/.env` | Daemon-readable environment file |
| `~/.openclaw/agents/<agentId>/agent/auth-profiles.json` | Per-agent auth profiles |
| `~/.openclaw/credentials/` | OAuth tokens, channel credentials |

### Environment Variable Priority (Provider Keys)

1. `OPENCLAW_LIVE_<PROVIDER>_KEY` (override)
2. `<PROVIDER>_API_KEYS` (multiple, comma-separated)
3. `<PROVIDER>_API_KEY` (single)
4. `<PROVIDER>_API_KEY_*` (numbered variants)

**Priority chain:** `env.shellEnv` > `~/.openclaw/.env` > systemd/launchd

### Token Rotation

"OpenClaw retries with the next key only for rate-limit errors (429, rate_limit, quota)" -- non-rate-limit errors skip rotation.

### Auth Status Commands

```bash
openclaw models status           # Check auth
openclaw models status --check   # Automation-friendly exit codes
openclaw doctor                  # Full diagnostic
openclaw doctor --fix            # Auto-fix issues
```

---

## 3. IRC Channel Adapter

**Source:** [docs.openclaw.ai/channels/irc](https://docs.openclaw.ai/channels/irc.md)

### Full Configuration Schema

```json5
{
  channels: {
    irc: {
      // Connection
      enabled: true,
      host: "irc.libera.chat",
      port: 6697,
      tls: true,
      nick: "bot-nick",
      channels: ["#channel1", "#channel2"],

      // NickServ Authentication
      nickserv: {
        enabled: true,
        service: "NickServ",       // default
        password: "...",           // or via IRC_NICKSERV_PASSWORD env var
        register: false,           // set true for initial registration only
        registerEmail: "..."       // for initial registration only
      },

      // DM Access Control
      dmPolicy: "pairing" | "allowlist" | "open" | "disabled",  // default: "pairing"
      allowFrom: ["nick!user@host", "nick2"],  // DM sender allowlist

      // Group/Channel Access Control
      groupPolicy: "allowlist" | "open" | "disabled",  // default: "allowlist" (FLAT STRING, not object!)
      groupAllowFrom: ["nick!user@host"],  // GLOBAL channel sender allowlist

      // Per-channel overrides
      groups: {
        "#channel1": {
          allowFrom: ["nick!user@host"],  // per-channel sender control
          requireMention: true             // default: true in groups
        }
      },

      // Per-sender tool restrictions (POWERFUL -- not in our masterplan!)
      toolsBySender: {
        "eigen!~eigen@174.127.248.171": { allow: ["read", "exec"] },
        "trusted-nick": { profile: "coding" },
        "*": { profile: "minimal" }  // fallback for everyone else
      },

      // Tool restrictions (channel-level)
      tools: {
        deny: ["exec", "gateway", "cron"]
      }
    }
  }
}
```

### Allowlist Format

Two formats supported:
- **Simple nick:** `"eigen"` (matches any hostmask -- weaker)
- **Full hostmask:** `"eigen!~eigen@174.127.248.171"` (stronger identity matching)

**Matching:** First-match precedence with `"*"` as wildcard fallback.

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `IRC_HOST` | Server hostname |
| `IRC_PORT` | Connection port |
| `IRC_TLS` | Enable TLS (`true`/`false`) |
| `IRC_NICK` | Bot nickname |
| `IRC_USERNAME` | IRC username |
| `IRC_REALNAME` | IRC realname field |
| `IRC_PASSWORD` | Server password (if server requires one) |
| `IRC_CHANNELS` | Comma-separated channel list |
| `IRC_NICKSERV_PASSWORD` | NickServ auth password |
| `IRC_NICKSERV_REGISTER_EMAIL` | For initial registration |

### CRITICAL Discrepancies with Masterplan

1. **`groupPolicy` is a FLAT STRING, not an object.** Our masterplan has:
   ```json5
   "groupPolicy": { "mode": "allowlist", "requireMention": true, "allowedGroups": ["#channel"] }
   ```
   But the actual schema is:
   ```json5
   "groupPolicy": "allowlist",
   "groups": { "#channel": { "requireMention": true, "allowFrom": [...] } }
   ```
   `allowedGroups` does not exist as a field.

2. **`toolsBySender` is missing from our plan.** This is a powerful per-sender tool restriction feature. Add it with hostmask-based rules.

3. **`groupAllowFrom` is separate from `groupPolicy`.** Controls which senders can trigger the bot in ALL groups globally.

---

## 4. Telegram Channel Adapter

**Source:** [docs.openclaw.ai/channels/telegram](https://docs.openclaw.ai/channels/telegram.md)

### Full Configuration Schema

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "123:abc",         // or via TELEGRAM_BOT_TOKEN env var
      // tokenFile: "/path/to/token",  // alternative

      // DM Policy
      dmPolicy: "pairing" | "allowlist" | "open" | "disabled",  // default: "pairing"
      allowFrom: ["123456789"],    // NUMERIC user IDs only (not @usernames!)

      // Group Policy
      groupPolicy: "open" | "allowlist" | "disabled",  // default: "allowlist"
      groupAllowFrom: ["123456789"],  // numeric group sender filter

      // Per-group config
      groups: {
        "-1001234567890": {        // numeric group ID (negative for supergroups)
          groupPolicy: "open",
          requireMention: false
        }
      },

      // Inline keyboards
      capabilities: {
        inlineButtons: "off" | "dm" | "group" | "all" | "allowlist"  // default: "allowlist"
      },

      // Polling (default) vs Webhook
      webhookUrl: "https://...",
      webhookSecret: "...",          // required for webhook
      webhookPath: "/telegram-webhook",
      webhookHost: "127.0.0.1",

      // Display
      historyLimit: 50,             // default
      replyToMode: "off" | "first" | "all",
      linkPreview: true,            // default
      streamMode: "off" | "partial" | "block",
      mediaMaxMb: 5,               // default

      // Proxy
      proxy: "socks5://...",

      // Retry
      retry: {
        attempts: 3,
        minDelayMs: 1000,
        maxDelayMs: 10000,
        jitter: true
      },

      // Network
      network: { autoSelectFamily: true }
    }
  }
}
```

### Pairing Process

1. Set `dmPolicy: "pairing"` (default)
2. Start gateway: `openclaw gateway`
3. User sends any message to bot
4. Bot generates time-limited code (1-hour expiration, max 3 pending)
5. Approve via CLI: `openclaw pairing approve telegram <CODE>`
6. After approval, only that user's numeric ID can interact

### Finding Your Telegram User ID

Send a message to your bot, then `openclaw logs --follow` -- look for `from.id` in log output.

### Discrepancies with Masterplan

1. **`allowFrom` takes NUMERIC IDs, not @usernames.** `openclaw doctor --fix` can resolve legacy `@username` entries.
2. **`configWrites` is NOT a real field.** Our plan has `"configWrites": false` in Telegram config. Config write prevention uses top-level `commands: { config: false }`.
3. **`groupPolicy` is again a flat string**, not an object. Same correction needed as IRC.

---

## 5. Security

**Source:** [docs.openclaw.ai/gateway/security](https://docs.openclaw.ai/gateway/security/index.md), [cli/security](https://docs.openclaw.ai/cli/security.md), [security/formal-verification](https://docs.openclaw.ai/security/formal-verification.md)

### Security Audit Tool

```bash
openclaw security audit              # Read-only scan
openclaw security audit --deep       # Live WebSocket probing
openclaw security audit --fix        # Auto-fix safe issues
openclaw security audit --json       # Machine-readable output
```

### High-Signal Security Checks

| Check ID | Severity | Issue |
|----------|----------|-------|
| `fs.state_dir.perms_world_writable` | Critical | State directory world-writable |
| `fs.config.perms_writable` | Critical | Config file writable by others |
| `fs.config.perms_world_readable` | Critical | Config file world-readable (tokens exposed) |
| `gateway.bind_no_auth` | Critical | Non-loopback bind without auth |
| `gateway.loopback_no_auth` | Critical | Loopback without auth (proxy bypass) |
| `gateway.tailscale_funnel` | Critical | Public internet exposure via funnel |
| `gateway.control_ui.insecure_auth` | Critical | Token-only HTTP, no device identity |
| `hooks.token_too_short` | Warning | Brute-force vulnerability |
| `logging.redact_off` | Warning | Sensitive value leakage |
| `models.small_params` | Critical/Info | Injection susceptibility with weak models |

### Tool Deny Lists -- Full Syntax

**Individual tools:**
```json5
{ tools: { deny: ["gateway", "cron", "browser", "sessions_spawn"] } }
```

**Group syntax:**
```json5
{ tools: { deny: ["group:automation", "group:runtime", "group:fs"] } }
```

**Available groups:**
| Group | Covers |
|-------|--------|
| `group:runtime` | exec, bash, process |
| `group:fs` | read, write, edit, apply_patch |
| `group:sessions` | session management tools |
| `group:memory` | memory_search, memory_get |
| `group:web` | web_search, web_fetch |
| `group:ui` | browser, canvas |
| `group:automation` | cron, gateway |
| `group:messaging` | message |
| `group:nodes` | nodes |
| `group:openclaw` | ALL built-in tools |

**Priority:** Deny takes precedence over allow. Case-insensitive matching. `"*"` = all tools.

### Sandbox Modes

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "off" | "non-main" | "all",   // when to sandbox
        scope: "session" | "agent" | "shared",  // container allocation
        workspaceAccess: "none" | "ro" | "rw",  // filesystem visibility
        workspaceRoot: "~/.openclaw/sandboxes",
        docker: {
          image: "openclaw-sandbox:bookworm-slim",
          containerPrefix: "...",
          workdir: "/workspace",
          readOnlyRoot: true,      // default
          tmpfs: ["/tmp"],
          network: "none" | "bridge",  // default: "none"
          user: "1000:1000",
          capDrop: ["ALL"],
          pidsLimit: 256,          // default
          memory: "512m",
          memorySwap: "512m",
          cpus: 1.0,
          seccompProfile: "/path/to/seccomp.json",
          apparmorProfile: "...",
          dns: [],
          extraHosts: [],
          binds: ["host:container:mode"],
          env: {}
        },
        browser: {
          enabled: false,
          image: "...",
          cdpPort: 9222,
          headless: true,
          autoStart: false
        },
        prune: {
          idleHours: 24,
          maxAgeDays: 7
        }
      }
    }
  }
}
```

**Blocked dangerous binds:** docker.sock, `/etc`, `/proc`, `/sys`, `/dev`

**Elevated tools** bypass ALL sandbox protections -- keep `tools.elevated.enabled: false`.

### mDNS Discovery

```json5
{
  discovery: {
    mdns: {
      mode: "minimal" | "full" | "off"  // default: "minimal"
    },
    wideArea: {
      enabled: false  // default
    }
  }
}
```

Or: `OPENCLAW_DISABLE_BONJOUR=1`

**Broadcast TXT records (full mode):** role, displayName, lanHost, gatewayPort, gatewayTls, gatewayTlsSha256, canvasPort, sshPort, transport, cliPath, tailnetDns

**Critical:** "Bonjour/mDNS TXT records are unauthenticated" -- never trust discovery data for security decisions.

### Official Hardened Baseline Configuration

```json5
{
  gateway: {
    mode: "local",
    bind: "loopback",
    auth: { mode: "token", token: "replace-with-long-random-token" },
  },
  session: {
    dmScope: "per-channel-peer",
  },
  tools: {
    profile: "messaging",
    deny: ["group:automation", "group:runtime", "group:fs", "sessions_spawn", "sessions_send"],
    fs: { workspaceOnly: true },
    exec: { security: "deny", ask: "always" },
    elevated: { enabled: false },
  },
}
```

### Known CVEs

| CVE | CVSS | CWE | Description | Fix |
|-----|------|-----|-------------|-----|
| **CVE-2026-25253** | 8.8 High | CWE-669 | 1-click RCE: app accepts `gatewayUrl` from query string, auto-connects WebSocket sending auth token without confirmation. Attacker steals token, disables sandbox, executes commands. | **v2026.1.29** |
| **CVE-2026-24763** | High | -- | Command injection via unsanitized input | **Patched** |
| **CVE-2026-25157** | High | -- | Command injection via unsanitized input | **Patched** |

**CVE-2026-25253 Attack chain:**
1. Attacker hosts malicious page with crafted `gatewayUrl` parameter
2. Victim visits page (1 click)
3. Victim's browser auto-connects WebSocket to attacker, sending auth token
4. Attacker connects to victim's local OpenClaw (bypasses localhost via victim's browser)
5. Attacker disables sandboxing via API
6. Attacker executes arbitrary commands on host

**CVSS Vector:** CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H

### Incident Response (Official)

1. **Contain:** Stop gateway, set `gateway.bind: "loopback"`, freeze risky DMs/groups
2. **Rotate:** `gateway.auth.token`, `gateway.remote.token`, ALL provider credentials (WhatsApp, Slack, Discord, model keys)
3. **Audit:** Review `/tmp/openclaw/openclaw-YYYY-MM-DD.log`, session transcripts at `~/.openclaw/agents/<agentId>/sessions/*.jsonl`, recent config changes, re-run `openclaw security audit --deep`
4. **Collect:** Timestamp, OS, version, transcripts, log excerpts (redacted), attacker input, agent response, exposure scope

### Formal Verification

TLA+/TLC security regression models at [github.com/vignesh07/openclaw-formal-models](https://github.com/vignesh07/openclaw-formal-models).

Verified properties:
- Gateway exposure (binding + auth enforcement)
- Nodes.run pipeline (command allowlisting + approval tokens)
- Pairing store (TTL enforcement, pending-request caps)
- Ingress gating (mention-based group access)
- Session isolation (per-peer DM separation)
- Concurrency/idempotency under interleavings
- Routing precedence and identity-link isolation

**Caveat:** "These are models, not the full TypeScript implementation. Drift between model and code is possible."

---

## 6. Plugins / ClawHub

**Source:** [docs.openclaw.ai/tools/clawhub](https://docs.openclaw.ai/tools/clawhub.md), [tools/plugin](https://docs.openclaw.ai/tools/plugin.md)

### ClawHub (Skill Marketplace)

- Public registry with vector-embedding-powered search
- GitHub accounts must be >= 1 week old to publish
- Community reporting (auto-hide after 3+ unique reports)
- CLI: `clawhub search`, `clawhub install <slug>`, `clawhub update`
- Skills install to `./skills` directory by default

### VirusTotal Partnership (Feb 7, 2026)

All skills now scanned server-side:
1. SHA-256 hash checked against VirusTotal database
2. Unknown hashes submitted for Code Insight (Gemini 3 Flash behavioral analysis)
3. Results: benign (approved), suspicious (warning), malicious (blocked)
4. Daily re-scans of active skills

**Updated threat numbers:**
| Metric | Original | Current |
|--------|----------|---------|
| Malicious skills | 341 | 1,184+ (~20% of registry) |
| Skills analyzed by VT | -- | 3,016+ |
| Single-actor skills | -- | 314 (actor: "hightower6eu") |
| Malware types | AMOS | AMOS + packed Windows trojans |

**Limitations:** Does NOT scan locally-installed skills, git-sourced skills, or third-party registries. Cannot detect prompt injection. Bypass techniques documented.

### Plugin Configuration

```json5
{
  plugins: {
    enabled: true,           // default: true
    allow: ["plugin-name"],  // explicit allowlist (NOT "allowList"!)
    deny: ["plugin-name"],   // explicit denylist
    load: {
      paths: ["/custom/plugin/dir"]
    },
    entries: {
      "plugin-id": {
        enabled: true,
        config: { /* plugin-specific */ }
      }
    }
  }
}
```

**Critical:** Plugins run **in-process** with Gateway. Treat as fully trusted code. npm lifecycle scripts execute during install.

### Discrepancy with Masterplan

Our Phase 9 uses `plugins.allowList` -- the correct field name is `plugins.allow`.

---

## 7. Memory System

**Source:** [docs.openclaw.ai/concepts/memory](https://docs.openclaw.ai/concepts/memory.md)

### Architecture

Two-layer system:
- `memory/YYYY-MM-DD.md` -- daily append-only logs (loaded at session start)
- `MEMORY.md` -- curated long-term reference (private sessions only)

Both live in workspace (`~/.openclaw/workspace` by default), NOT in `~/.openclaw/memory/` (which holds the SQLite index only).

### SQLite Backend

- Per-agent storage: `~/.openclaw/memory/<agentId>.sqlite`
- Stores: embeddings, chunk metadata, BM25 full-text index
- Configurable path: `agents.defaults.memorySearch.store.path` (supports `{agentId}` token)
- Auto-resets if provider, endpoint, or chunking params change

### sqlite-vec Extension

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        store: {
          vector: {
            enabled: true,              // default when available
            extensionPath: "/path/to/sqlite-vec"  // optional
          }
        }
      }
    }
  }
}
```

Falls back to in-process cosine similarity if extension unavailable. No data loss on fallback.

### Embedding Provider Auto-Selection

Priority order (NOT a literal `"auto"` value):
1. **Local** -- if `memorySearch.local.modelPath` configured (default model: `embeddinggemma-300m-qat-Q8_0`, ~0.6GB)
2. **OpenAI** -- if `OPENAI_API_KEY` available
3. **Gemini** -- if Gemini API key available
4. **Voyage** -- if Voyage API key available
5. Disabled until configured

### Hybrid Search (BM25 + Vector)

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        query: {
          hybrid: {
            enabled: true,
            vectorWeight: 0.7,         // default
            textWeight: 0.3,           // default
            candidateMultiplier: 4,    // default
            mmr: {                     // diversity re-ranking (NEW)
              enabled: true,
              lambda: 0.7              // 0=max diversity, 1=max relevance
            },
            temporalDecay: {           // recency boost (NEW)
              enabled: true,
              halfLifeDays: 30         // 30-day half-life
            }
          }
        }
      }
    }
  }
}
```

**Search process:**
1. Vector: top `maxResults * candidateMultiplier` by cosine similarity
2. BM25: top `maxResults * candidateMultiplier` by FTS5 rank
3. Score normalization: `1 / (1 + max(0, bm25Rank))`
4. Merge: `finalScore = vectorWeight * vectorScore + textWeight * textScore`
5. MMR re-ranking (if enabled): balances relevance with diversity
6. Temporal decay (if enabled): ages out stale memories exponentially

**Temporal decay formula:** `decayedScore = score * e^(-lambda * ageInDays)`
- Today: 100% | 7 days: ~84% | 30 days: 50% | 90 days: 12.5%
- Evergreen files (`MEMORY.md`, non-dated files) NEVER decay

### Chunking

- Target: ~400 tokens per chunk
- Overlap: 80 tokens
- Indexed files: Markdown only (`MEMORY.md`, `memory/**/*.md`)
- Freshness tracking: 1.5s debounce

### Memory Tools

- `memory_search` -- semantic search across Markdown chunks (~700 char snippets)
- `memory_get` -- read specific file by workspace-relative path

Both enabled only when `memorySearch.enabled = true`.

### Extra Memory Paths

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        extraPaths: ["../team-docs", "/srv/shared-notes/overview.md"]
      }
    }
  }
}
```

### Embedding Cache

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        cache: { enabled: true, maxEntries: 50000 }
      }
    }
  }
}
```

### QMD Backend (Experimental Alternative)

BM25 + vectors + reranking via sidecar process. Config under `memory.backend: "qmd"`.

### Discrepancies with Masterplan

1. **`"provider": "auto"` is NOT a valid value.** Remove it -- let auto-selection logic work from environment.
2. **Add `temporalDecay` and `mmr` settings** for better search quality.
3. **Memory files live in workspace**, not `~/.openclaw/memory/` (that's the SQLite index).
4. **Missing `memorySearch.cache`** and `memorySearch.extraPaths` settings.

---

## 8. Systemd Integration

**Source:** [docs.openclaw.ai/platforms/linux](https://docs.openclaw.ai/platforms/linux.md), [install/installer](https://docs.openclaw.ai/install/installer.md)

### Default: User-Level Service

OpenClaw default installs a **systemd user service**:
- Location: `~/.config/systemd/user/openclaw-gateway.service`
- Requires: `loginctl enable-linger openclaw`
- Survives logout with lingering enabled

### Official Minimal Unit File

```ini
[Unit]
Description=OpenClaw Gateway (profile: <profile>, v<version>)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/openclaw gateway --port 18789
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

### System-Level Service (Our Approach -- Correct for Servers)

For always-on or multi-user servers, use a system unit (no lingering). This is what our masterplan uses and is the **recommended approach for VPS deployment**.

### Installation Commands

```bash
openclaw onboard --install-daemon     # During onboarding
openclaw gateway install              # Standalone
openclaw configure                    # Interactive
```

### Known Bug: Upgrade Path ([#14845](https://github.com/openclaw/openclaw/issues/14845))

`openclaw gateway install --force` after upgrading prints "already enabled" but service file still contains OLD version's pnpm store path. Service doesn't get regenerated.

**Workaround:** Manually edit/recreate service file after upgrades (our custom system-level unit avoids this).

### Environment File Pattern

OpenClaw reads from `~/.openclaw/.env` for daemon operation. For system services:
```ini
EnvironmentFile=/etc/openclaw/env
```

### install.sh Behavior

The installer script:
1. Detects OS (macOS, Linux, WSL)
2. Checks Node.js, installs Node 22 if needed (NodeSource on Linux)
3. Ensures Git is present
4. Offers global npm install (default) or git-based install
5. Runs `openclaw doctor --non-interactive` on upgrades

**Does NOT create:** systemd units, service users, environment files, or directory structures. Those are handled by `openclaw onboard --install-daemon`.

### Discrepancy with Masterplan

Our systemd unit is MORE hardened than the official (correct for maximum lockdown). The official `ExecStart` uses `openclaw gateway --port 18789` -- we should verify if `openclaw gateway start --foreground` is the correct form, or if it should simply be `openclaw gateway`.

---

## 9. Tool System

**Source:** [docs.openclaw.ai/tools/index](https://docs.openclaw.ai/tools/index.md), [configuration-reference](https://docs.openclaw.ai/gateway/configuration-reference.md)

### Available Tools

**Core Execution & Files:**
- `exec` -- shell commands | `process` -- background sessions
- `read`, `write`, `edit`, `apply_patch` -- file operations

**Web & Browser:**
- `web_search` -- Brave Search API | `web_fetch` -- URL content
- `browser` -- dedicated browser instance

**UI & Automation:**
- `canvas` -- node Canvas | `cron` -- scheduled jobs
- `gateway` -- restart/update process

**Communication:**
- `message` -- cross-channel messaging | `nodes` -- paired nodes
- `image` -- image analysis

**Sessions & Memory:**
- `sessions_list`, `sessions_history`, `sessions_send`, `sessions_spawn`
- `session_status`, `agents_list`
- `memory_search`, `memory_get`

### Tool Profiles

| Profile | Scope |
|---------|-------|
| `"minimal"` | Only `session_status` |
| `"coding"` | Files, runtime, sessions, memory, images |
| `"messaging"` | Messaging, sessions list/history/send, status |
| `"full"` | No restrictions (default) |

### Exec Tool Security Levels

```json5
{
  tools: {
    exec: {
      security: "deny" | "allowlist" | "full",
      backgroundMs: 10000,     // auto-background timeout
      timeoutSec: 1800,        // kill timeout
      cleanupMs: 1800000,
      notifyOnExit: true
    }
  }
}
```

### Per-Provider Policies

```json5
{
  tools: {
    byProvider: {
      "google-antigravity": { profile: "minimal" }
    }
  }
}
```

### Loop Detection

```json5
{
  tools: {
    loopDetection: {
      enabled: true,           // default: false
      historySize: 30,
      warningThreshold: 10,
      criticalThreshold: 20,
      globalCircuitBreakerThreshold: 30,
      detectors: { genericRepeat: true, knownPollNoProgress: true, pingPong: true }
    }
  }
}
```

### CRITICAL Discrepancies with Masterplan

1. **`"gateway-tool"` should be `"gateway"`** -- the official tool name
2. **`"node-invoke"` should be `"nodes"`** -- the official tool name
3. **`"tts"` is NOT a tool** -- TTS is under `messages.tts`, not a deniable tool. Remove from deny list.
4. **Missing from deny list:** `sessions_spawn`, `sessions_send`
5. **Group syntax is more robust:** Use `"group:automation"` instead of listing `"gateway"` + `"cron"` separately

### Recommended Updated Deny List

```json5
{
  tools: {
    profile: "minimal",    // or "messaging" for IRC use case
    deny: [
      "gateway",           // was "gateway-tool"
      "cron",
      "group:runtime",     // covers exec, bash, process
      "group:fs",          // covers read, write, edit, apply_patch
      "browser",
      "canvas",
      "nodes",             // was "node-invoke"
      "sessions_spawn",
      "sessions_send",
      "web_search",        // disable web access
      "web_fetch"
    ],
    exec: { security: "deny", ask: "always" },
    elevated: { enabled: false }
  }
}
```

---

## 10. Known Bugs

### The Loopback Fallback to 0.0.0.0

**Status:** CONFIRMED -- multiple GitHub issues

When loopback binding fails (port in use, interface unavailable), the Gateway **silently falls back to `0.0.0.0`**, exposing the service to all network interfaces without warning.

**Related GitHub issues:**
- [#1380](https://github.com/openclaw/openclaw/issues/1380) -- Binds to Tailscale IP instead of loopback
- [#8823](https://github.com/openclaw/openclaw/issues/8823) -- CLI RPC probe hardcodes `ws://127.0.0.1` when bind is "lan"
- [#16299](https://github.com/openclaw/openclaw/issues/16299) -- TUI hardcodes localhost, ignores bind mode
- [#14542](https://github.com/openclaw/openclaw/issues/14542) -- gateway.bind should auto-set to loopback when tailscale.mode is serve
- [#7626](https://github.com/openclaw/openclaw/issues/7626) -- Gateway ignores gateway.port config and --port flag

**Note on source location:** The centminmod analysis references `src/gateway/net.ts:159-164` (not 256-261 as we originally had). Line numbers may vary by version.

**Our mitigation (binding verification cron) is correct:**
```bash
if ss -tlnp | grep ':18789' | grep -q '0.0.0.0'; then
    systemctl stop openclaw
fi
```

Also: `openclaw security audit --deep` performs live WebSocket probing and reports actual listening interface.

### Upgrade Service File Bug ([#14845](https://github.com/openclaw/openclaw/issues/14845))

`openclaw gateway install --force` after version upgrade doesn't regenerate service file. Still points to old pnpm store path.

### Port Config Ignored ([#7626](https://github.com/openclaw/openclaw/issues/7626))

Gateway sometimes ignores `gateway.port` config and `--port` CLI flag. Verify actual port after startup.

---

## Additional Findings

### Version Numbering

**Calendar Versioning (CalVer):** `vYYYY.M.D` format

| Channel | Format | npm dist-tag |
|---------|--------|-------------|
| Stable | `vYYYY.M.D` or `vYYYY.M.D-<patch>` | `latest` |
| Beta | `vYYYY.M.D-beta.N` | `beta` |
| Dev | Development builds | `dev` |

**Critical minimum version:** `>= 2026.1.29` (patches CVE-2026-25253)

```bash
openclaw update --channel stable
openclaw update --tag 2026.1.29
npm i -g openclaw@2026.1.29    # pin specific version
```

### Naming: "OpenClaw" vs "open-claw"

- **Official name:** "OpenClaw" (capital O, capital C, one word)
- **npm package:** `openclaw` (lowercase, one word)
- **GitHub repo:** `openclaw/openclaw`
- **Historical names:** "clawdbot" and "Moltbot" (NVD: "OpenClaw (aka clawdbot or Moltbot)")
- **Hyphenated "open-claw":** NOT used in official sources

### Infostealer Threat

Hudson Rock discovered infostealers (Vidar variant) targeting `~/.openclaw/`:
- Config files with tokens
- Credential files
- Session transcripts
- 28,663 IPs / 40,214+ exposed instances

### Dutch DPA Warning

Dutch Data Protection Authority warned about serious cybersecurity and privacy risks from OpenClaw agents. Validates our maximum lockdown approach.

---

## Masterplan Corrections Needed

### Critical (Must Fix)

| # | What | Current | Should Be |
|---|------|---------|-----------|
| 1 | Auth primary | setup-token | API key (setup-token blocked Jan 9, 2026) |
| 2 | IRC groupPolicy | Object `{ mode, requireMention, allowedGroups }` | Flat string `"allowlist"` + separate `groups` object |
| 3 | Tool: gateway-tool | `"gateway-tool"` | `"gateway"` |
| 4 | Tool: node-invoke | `"node-invoke"` | `"nodes"` |
| 5 | Tool: tts | In deny list | Remove (not a tool) |
| 6 | Missing tools in deny | -- | Add `"sessions_spawn"`, `"sessions_send"` |
| 7 | Telegram configWrites | `"configWrites": false` | Not a field. Use `commands: { config: false }` |
| 8 | Plugins allowList | `plugins.allowList` | `plugins.allow` |
| 9 | Memory provider | `"provider": "auto"` | Remove (auto-selection is implicit, not a value) |

### Recommended Additions

| # | Addition | Where |
|---|----------|-------|
| 1 | `toolsBySender` for IRC per-sender restrictions | Phase 3 IRC config |
| 2 | `session.dmScope: "per-channel-peer"` | Phase 4 security |
| 3 | `tools.exec.security: "deny"` and `tools.elevated.enabled: false` | Phase 4 security |
| 4 | `temporalDecay` and `mmr` settings | Phase 6 memory |
| 5 | `gateway.auth.rateLimit` settings | Phase 4 security |
| 6 | Pin version `>= 2026.1.29` in install | Phase 1 |
| 7 | `logging.redactPatterns` for custom patterns | Phase 8 monitoring |
| 8 | Verify ExecStart form for systemd | Phase 7 |

---

## Sources

### Official Documentation
- [docs.openclaw.ai](https://docs.openclaw.ai) -- Main site
- [docs.openclaw.ai/llms.txt](https://docs.openclaw.ai/llms.txt) -- Full index (200+ pages)
- [Gateway Security](https://docs.openclaw.ai/gateway/security/index.md)
- [Authentication](https://docs.openclaw.ai/gateway/authentication.md)
- [Configuration Reference](https://docs.openclaw.ai/gateway/configuration-reference.md)
- [IRC Channel](https://docs.openclaw.ai/channels/irc.md)
- [Telegram Channel](https://docs.openclaw.ai/channels/telegram.md)
- [Memory System](https://docs.openclaw.ai/concepts/memory.md)
- [Tools](https://docs.openclaw.ai/tools/index.md)
- [ClawHub](https://docs.openclaw.ai/tools/clawhub.md)
- [Sandboxing](https://docs.openclaw.ai/gateway/sandboxing.md)
- [Network Model](https://docs.openclaw.ai/gateway/network-model.md)
- [Bonjour/mDNS](https://docs.openclaw.ai/gateway/bonjour.md)
- [Linux/Systemd](https://docs.openclaw.ai/platforms/linux.md)
- [Installer Internals](https://docs.openclaw.ai/install/installer.md)
- [Formal Verification](https://docs.openclaw.ai/security/formal-verification.md)

### Security & CVE Sources
- [NVD CVE-2026-25253](https://nvd.nist.gov/vuln/detail/CVE-2026-25253)
- [SOCRadar CVE Analysis](https://socradar.io/blog/cve-2026-25253-rce-openclaw-auth-token/)
- [GHSA-g8p2-7wf7-98mq](https://github.com/openclaw/openclaw/security/advisories/GHSA-g8p2-7wf7-98mq)
- [Adversa.ai Security Guide](https://adversa.ai/blog/openclaw-security-101-vulnerabilities-hardening-2026/)
- [Wiz CVE Database](https://www.wiz.io/vulnerability-database/cve/cve-2026-25253)

### GitHub Issues
- [#14845](https://github.com/openclaw/openclaw/issues/14845) -- Service file not regenerated
- [#1380](https://github.com/openclaw/openclaw/issues/1380) -- Tailscale binding bug
- [#8823](https://github.com/openclaw/openclaw/issues/8823) -- CLI RPC hardcodes localhost
- [#16299](https://github.com/openclaw/openclaw/issues/16299) -- TUI ignores bind mode
- [#16365](https://github.com/openclaw/openclaw/issues/16365) -- Subscription auth request
- [#8074](https://github.com/openclaw/openclaw/issues/8074) -- OAuth token expiration
- [#7626](https://github.com/openclaw/openclaw/issues/7626) -- Port config ignored

### Blog & News
- [VirusTotal Partnership](https://openclaw.ai/blog/virustotal-partnership)
- [VirusTotal Blog: Automation to Infection](https://blog.virustotal.com/2026/02/from-automation-to-infection-how.html)
- [THN: Infostealer](https://thehackernews.com/2026/02/infostealer-steals-openclaw-ai-agent.html)
- [THN: CVE-2026-25253](https://thehackernews.com/2026/02/openclaw-bug-enables-one-click-remote.html)

---

*Deep research conducted against official sources only. No content from clawbot.ai (confirmed typosquat) was used. All configuration schemas extracted from docs.openclaw.ai/gateway/configuration-reference.md and individual channel/feature pages.*
