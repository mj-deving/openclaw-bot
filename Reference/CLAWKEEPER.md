# ClawKeeper Reference

> Authoritative reference for ClawKeeper adoption and integration.
> For the Defense Shield system (our enforcement layer), see [DEFENSE-SYSTEM.md](DEFENSE-SYSTEM.md).

## What It Is

ClawKeeper is an open-source security framework for OpenClaw agents, described as "the Norton for OpenClaw." It provides config auditing, behavioral monitoring, drift detection, and skill supply chain scanning. Built by [@xunyoyo](https://github.com/xunyoyo/ClawKeeper), it operates as an OpenClaw plugin that hooks into the gateway lifecycle.

**Version:** 0.1.0
**License:** MIT
**Repository:** github.com/xunyoyo/ClawKeeper

## Why We Adopted It

Our 6-layer Defense Shield handles active enforcement: blocking injections, redacting secrets, guarding tool calls. But it does not audit configuration, monitor behavioral drift, or scan skills for supply chain risks. ClawKeeper fills those complementary gaps:

| Gap | How ClawKeeper Fills It |
|-----|------------------------|
| Config auditing | 9+ security domains, scores 0-100, actionable findings |
| Behavioral drift | Watches `openclaw.json` and `AGENTS.md` for unexpected changes |
| Skill scanning | Static analysis of skill code for dangerous patterns |
| Runtime constitution | Injects behavioral rules into AGENTS.md |
| Event logging | JSONL logs of all hooks: tool calls, messages, LLM I/O |

Together, Defense Shield + ClawKeeper provide observe-then-enforce defense-in-depth.

## Architecture: Three Pillars

ClawKeeper has three deployment modes. We use the Plugin pillar only.

### 1. Plugin (what we use)

An OpenClaw extension that registers hooks and CLI commands. Loads from `~/.openclaw/extensions/clawkeeper/`. Provides:

- 5 event hooks (logging all message, tool, and LLM activity)
- CLI commands for audit, harden, monitor, scan
- Gateway startup audit (runs automatically on boot)
- Drift monitoring (optional, watches config files)

### 2. Bundled Skill (not deployed)

A workspace skill that gives the bot itself security awareness. Requires `child_process` for installation, which we patched out. The skill's behavioral rules are available via `openclaw clawkeeper harden` which injects them into AGENTS.md.

### 3. Standalone Watcher (not deployed)

A separate process that watches OpenClaw's state directory for changes. Not needed when the plugin handles drift monitoring.

## Installation

### How It Was Installed

1. Cloned from GitHub to `/tmp/ClawKeeper/` on VPS
2. Patched `src/plugin/cli.js` line 249-263: replaced `runBundledScript()` which uses `child_process.spawn()` with a no-op warning (OpenClaw plugin sandbox blocks `child_process`)
3. Copied `clawkeeper-plugin/` to `~/.openclaw/extensions/clawkeeper/`
4. Enabled via `openclaw plugins enable clawkeeper`
5. Gateway restart to activate

### The child_process Patch

ClawKeeper's `installBundledSkill()` function uses a dynamic `import('node:child_process')` to spawn bash scripts for skill installation. OpenClaw's plugin sandbox blocks this import. The patch replaces the function body with a `console.warn()` explaining the limitation.

**Patched function:**
```javascript
async function runBundledScript(scriptName) {
  // PATCHED: child_process blocked by OpenClaw plugin sandbox.
  console.warn(`[Clawkeeper] runBundledScript(${scriptName}) skipped`);
}
```

This means the bundled skill cannot auto-install. The plugin itself works fine -- only the `install` and `harden` CLI commands that spawn shell scripts are affected.

## Commands Reference

All commands run via `openclaw clawkeeper <command>`.

| Command | Purpose | Example |
|---------|---------|---------|
| `audit` | Run security audit, print score and findings | `openclaw clawkeeper audit` |
| `audit --json` | Machine-readable JSON output | `openclaw clawkeeper audit --json` |
| `audit --deep` | Deep scan with network probing and IOC checks | `openclaw clawkeeper audit --deep` |
| `harden` | Auto-fix findings that support it | `openclaw clawkeeper harden` |
| `status` | Show plugin state and configuration | `openclaw clawkeeper status` |
| `logs` | View security event logs | `openclaw clawkeeper logs` |
| `logs --scan` | Scan logs for security anomalies | `openclaw clawkeeper logs --scan` |
| `scan-skill <path>` | Static analysis of a skill directory | `openclaw clawkeeper scan-skill ./my-skill` |
| `rollback` | Revert last harden action | `openclaw clawkeeper rollback` |
| `install` | Install bundled skill (blocked by patch) | N/A |

## Security Audit Domains

The audit checks 9+ security domains with findings scored by severity.

| Domain | ID Prefix | What It Checks |
|--------|-----------|----------------|
| Network | `network.*`, `SC-GW-*` | Gateway binding, TLS, port exposure |
| Identity | `identity.*` | Auth tokens, operator boundaries |
| Execution | `execution.*`, `SC-EXEC-*` | Sandbox mode, filesystem boundaries |
| Behavior | `behavior.*` | Runtime constitution in AGENTS.md |
| Credentials | `SC-CRED-*` | Plaintext API keys in state directory |
| Cost | `SC-COST-*` | Spending limits, API quotas, log volume |
| Access Control | `SC-AC-*` | Rate limiting, message flood protection |
| Control Tokens | `SC-CTRL-*` | Custom vs default control tokens |
| Cross-Layer | `SC-CROSS-*` | Compound attack surface across MAESTRO layers |

### Scoring

- Base score: 100
- CRITICAL finding: -20 points
- HIGH finding: -10 points
- MEDIUM finding: -5 points
- LOW finding: -2 points
- INFO finding: 0 points (informational only)

### Our Baseline Score: 29/100

Many of ClawKeeper's findings flag config patterns we handle differently:
- **Gateway binding:** We use `"loopback"` string, ClawKeeper expects `"127.0.0.1"` literal
- **Spending limits:** We enforce via Defense Shield L5 governor (systemd env vars), not `openclaw.json`
- **Sandbox mode:** We use `exec.security: "full"` instead of `sandbox.mode`
- **Plaintext API keys:** Found in third-party `node_modules/` README files, not actual credentials
- **TLS:** Not needed -- gateway is loopback-only, never internet-exposed

The score reflects ClawKeeper's generic expectations vs our hardened-but-differently-configured deployment.

## Core Security Rules

ClawKeeper ships 8 behavioral rules (the "runtime constitution") that can be injected into AGENTS.md. These 10 high-severity pattern categories are detected by the security scanner:

| Category | What It Detects |
|----------|----------------|
| Prompt injection | "Ignore previous instructions" and 40+ variants (EN + CN) |
| Role override | "You are now an evil AI" and mode switching |
| System markers | `[SYSTEM]`, `<<SYS>>`, template tags |
| Credential patterns | API keys, tokens, secrets in content |
| Dangerous commands | `rm -rf`, `chmod 777`, `curl \| bash` |
| Exfiltration | Data sent to external URLs, webhook sites |
| Privilege escalation | `sudo`, setuid, capability manipulation |
| Social engineering | Authority claims, urgency pressure |
| Obfuscation | Base64, hex, ROT13 encoded payloads |
| Control flow | Instruction injection, new-rule insertion |

## Configuration

Plugin config in `openclaw.json` under the `plugins.clawkeeper` key:

```json
{
  "plugins": {
    "clawkeeper": {
      "autoHarden": false,
      "strictMode": false,
      "driftMonitor": false
    }
  }
}
```

| Setting | Default | Purpose |
|---------|---------|---------|
| `autoHarden` | `false` | Run safe hardening on gateway startup |
| `strictMode` | `false` | Treat missing controls as CRITICAL instead of HIGH |
| `driftMonitor` | `false` | Watch config/AGENTS files for boundary drift |

## Event Logging

ClawKeeper logs all 5 hook events to JSONL files at `~/.openclaw/workspace/log/YYYY-MM-DD.jsonl`:

- `before_tool_call` — tool name, params, agent/session context
- `message_received` — from, content (first 1000 chars), channel
- `message_sending` — to, content (first 1000 chars), channel
- `llm_input` — provider, model, prompt (first 2000 chars), system prompt, history count
- `llm_output` — provider, model, assistant texts, token usage

These logs complement Defense Shield's violation-focused logging with comprehensive activity tracking.

## Relationship to Defense Shield

| Aspect | Defense Shield | ClawKeeper |
|--------|---------------|------------|
| **Role** | Active enforcement | Passive observation + audit |
| **Blocks attacks** | Yes (hooks modify/cancel messages, block tools) | No (logs and reports only) |
| **Redacts secrets** | Yes (pre-delivery via message_sending hook) | No (detects but does not modify) |
| **Config auditing** | No | Yes (9 domains, scored findings) |
| **Drift detection** | No | Yes (watches config/AGENTS changes) |
| **Skill scanning** | No | Yes (static analysis for dangerous patterns) |
| **Event logging** | Violation-focused (only logs when something triggers) | Comprehensive (logs all activity) |
| **Hook count** | 5 hooks (all active enforcement) | 5 hooks (all passive logging) |
| **Cost tracking** | L5 governor (enforces limits) | Audit finding (reports missing limits) |
| **Architecture** | Library code compiled into plugin | Standalone JS plugin with CLI |

**Together:** ClawKeeper observes everything and audits configuration. Defense Shield enforces security policy in real-time. ClawKeeper catches what Defense Shield cannot see (config drift, skill supply chain). Defense Shield blocks what ClawKeeper cannot stop (live injection attempts, secret leaks).

## Known Limitations

1. **child_process patch** — The `install` and `harden` CLI commands that spawn shell scripts are non-functional. Bundled skill must be deployed manually.

2. **No real-time blocking** — ClawKeeper is observational only. It logs tool calls and messages but cannot block them. Active enforcement is Defense Shield's job.

3. **Generic audit baselines** — ClawKeeper's audit expects vanilla OpenClaw config patterns. Our hardened deployment uses different mechanisms (systemd env vars, exec.security, loopback binding string), causing expected false findings.

4. **Beijing timezone in logs** — The interceptor uses UTC+8 for log timestamps regardless of server timezone. Our VPS runs UTC+2. Log timestamps will be 6 hours ahead.

5. **No dedup with Defense Shield** — Both plugins register hooks on the same events. ClawKeeper logs first, Defense Shield enforces. No conflict, but messages are processed by both.

## Operational Commands

```bash
# Run security audit
ssh vps 'export PATH="$HOME/.npm-global/bin:$PATH" && openclaw clawkeeper audit'

# Run audit with JSON output
ssh vps 'export PATH="$HOME/.npm-global/bin:$PATH" && openclaw clawkeeper audit --json'

# View today's event logs
ssh vps 'cat ~/.openclaw/workspace/log/$(date -u +%Y-%m-%d).jsonl | python3 -m json.tool'

# Scan logs for security anomalies
ssh vps 'export PATH="$HOME/.npm-global/bin:$PATH" && openclaw clawkeeper logs --scan'

# Check plugin status
ssh vps 'export PATH="$HOME/.npm-global/bin:$PATH" && openclaw plugins list | grep -A3 clawkeeper'

# Scan a skill before installation
ssh vps 'export PATH="$HOME/.npm-global/bin:$PATH" && openclaw clawkeeper scan-skill /path/to/skill'
```

## File Inventory

| File | Purpose |
|------|---------|
| `~/.openclaw/extensions/clawkeeper/` | Plugin installation directory |
| `~/.openclaw/extensions/clawkeeper/src/index.js` | Plugin entry point |
| `~/.openclaw/extensions/clawkeeper/src/plugin/sdk.js` | Hook registration and lifecycle |
| `~/.openclaw/extensions/clawkeeper/src/plugin/cli.js` | CLI command registration (patched) |
| `~/.openclaw/extensions/clawkeeper/src/core/audit-engine.js` | Security audit engine |
| `~/.openclaw/extensions/clawkeeper/src/core/controls.js` | 5 built-in security controls |
| `~/.openclaw/extensions/clawkeeper/src/core/security-rules.js` | Injection pattern library |
| `~/.openclaw/extensions/clawkeeper/src/core/interceptor.js` | Event logging hooks |
| `~/.openclaw/extensions/clawkeeper/src/core/drift-monitor.js` | Config/AGENTS drift watcher |
| `~/.openclaw/extensions/clawkeeper/src/core/skill-scanner.js` | Skill static analysis |
| `~/.openclaw/extensions/clawkeeper/openclaw.plugin.json` | Plugin manifest |
| `~/.openclaw/workspace/log/*.jsonl` | Daily event logs |
| `Reference/CLAWKEEPER.md` | This file (authoritative reference) |
