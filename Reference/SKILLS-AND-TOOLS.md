# Skills, Tools & Agent Capabilities for OpenClaw

Best practices for managing skills, expanding agent capabilities, vetting third-party code, and maintaining a security-first posture. Research synthesized from OpenClaw docs, security advisories, and community analysis.

---

## The Big Picture: Three Extension Mechanisms

OpenClaw agents gain capabilities through three distinct mechanisms. Understanding what each IS prevents dangerous confusion between them.

| Mechanism | What It Is | Runs As | Security Model | Available Now |
|-----------|-----------|---------|----------------|---------------|
| **Native tools** | Built-in functions (exec, read, write, etc.) | In-process | Governed by tool policy (profile + allow/deny) | Yes |
| **Skills** | SKILL.md instruction files teaching tool usage | In-process (guides existing tools) | Same as native — they USE native tools | Yes |
| **MCP servers** | External processes exposing tool schemas via Model Context Protocol | Separate child process | Full process permissions, less controlled | PR #21530 pending |

**The critical distinction:** Tools *execute*, skills *educate*. A skill cannot do anything the agent's tools can't already do — it just teaches the agent HOW to use tools for a specific purpose. This means a malicious skill can't bypass your tool deny list, but it CAN trick the agent into misusing tools it already has.

---

## 1. Skill Anatomy

### SKILL.md File Structure

Every skill is a markdown file with YAML frontmatter. Minimum:

```yaml
---
name: my-skill
description: What this skill does
---

# My Skill

Instructions for the agent...
```

**Required fields:**
- `name` — skill identifier (lowercase, hyphens, under 64 chars)
- `description` — human-readable purpose

**Optional frontmatter:**
- `homepage` — URL displayed in macOS Skills UI
- `user-invocable` — `true|false` (default: true); exposes as slash command
- `disable-model-invocation` — `true|false` (default: false); excludes from model prompt
- `command-dispatch` — set to `tool` for direct tool dispatch (bypasses model reasoning)
- `command-tool` — tool name when using command-dispatch
- `metadata` — single-line JSON for gating and configuration (see below)

### Gating via metadata.openclaw

Skills are filtered at load time. The `metadata` field controls eligibility:

```json
{
  "openclaw": {
    "always": false,
    "emoji": "🔍",
    "os": ["linux"],
    "requires": {
      "bins": ["gh"],
      "anyBins": [],
      "env": ["GITHUB_TOKEN"],
      "config": ["browser.enabled"]
    },
    "primaryEnv": "GITHUB_TOKEN",
    "install": [
      { "id": "apt-gh", "kind": "node", "bins": ["gh"], "label": "Install GitHub CLI" }
    ]
  }
}
```

| Field | What It Does |
|-------|-------------|
| `always: true` | Skip all gates — always load |
| `os` | Platform filter (darwin, linux, win32) |
| `requires.bins` | ALL listed binaries must exist on PATH |
| `requires.anyBins` | At least ONE must exist on PATH |
| `requires.env` | Environment variables must exist or be in config |
| `requires.config` | openclaw.json paths that must be truthy |
| `primaryEnv` | Links to `skills.entries.<name>.apiKey` convenience field |

**No metadata = always eligible** (unless disabled in config or blocked by `skills.allowBundled`).

### Skill Precedence (Three-Tier Hierarchy)

Skills load from three locations, highest precedence first:

1. **Workspace skills** — `<workspace>/skills/` (per-agent, highest priority)
2. **Managed skills** — `~/.openclaw/skills/` (shared across agents)
3. **Bundled skills** — shipped with the npm package (lowest priority)

Name conflicts resolve by tier: workspace overrides managed, managed overrides bundled.

Extra directories: `skills.load.extraDirs` adds lowest-precedence scan paths.

### Token Impact

Skills are injected as compact XML into the system prompt:

- **Base overhead** (when any skills exist): ~195 characters
- **Per skill**: ~97 characters + XML-escaped field lengths
- **Rough estimate**: ~24 tokens per skill (OpenAI-style tokenizer)

**Denied tools exclude their skills from injection** — so your deny list saves tokens on every LLM call.

---

## 2. Custom Skill Creation

### When to Build a Custom Skill

Build when:
- A workflow involves domain-specific tools not in bundled skills
- You need structured guidance beyond what TOOLS.md provides
- You want the agent to follow a specific multi-step procedure

Don't build when:
- Bundled skills already cover the need
- The exec tool + a CLI binary handles it (just document in TOOLS.md)
- A simple workspace file instruction suffices

### Creating a Skill Manually

```bash
# 1. Create the skill directory
mkdir -p ~/.openclaw/skills/my-skill/

# 2. Create SKILL.md
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

## Edge Cases
What to do when things go wrong.
EOF

# 3. Verify it loaded (no restart needed — skills are detected dynamically)
openclaw skills list | grep my-skill
```

### Using the skill-creator Bundled Skill

The `skill-creator` skill guides the agent through a six-step workflow:

1. Understanding the use case with concrete examples
2. Planning reusable resources (scripts, references, assets)
3. Initializing the skill structure
4. Editing skill content
5. Packaging the skill
6. Iterating based on usage

Invoke it by asking the bot: "Create a skill for [purpose]"

### Advanced Skill Structure

Beyond the basic SKILL.md, skills can include:

```
my-skill/
├── SKILL.md              # Required — agent instructions
├── scripts/              # Optional — executable code for deterministic tasks
│   └── process.py
├── references/           # Optional — on-demand context loaded into agent
│   └── schema.md
└── assets/               # Optional — templates, boilerplate
    └── template.json
```

- **scripts/** — code the agent can execute via the exec tool
- **references/** — documentation the agent reads when needed (not injected every message)
- **assets/** — templates and boilerplate for generating output

### Skill Configuration in openclaw.json

```json5
{
  "skills": {
    "entries": {
      "my-skill": {
        "enabled": true,
        "apiKey": "KEY_HERE",
        "env": { "MY_API_KEY": "KEY_HERE" },
        "config": { "endpoint": "https://api.example.com" }
      }
    },
    "load": {
      "watch": true,
      "watchDebounceMs": 250,
      "extraDirs": ["/path/to/shared/skills"]
    },
    "install": {
      "nodeManager": "npm",
      "preferBrew": false
    }
  }
}
```

**Environment injection is scoped:** `env` values are injected per agent run, not into the global shell. Restored after run ends. Docker-sandboxed processes don't inherit these — configure via `agents.defaults.sandbox.docker.env` instead.

---

## 3. Tool Profiles and Permission Model

### Four Predefined Profiles

| Profile | What It Includes | Use Case |
|---------|-----------------|----------|
| `full` | All tools, no restrictions | Personal bot with max capability |
| `coding` | Filesystem, runtime, sessions, memory | Developer-focused agent |
| `messaging` | Messaging channels, session management | Chat-only agent |
| `minimal` | `session_status` only | Ultra-locked-down |

### The Permission Pipeline

Four layers applied in sequence — **each can only restrict, never expand**:

```
Layer 1: Tool Profile (base allowlist)
    ↓
Layer 2: Provider-specific profiles (tools.byProvider)
    ↓
Layer 3: Global + per-agent allow/deny lists
    ↓
Layer 4: Sandbox-specific policies
```

**Rule #1: Deny always wins.** At every layer, deny overrides allow.

**Rule #2: Non-empty allow creates implicit deny.** If you specify `allow: ["read", "exec"]`, everything else is implicitly denied.

**Rule #3: Per-agent overrides can only further restrict** — not expand beyond global settings.

### Tool Groups (Bulk Deny/Allow)

| Group | Contains |
|-------|----------|
| `group:runtime` | exec, process |
| `group:fs` | read, write, edit, apply_patch |
| `group:sessions` | Session management tools |
| `group:memory` | memory_search, memory_get |
| `group:web` | web_search, web_fetch |
| `group:ui` | browser, canvas |
| `group:automation` | cron, gateway |
| `group:messaging` | Message tools per channel |
| `group:nodes` | Node operations |
| `group:openclaw` | All built-ins (excludes provider plugins) |

### How Skills Interact with Tool Permissions

**Skills cannot escalate permissions.** A skill is a teaching document — it guides the agent to use tools that are already available. If a tool is denied, the skill cannot make it usable. The skill's instructions simply won't work, and the agent will report the tool is unavailable.

**Skills DO inherit the agent's full tool access.** If exec is allowed and a skill teaches the agent to run `curl` to an external endpoint, the agent will do it. The defense is the tool policy, not the skill.

---

## 4. Supply Chain Risk Model

### The Threat Landscape

**ClawHavoc campaign (Feb 2026):** The most significant supply chain attack on the OpenClaw ecosystem.

- **Scale:** Initially 341 malicious skills identified (12% of registry). Updated scans found 800+ malicious packages (~20% of 10,700+ skills). One actor (hightower6eu) uploaded 314 alone.
- **Attack vector:** Malicious SKILL.md files masquerading as cryptocurrency tools, YouTube utilities, and Google Workspace integrations. The "Prerequisites" section used ClickFix social engineering — convincing users to run attacker-supplied shell commands.
- **Payload:** Atomic macOS Stealer (AMOS), a $500-1K/month malware-as-a-service tool. Harvested browser credentials, keychain passwords, cryptocurrency wallets (60+ types), SSH keys, and API keys. Windows variant: VMProtect-packed infostealers with keylogger and RAT capabilities.
- **Delivery:** macOS used base64-encoded shell commands from glot.io. Windows used password-protected ZIP archives from GitHub to bypass antivirus.
- **Persistence:** Memory poisoning — modifying SOUL.md and MEMORY.md files for delayed-execution attacks that survive reboots and session restarts.

**Snyk ToxicSkills study:** Analyzed 3,984 skills. Found 36.82% contained security flaws; 1,467 showed critical issues.

### Attack Vectors

| Vector | How It Works | Detectability |
|--------|-------------|---------------|
| **Adversarial SKILL.md prompts** | Instructions that trick the agent into running malicious commands | Hard — requires semantic analysis, not binary scanning |
| **npm lifecycle scripts** | `preinstall`/`postinstall` hooks execute during `clawhub install` | Medium — inspect package.json before install |
| **Dependency confusion** | Skill requires a binary that resolves to an attacker-controlled package | Medium — verify package sources manually |
| **Typosquatting** | Skills with names similar to popular ones | Easy — check exact name and author |
| **Data exfiltration via curl** | Skill teaches agent to send data to external endpoints | Hard — looks like normal tool usage |
| **Memory poisoning** | Modifying persistent files (SOUL.md, MEMORY.md) for delayed compromise | Very hard — changes persist across sessions |

### Known CVEs

| CVE | CVSS | What | Fixed In |
|-----|------|------|----------|
| CVE-2026-25253 | 8.8 | Cross-site WebSocket hijacking → RCE via Control UI | v2026.1.29 |
| CVE-2026-25157 | — | OS command injection via SSH handler | v2026.1.29 |
| CVE-2026-25475 | 6.5 | Local file inclusion via MEDIA: path extraction | v2026.1.29 |
| GHSA-mc68-q9jw-2h3v | — | Docker command injection via PATH manipulation | v2026.1.29 |
| GHSA-g55j-c2v4-pjcg | — | Unauthenticated local RCE via WebSocket config.apply | v2026.1.29 |

**All patched in v2026.1.29+.** Ensure your installation is current.

### Registry Moderation (Current State)

ClawHub's current defenses are minimal:
- GitHub account age minimum: one week
- Post-upload VirusTotal scanning (catches binary malware)
- **Cannot detect:** adversarial prompts in SKILL.md, social engineering instructions, data exfiltration patterns, or dependency-based attacks

---

## 5. Security Audit Methodology

### Vetting Checklist (Enhanced)

Before installing ANY community skill, complete this checklist:

**Author verification:**
- [ ] Author has 1K+ downloads across their skills
- [ ] Author is a known community member (GitHub profile, forum activity)
- [ ] Author account is older than 30 days
- [ ] Cross-reference author name — check for typosquatting of known contributors

**Code review:**
- [ ] Read the entire SKILL.md — check for suspicious "prerequisites" or "setup" instructions
- [ ] Search for `curl`, `wget`, `fetch()`, `exec()`, `eval()` — any calls to external hosts
- [ ] Check for base64-encoded content (common obfuscation technique)
- [ ] Search for references to `~/.openclaw/`, `SOUL.md`, `MEMORY.md` — memory poisoning vectors
- [ ] Inspect any scripts/ directory for shell commands, network calls, or file writes
- [ ] Check package.json for lifecycle scripts (`preinstall`, `postinstall`, `prepare`)
- [ ] Verify no symlinks in the skill package (rejected by design, but check manually)

**Dependency audit:**
- [ ] If the skill requires CLI binaries, verify they come from official sources
- [ ] Check npm package names for typosquatting (e.g., `@steipete/summarize` vs `@steipet/summarize`)
- [ ] Pin exact versions after install (`clawhub install skill@1.2.3`)
- [ ] No VirusTotal flags on any dependency

**Post-install verification:**
- [ ] Run `openclaw security audit --deep` after installation
- [ ] Monitor `openclaw skills list` — verify only expected skills are loaded
- [ ] Check for unexpected files in `~/.openclaw/skills/` and workspace directories
- [ ] Monitor outbound network connections during first use

### SecureClaw (Community Security Tool)

A dual-component security system for OpenClaw:
- **55 audit checks** evaluating installation security
- **15 behavioral rules** influencing agent behavior during prompt, tool, and output interactions
- **9 scripts + 4 JSON pattern databases** for detection logic
- Optimized to ~1,150 tokens to minimize context window impact
- Maps to all 10 OWASP Agentic Security Initiative (ASI) top threats
- Maps to MITRE ATLAS agentic AI attack techniques

### Monitoring After Installation

**Watch for these signals:**
- Unexpected outbound network connections (especially to paste services like glot.io)
- Changes to SOUL.md or MEMORY.md not initiated by you
- New cron jobs created without your knowledge (`openclaw cron list`)
- Agent behavior changes (new patterns, unexpected tool usage)
- Increased token consumption (could indicate prompt injection expanding context)

---

## 6. MCP Server Integration (Future)

### Current Status

Native MCP support is **not yet in OpenClaw mainline**. Community PR #21530 is open and under review (Feb 2026). The `mcpServers` config key is currently ignored with a log message.

### Proposed Configuration

```json
{
  "agents": {
    "list": [
      {
        "id": "main",
        "mcp": {
          "servers": [
            { "name": "filesystem", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/openclaw"] },
            { "name": "github", "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": { "GITHUB_TOKEN": "..." } }
          ]
        }
      }
    ]
  }
}
```

### How MCP Will Differ from Skills

| Aspect | Skills | MCP Servers |
|--------|--------|-------------|
| Execution model | In-process (guides existing tools) | Separate child process |
| Trust requirement | Trust the instructions | Trust the executable code |
| Sandboxing | None (but limited to available tools) | None by default (separate process, same user) |
| Tool schemas | None (natural language) | Formal JSON schemas exposed via tools/list |
| Token cost | ~24 tokens per skill | Additional tool schemas per server |
| Network access | Via agent's exec tool (controlled) | Direct from server process (less controlled) |

### Security Implications of MCP

When MCP lands, treat each server as untrusted code:
- MCP servers run as child processes under the same OS user
- They inherit the spawning user's filesystem and network permissions
- Environment variables configured in `mcp.servers[].env` are visible to the server
- No built-in mechanism to deny specific tools from an MCP server while allowing others
- **Audit each MCP server package before deploying** — same rigor as npm dependencies

---

## 7. Agent Capability Expansion Patterns

### Decision Framework

```
Need new capability?
  │
  ├── Is it a CLI tool? → Install binary + document in TOOLS.md
  │
  ├── Does it need multi-step guidance? → Create a skill (SKILL.md)
  │
  ├── Does it need formal tool schemas? → Wait for MCP
  │
  ├── Does it need process isolation? → MCP server (when available)
  │
  └── Does it need per-agent scoping? → Agent tool overrides
```

### Expanding via Exec + TOOLS.md (Simplest Path)

The exec tool makes every installed CLI binary available to the agent. Install the binary, guide usage in TOOLS.md:

```bash
# Install capabilities
sudo apt install gh jq
npm install -g @steipete/summarize clawhub

# Guide in workspace TOOLS.md
cat >> ~/.openclaw/workspace/TOOLS.md << 'EOF'

## Available CLI Tools
- `gh` — GitHub CLI for issues, PRs, code review (auth via `gh auth login`)
- `jq` — JSON processing and filtering
- `summarize` — Summarize URLs, PDFs, YouTube videos
EOF
```

### Expanding via Custom Skills (Structured Guidance)

For capabilities that need multi-step instructions, create a workspace skill:

```bash
mkdir -p ~/.openclaw/workspace/skills/deploy-check/
# Create SKILL.md with deployment verification workflow
```

### Expanding via Agent Configuration (Per-Agent Capabilities)

Different agents can have different tool profiles:

```json5
{
  "agents": {
    "list": [
      {
        "id": "main",
        "tools": { "profile": "full", "deny": ["gateway", "nodes"] }
      },
      {
        "id": "cron",
        "model": "anthropic/claude-haiku-3-5",
        "tools": { "profile": "coding", "deny": ["gateway", "browser"] }
      }
    ]
  }
}
```

### Subagent Configuration

Background workers spawned by the main agent have their own tool restrictions:

```json5
{
  "agents": {
    "defaults": {
      "subagents": {
        "model": "anthropic/claude-haiku-3-5",
        "maxConcurrent": 1,
        "maxSpawnDepth": 1,
        "maxChildrenPerAgent": 5,
        "archiveAfterMinutes": 60
      }
    }
  },
  "tools": {
    "subagents": {
      "tools": {
        "deny": ["sessions_list", "sessions_history", "sessions_send", "sessions_spawn"]
      }
    }
  }
}
```

---

## Priority Recommendations

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 1 | Stay bundled-only — zero community skill installs | 0 min | Eliminates entire supply chain attack surface |
| 2 | Ensure OpenClaw v2026.1.29+ (all critical CVEs patched) | 5 min | Closes WebSocket RCE, command injection, file inclusion |
| 3 | Create custom workspace skills for recurring workflows | 30 min | Structured agent guidance without third-party risk |
| 4 | Audit TOOLS.md — document installed CLI tools for agent | 15 min | Better tool usage without skill overhead |
| 5 | Consider per-agent tool restrictions for cron | 10 min | Reduce blast radius of autonomous sessions |
| 6 | Run `openclaw security audit --deep` periodically | 5 min | Catch configuration drift |
| 7 | Monitor for MCP PR #21530 landing | Ongoing | New extension path when available |
| 8 | Evaluate SecureClaw for automated security auditing | 30 min | 55 checks + behavioral rules |

---

## Sources

- [OpenClaw Docs: Skills](https://docs.openclaw.ai/tools/skills)
- [OpenClaw Docs: Skills Config](https://docs.openclaw.ai/tools/skills-config)
- [OpenClaw Docs: Tools](https://docs.openclaw.ai/tools)
- [OpenClaw Docs: Tool Policy](https://docs.openclaw.ai/gateway/sandbox-vs-tool-policy-vs-elevated)
- [OpenClaw Docs: Multi-Agent](https://docs.openclaw.ai/concepts/multi-agent)
- [OpenClaw Docs: Sub-Agents](https://docs.openclaw.ai/tools/subagents)
- [OpenClaw Docs: Configuration Reference](https://docs.openclaw.ai/gateway/configuration-reference)
- [GitHub Issue #4834: Native MCP Support](https://github.com/openclaw/openclaw/issues/4834)
- [GitHub PR #21530: MCP Client Support](https://github.com/openclaw/openclaw/pull/21530)
- [GitHub Issue #13248: MCP Status](https://github.com/openclaw/openclaw/issues/13248)
- [eSecurity Planet: Malicious Skills in ClawHub](https://www.esecurityplanet.com/threats/hundreds-of-malicious-skills-found-in-openclaws-clawhub/)
- [Conscia: OpenClaw Security Crisis](https://conscia.com/blog/the-openclaw-security-crisis/)
- [Aryaka: ClawHavoc Supply Chain Attack](https://www.aryaka.com/blog/securing-openclaw-agents-clawhavoc-supply-chain-attack-ai-secure-protection/)
- [HelpNet Security: SecureClaw](https://www.helpnetsecurity.com/2026/02/18/secureclaw-open-source-security-plugin-skill-openclaw/)
- [Barrack.ai: OpenClaw Security Vulnerabilities](https://blog.barrack.ai/openclaw-security-vulnerabilities-2026/)
