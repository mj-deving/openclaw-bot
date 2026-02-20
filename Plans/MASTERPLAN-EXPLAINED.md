# Masterplan Explained -- The Reasoning Behind Every Decision

**Companion document to:** `MASTERPLAN.md`
**Purpose:** Explain the *why* behind every step, not just the *what*

---

## How This Plan Was Built

Three parallel research agents analyzed the entire OpenClaw ecosystem:

1. **Repo extraction agent** -- Cloned `centminmod/explain-openclaw`, read all 199 markdown files (5.6MB). This is a third-party documentation project by George Liu (centminmod) that synthesizes analyses from 5 different AI models (Opus 4.5, GPT-5.2, GLM 4.7, Gemini 3.0 Pro, Kimi K2.5). It contains deployment runbooks, security audits, threat models, and architecture deep-dives.

2. **Web research agent** -- Searched GitHub, Wikipedia, blog posts (Simon Willison, Moncef Abboud, Pragmatic Engineer), security coverage (The Register, Hacker News, Cisco, Kaspersky, Sophos, Adversa AI), and the official docs at docs.openclaw.ai.

3. **Local project analysis agent** -- Inventoried the `openclaw-bot` repo structure and existing deployment configuration.

The plan is the synthesis of all three. Every decision traces back to specific evidence. The plan evolved through 13 phases of iterative deployment, each building on the last. Here's what drove each decision.

---

## Why VPS Over Other Deployment Options

OpenClaw documents 4 deployment scenarios. Here's why VPS won:

### Mac Mini (rejected)
The Mac mini deployment is designed for Apple Silicon users who want maximum privacy and local-first operation. It uses launchd instead of systemd. If you're on Linux and need always-on availability, a Mac mini would require buying hardware and being tied to a physical location. The docs explicitly call this "privacy-first" -- but it trades away availability.

### Cloudflare Moltworker (rejected)
The Moltworker runs inside Cloudflare's Sandbox SDK on their edge network. Sounds appealing (serverless, no server management) but the security docs flagged two critical problems:
- **No egress filtering** -- the sandbox can make arbitrary outbound HTTP requests. If the AI gets prompt-injected, there's no network-level containment.
- **R2 single point of failure** -- all persistent state lives in Cloudflare R2. If R2 has an outage or you lose access, everything is gone.
- **Cost**: Minimum $5/month for Workers paid plan, plus R2 storage, plus AI Gateway costs, plus Anthropic API. More moving parts than a VPS.

The explain-openclaw repo rates Moltworker as "proof-of-concept" grade. Not production.

### Docker Model Runner (rejected for primary, possible addon later)
This lets you run local AI models (Qwen, GLM, etc.) via Docker Desktop for zero API cost. Rejected because:
- If you already have an Anthropic subscription -- no need to avoid API costs
- Local models (7B-13B params) are measurably worse than Claude Sonnet for complex reasoning
- Requires GPU hardware (Apple Silicon, NVIDIA, or AMD). Most VPS providers don't offer GPUs at reasonable prices
- The docs themselves say: "For production workloads requiring highest-quality responses, cloud providers still have an edge"

### VPS (chosen)
- Always-on -- the bot stays connected to Telegram 24/7 without relying on your local machine
- systemd provides auto-restart, log management, security sandboxing out of the box
- The explain-openclaw repo has a complete "Isolated VPS" runbook with DigitalOcean 1-Click as the reference deployment. This is their most thoroughly documented path.
- SSH tunnel access means you can manage it from anywhere

---

## Why Anthropic (Claude) Over Other Providers

OpenClaw supports 20+ AI providers. Here's why Anthropic is the right choice:

### What was considered
- **OpenRouter**: Gateway to 200+ models with smart routing. `openrouter/auto` picks the best model per query. Cost-optimized with inverse-square pricing. Sounds great -- but it's an intermediary. Your data passes through OpenRouter's servers AND the downstream provider's servers. Two trust boundaries instead of one.
- **OpenAI GPT-5**: Full support in OpenClaw. Comparable quality to Claude. But if you already have an Anthropic subscription, there's no cost advantage.
- **Local models via Ollama**: Zero cost, full privacy. But quality is significantly lower than Claude Sonnet, and most VPS providers lack GPUs.
- **z.ai/Grok, Gemini, Moonshot, Kimi, MiniMax**: All supported but less documented, less tested with OpenClaw's tool-use pipeline.

### Why Anthropic won
1. **Max subscription support** -- OpenClaw supports Anthropic directly via the `setup-token` method. No separate API account, no additional cost, no billing surprises. The `claude setup-token` command generates an OAuth credential that bridges a Max subscription to OpenClaw's Anthropic provider.
2. **Primary recommended provider** -- OpenClaw's onboarding wizard puts Anthropic first. The most-tested code path.
3. **Best security audit performance** -- In the explain-openclaw repo's 5-model comparison, Claude Opus had the "most rigorous security verification with code citations." The model that powers the bot should be the one that handles sensitive contexts best.
4. **Single trust boundary** -- Data goes to Anthropic and nowhere else. With OpenRouter, it goes to OpenRouter then to a downstream provider.

### Why setup-token over API key

The `setup-token` method was chosen because:
1. **Zero additional cost** -- A Max subscription already covers usage. A separate API key would mean paying twice (subscription + per-token API charges).
2. **Officially supported** -- OpenClaw documents setup-token auth at `docs.openclaw.ai/gateway/authentication` as a first-class method alongside API keys.
3. **OAuth-based refresh** -- The credential auto-refreshes. API keys are static and need manual rotation.
4. **Fallback is simple** -- If setup-token proves unreliable (some users report 401 errors), switching to an API key is a single env var change. No architecture impact.

The caveat: Anthropic recommends API keys for "production or multi-user workloads." For a personal Telegram bot with a single operator, setup-token is the right fit.

### The prompt caching tradeoff

**Setup-token auth does not support prompt caching.** This was verified through research and testing. OpenClaw auto-applies `cacheRetention` only for API key auth. With setup-token, the full system prompt is re-sent to Anthropic on every single message -- no caching, no reuse.

Why this matters:
- The bot's bootstrap injection (system prompt + workspace files) is roughly 3,750 tokens
- Every message incurs the full input cost of that prompt, even for short follow-ups
- Prompt caching would reduce repeated input costs by up to 90%

Why this is a problem:
- Claude Max IS metered -- tokens count against a 5x Pro rolling usage cap (5-hour windows, weekly limits)
- Setup-token auth means metered usage WITHOUT prompt caching -- the worst of both worlds
- Every message burns ~3,750 tokens of system prompt at full input cost, with zero reuse
- Switching to API key auth unlocks prompt caching (90% savings on repeated input), which more than justifies the per-token cost
- The switch is a single config change: create an API key at console.anthropic.com, update the auth method in `openclaw.json`, enable `cacheRetention: "long"`

### Why Sonnet as the default model

- **Sonnet is the sweet spot** -- response latency matters for chat. Opus is smarter but slower. Haiku is faster but less capable. Sonnet handles Q&A, code, and general assistance well.
- **Token economics** -- on a subscription, Sonnet responses are predictable. With Opus, each response uses roughly 3x more compute for marginal quality improvement in typical conversations.
- **Upgrade path is trivial** -- changing to Opus for complex tasks is a single command. No architecture changes needed.
- **Model tiering** -- the bot can use different models for different workloads. Haiku for cost-sensitive automated tasks (cron), Sonnet for general conversation, Opus on-demand for complex reasoning.

---

## Why Telegram as Primary Channel

OpenClaw supports multiple channels (Telegram, WhatsApp, IRC, Discord, Slack, etc.). Telegram was chosen as the sole channel for several reasons:

### Why Telegram won
1. **Rich interaction** -- Telegram supports markdown formatting, inline code, media attachments, and long messages. The bot's responses render beautifully without any adaptation.
2. **Mobile and desktop** -- accessible from phone, tablet, and desktop apps. The bot is always reachable.
3. **Bot API maturity** -- Telegram's Bot API is well-documented, stable, and free. No approval process, no rate limit surprises for personal bots.
4. **Private by default** -- Telegram DMs are between you and the bot. No public channel where others can see responses or attempt prompt injection.
5. **No inbound ports** -- the bot polls Telegram's servers via HTTPS. No firewall changes needed. The VPS makes outbound connections only.

### Why `dmPolicy: "pairing"` for access control

OpenClaw supports three DM policies:
- `open` -- anyone can DM the bot. Terrible for security.
- `allowlist` -- specific user IDs can DM. Requires knowing Telegram user IDs upfront.
- `pairing` -- first person to DM becomes the paired user. Cryptographically tied to their Telegram account.

Pairing is the recommended approach because:
1. It's a one-time setup (DM the bot once, confirm the pairing code)
2. After pairing, the bot ignores all other DMs -- zero attack surface from random users
3. You don't need to look up your Telegram user ID manually
4. The pairing is stored server-side, survives restarts

### Why the bot token is in the env file

The Telegram Bot API token (`123456:ABC-DEF...`) is effectively a full-access credential. Anyone with this token can:
- Read all messages sent to the bot
- Send messages as the bot
- See the paired user's Telegram ID

It gets the same treatment as other secrets: stored in `/etc/openclaw/env` (root-owned, 0600), referenced via `TELEGRAM_BOT_TOKEN` env var, never written to `openclaw.json`.

---

## Why This Security Posture

> *As capable as possible, while as secure as necessary.*

This is the guiding philosophy. Security exists to protect capability, not to prevent it. Every restriction must justify itself: "Does removing this capability make the bot meaningfully safer, or just less useful?"

### The threat landscape (Feb 2026)

The threats are real and well-documented:

**28,000+ exposed OpenClaw instances** -- SecurityScorecard's STRIKE team scanned the internet and found tens of thousands of OpenClaw gateways directly reachable. These are full AI agents with shell access, file I/O, and API keys. Many had auth disabled by default.

**Malicious ClawHub skills** -- The "ClawHavoc" campaign discovered in Feb 2026 found hundreds of malicious skills in the ClawHub registry. Some bundled the AMOS macOS infostealer. Others used prompt injection to exfiltrate data. VirusTotal scanning catches binary malware but not adversarial prompts in SKILL.md files.

**Real CVEs with high severity:**
- CVE-2026-25253 (CVSS 8.8): Control UI automatically trusts `gatewayURL` query param, establishes WebSocket with stored auth token without origin verification. One-click total gateway compromise.
- CVE-2026-24763, CVE-2026-25157: Command injection vulnerabilities.

**Hudson Rock infostealer** -- First confirmed case of Vidar malware specifically targeting `~/.openclaw/` config files. Credentials stored as plaintext in that directory are the prize.

**The "lethal trifecta"** (Cisco's framing): OpenClaw agents have (1) privileged access to sensitive data, (2) ability to communicate externally, and (3) ability to access untrusted content. This combination means any prompt injection can potentially trigger data exfiltration.

### How the posture balances capability and security

The bot runs with `tools.profile: "full"` -- nearly everything is enabled. Then specific, high-risk tools are denied with clear justification:

**Loopback binding** (`gateway.bind: "loopback"`)
- **Threat**: The gateway's default can silently fall back to 0.0.0.0 if loopback binding fails (found in source code analysis by the explain-openclaw repo). Your gateway could become internet-facing without warning.
- **Mitigation**: Loopback binding + a verification cron that checks every 5 minutes (Phase 8).

**`gateway` tool denied**
- **Threat**: The gateway tool has zero-gating on `config.apply` and `config.patch` operations. The AI agent can reconfigure itself -- change its model, disable security settings, add channels -- without any permission check.
- **Evidence**: Found in the explain-openclaw security analysis. This is the most dangerous tool in the toolset.
- **Impact**: A prompt injection could instruct the bot to weaken its own security config.

**`nodes`, `sessions_spawn`, `sessions_send` denied**
- **Threat**: These enable multi-device orchestration and cross-session communication. For a single-bot deployment, they add attack surface with zero benefit.

**Shell execution enabled** (`exec.security: "full"`, `ask: "off"`)
- **Why enabled**: A capable bot needs to run commands -- checking weather, running calculations, interacting with the filesystem. Denying exec would cripple the bot's utility.
- **Why "full" security**: OpenClaw's "full" exec security applies sandboxing and restrictions to shell commands. The bot can execute, but within boundaries.
- **Risk acceptance**: With Telegram pairing, only the owner can trigger commands. The attack surface is limited to the owner's own messages and anything the bot might encounter in its tools.

**mDNS disabled** (`discovery.mdns.mode: "off"`)
- **Threat**: OpenClaw broadcasts its presence via mDNS by default. On a VPS with shared networking, this announces "I am an OpenClaw instance" to neighboring VMs.

**Config writes disabled** (`commands.config: false`)
- **Threat**: Without this, chat-based config changes could modify security settings.
- **Reasoning**: Configuration should only happen via SSH. Never from chat.

**Log redaction** (`logging.redactSensitive: "tools"`)
- **Threat**: Tool I/O can contain API keys, passwords, or sensitive data. If logs are compromised, this data leaks.
- **Reasoning**: Defense in depth.

### Why not maximum lockdown?

The original plan used `tools.profile: "minimal"` with a heavy deny list. This was changed because:
1. **A bot that can't do things isn't useful.** Minimal profile disabled shell execution, file operations, and most tools. The bot could only chat.
2. **The real threats are self-modification, not capability.** The `gateway` tool (self-reconfiguration) is dangerous. The `exec` tool (running commands) is the whole point.
3. **Pairing eliminates most prompt injection vectors.** With only the owner able to message the bot, the attack surface is dramatically smaller than a public multi-user channel.

---

## Why a Dedicated `openclaw` User

### The principle: least privilege
Running OpenClaw as root means any vulnerability gives the attacker root. Running as your admin user means any compromise gives access to your SSH keys, other projects, and admin sudo.

A dedicated user with:
- No password (locked: `passwd -l`)
- No sudo access
- Restricted home directory (0700)
- systemd sandbox (`ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=true`)

...means even if OpenClaw is fully compromised, the attacker can only access `~/.openclaw/` and `~/workspace/`. They can't escalate, can't read other users' files, can't modify system binaries.

### Why lock the password
The `openclaw` user should only be accessible via `sudo -u openclaw -i` from your admin account. No direct SSH login. This eliminates password brute-force as an attack vector.

---

## Why Secrets in systemd `EnvironmentFile` Instead of `openclaw.json`

Three storage options were considered:

1. **In `openclaw.json`** -- Plaintext. Protected by file permissions (0600). But any process running as the `openclaw` user can read it. If the AI agent has file read access, it could potentially read its own config and leak keys in a chat response.

2. **In the systemd unit file** -- Better than JSON, but `systemctl show openclaw` can leak environment variables to anyone who can query systemd.

3. **In `/etc/openclaw/env`** (chosen) -- Owned by `root:openclaw`, mode 0600. The systemd service reads it at startup via `EnvironmentFile=`. The running process has the variables in memory, but:
   - The file is not readable by the `openclaw` user (owned by root)
   - The AI agent's file read tools can't access `/etc/openclaw/env` (outside its sandbox)
   - `systemctl show` with `--property=Environment` shows the variables, but only to users with systemd access (not the bot)

This is defense in depth. Secrets exist in process memory (unavoidable), but they're not in any file the AI agent can read.

**Note on setup-token auth:** With setup-token, the Anthropic API credential is managed by OpenClaw's credential store (`~/.openclaw/credentials/`). The env file still holds the Telegram bot token. The same security principles apply to all credentials.

---

## Why systemd Security Directives

The systemd unit file includes security hardening directives. Here's what each one does and why:

| Directive | What it does | Why |
|-----------|-------------|-----|
| `NoNewPrivileges=true` | Process can't gain new privileges (no setuid, no capability escalation) | Prevents privilege escalation even if attacker finds an exploit |
| `ProtectSystem=strict` | Entire filesystem is read-only except explicitly listed paths | Prevents writing to system directories even if process is compromised |
| `ProtectHome=read-only` | All home directories are read-only | Prevents modifying other users' files |
| `ReadWritePaths=...` | Only `~/.openclaw` and `~/workspace` are writable | Minimum necessary write access |
| `PrivateTmp=true` | Process gets its own /tmp | Prevents cross-process tmp attacks |
| `ProtectKernelTunables=true` | Can't modify /proc/sys | Prevents kernel parameter manipulation |
| `ProtectKernelModules=true` | Can't load kernel modules | Prevents rootkit installation |
| `ProtectControlGroups=true` | Can't modify cgroups | Prevents resource limit evasion |
| `RestrictNamespaces=true` | Can't create new namespaces | Prevents container escape techniques |
| `RestrictRealtime=true` | Can't use realtime scheduling | Prevents CPU monopolization |
| `MemoryDenyWriteExecute=true` | Can't create writable+executable memory | Prevents most shellcode injection |

Each directive eliminates a class of attacks. Combined, they create a sandbox that's more restrictive than running in Docker (Docker doesn't set most of these by default).

---

## Why the Binding Verification Cron

This exists because of a specific bug in the OpenClaw source code:

When the gateway tries to bind to loopback (127.0.0.1) and fails (e.g., another process on that port, transient error), it can silently fall back to binding on `0.0.0.0` (all interfaces). No warning. No error log. Your gateway is suddenly internet-facing. This behavior was identified in the explain-openclaw repo's source code analysis of the gateway networking module.

The verification script runs every 5 minutes, checks if the gateway is bound to `0.0.0.0` on the gateway port, and kills it if so. This is a compensating control for a known source code bug.

If OpenClaw fixes this upstream, the cron becomes a no-op (never triggers). No harm in keeping it.

---

## Why We're Not Using Tailscale

Tailscale is documented in OpenClaw as an alternative to SSH tunnels for remote access. It's a good product. Here's why the plan doesn't use it:

1. **Additional trust boundary** -- Tailscale routes traffic through their coordination server. For management access to your gateway, you're adding a dependency on Tailscale's infrastructure and security.

2. **Additional software to maintain** -- One more package to update, one more service to monitor, one more config to secure.

3. **SSH tunnel does the same thing** -- `ssh -L 18789:127.0.0.1:18789` gives you the exact same result (local port forwarded to remote loopback) without any additional software.

4. **Principle of minimum viable infrastructure** -- Every component you add is a component that can break or be compromised. SSH is already installed and required for server management. Tailscale adds zero capability you don't already have.

If you later want Tailscale for convenience (e.g., accessing from a phone where SSH tunneling is awkward), it's a `gateway.tailscale.mode: "serve"` config change. The plan doesn't preclude it.

---

## Why Node.js 22.x, Not Bun

The explain-openclaw documentation explicitly notes:

> "Alternative: Bun runtime (has known bugs per docs)"

OpenClaw's primary runtime is Node.js. Their install script installs Node. Their documentation references Node. Their systemd examples use Node. Bun is listed as an alternative with caveats.

For a production bot that needs to be reliable 24/7, the documented primary runtime (Node.js 22.12.0+) is the safer choice. Bun can be used for development tooling in the repo, but the OpenClaw process itself should run on Node.

---

## Why Phase Order Matters

The phases are ordered to minimize risk at each step:

**Phase 0 before Phase 1**: Harden the OS BEFORE installing OpenClaw. If you install first, there's a window where OpenClaw is running on an unhardened system.

**Phase 2 before Phase 3**: Configure the AI provider BEFORE connecting to Telegram. Otherwise the bot receives messages but can't respond (no AI backend).

**Phase 3 before Phase 4**: Set up Telegram first, verify it works, THEN harden. If something breaks, you know it's the hardening that broke it, not the initial setup. Debugging is easier before lockdown.

**Phase 4 before Phase 7**: Harden BEFORE creating the systemd service. The service codifies the running state. If you harden after creating the service, you have to update the service config too.

**Phase 7 before Phase 8**: Create the service before monitoring. Monitoring checks if the service is healthy -- it needs to exist first.

**Phase 9 (skills) after launch**: Skills are a dependency layer. Adding them before the bot is stable means debugging two things at once (is the bug in the skill or the base install?). Ship the base, verify it works, then add skills.

**Phase 10 (cron) after skills**: Autonomous engagement uses the bot's full capability set. Skills and memory should be working before you let the bot post on its own.

**Phase 11 (pipeline) after cron**: The pipeline enables remote orchestration. The bot should already be autonomous and capable before adding external command input.

**Phase 12 (cost monitoring) last**: You need the bot running all its workloads (conversations, cron, pipeline) before you can meaningfully measure and baseline costs.

---

## Why Bundled Skills Only

OpenClaw v2026.2.17 ships 50 bundled skills as SKILL.md files inside the npm package. These activate automatically when their required CLI binary is installed on the system -- no `clawhub install` needed.

### Why bundled over ClawHub community skills

1. **Zero supply chain risk from the registry.** Bundled skills ship with OpenClaw itself. They're reviewed by the core team and included in the release. No third-party uploads, no malicious injections, no ClawHavoc-style attacks.

2. **No runtime dependency on ClawHub.** The registry could go down, get compromised, or change its API. Bundled skills work offline with no external calls.

3. **Skills are just documentation.** A SKILL.md file is a markdown prompt -- it tells the AI how to use a CLI tool. There's no executable code. The security boundary is the CLI tool itself, which you install and control.

4. **Incremental activation.** Each skill activates when its CLI dependency is installed. You add capabilities one at a time, verify each works, and can remove by uninstalling the CLI. Clean rollback.

### The ClawHub ecosystem reality

The ClawHub registry has thousands of skills, but the quality and security picture is mixed:
- The "ClawHavoc" campaign found hundreds of malicious uploads
- VirusTotal scanning catches binary malware but not adversarial prompts
- New skills are uploaded faster than moderators can vet them
- Skills run in-process with the gateway -- a malicious skill has full access to process memory and API keys

Bundled skills bypass this entire attack surface. The tradeoff is a smaller selection (50 vs thousands), but those 50 cover the most common use cases: GitHub, summarization, web search, weather, health checks, and more.

### The expansion path

If a bundled skill doesn't cover a needed capability:
1. Check if the existing skills + model reasoning can approximate it
2. If not, evaluate the specific ClawHub skill: read its SKILL.md source, check the author, review download counts
3. Install in a test environment first, audit behavior
4. If clean, add to production with version pinning

---

## Why a File-Based Pipeline

The pipeline enables asynchronous communication between a local assistant and the VPS-hosted bot. Three directories at `~/.openclaw/pipeline/` -- inbox (messages to the bot), outbox (messages from the bot), ack (processed messages) -- with SSH as the transport.

### What was considered

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **File-based via SSH** | Simple, auditable, no new infrastructure, no new auth | Not real-time (~minutes) | **Chosen** |
| **GitHub repo files** | Versioned, inspectable via web UI | Requires git on VPS, commit per message, overkill | Rejected |
| **GitHub Issues** | Structured, threaded | Too public unless repo is private, clunky for rapid exchange | Rejected |
| **Direct API relay** | Real-time | Requires custom server, opens network attack surface | Rejected |

### Why file-based won

1. **SSH is already there.** The VPS is managed via SSH. No new authentication, no new ports, no new software.
2. **JSON files are inspectable.** Each message is a timestamped JSON file. You can `ls`, `cat`, or `jq` the inbox at any time to see what's pending.
3. **No new attack surface.** No additional service listening on a port. No API to exploit. Just files on disk.
4. **Archival built in.** Processed messages move to `ack/`. Nothing is deleted. Full audit trail.
5. **Bot-side integration is simple.** A cron job checks the inbox periodically. The bot reads, processes, and moves the file. No long-polling, no WebSocket, no event bus.

### Why not real-time?

The pipeline handles tasks like "check this URL," "run a security scan," or "summarize this document." None of these are time-critical. The bottleneck is human attention, not message latency. If something truly urgent arises, you message the bot directly on Telegram.

---

## Why Autonomous Engagement via Cron

Phase 10 uses OpenClaw's built-in cron system (not system crontab) to give the bot autonomous voice. The bot generates original content on a schedule -- using its personality, memory, and tools -- without waiting for a human message.

Why this matters:
- **Persistent presence.** A bot that only responds when spoken to feels passive. Scheduled posts make it feel alive.
- **Built-in, not bolted on.** The cron system runs inside the gateway process. No external scheduler, no extra process to manage.
- **Per-job model overrides.** Cron jobs can use cheaper models (Haiku) for routine posts, saving costs while keeping Sonnet/Opus for interactive conversation.
- **Isolated sessions.** Each cron run starts with a clean context. No risk of cron posts leaking information from private conversations.
- **Security note:** The `cron` tool is NOT denied in this configuration. The bot can manage its own scheduled tasks. This is a deliberate capability tradeoff -- the owner controls cron via CLI, and the bot's Telegram pairing limits who can influence it.

---

## Why Cost Monitoring

Even on a subscription, understanding token flow prevents surprises and informs optimization decisions.

Why dedicated monitoring matters:
- **Subscription metering is real.** Claude Max uses 5-hour rolling windows and weekly caps on token usage. Monitoring actual consumption tells you how close you are to rate limits and whether your bot's workload fits within the allowance.
- **Cron costs add up silently.** Five autonomous posts per day, each with system prompt + memory retrieval + generation, compound over a month.
- **Bootstrap injection cost.** The system prompt (~3,750 tokens) is re-sent on every message because setup-token auth doesn't support prompt caching. This is invisible without monitoring.
- **Optimization requires baselines.** You can't reduce costs without first measuring them. ClawMetry or built-in commands (`/usage`, `/status`) establish what "normal" looks like.

---

## Why We Track CVEs in the Plan

Three CVEs are listed not because they're currently exploitable (they're patched) but because:

1. **Version pinning** -- Knowing CVE-2026-25253 was patched in v2026.1.29 tells you the minimum version to install. If your VPS has an older version cached or you accidentally install an old release, you know to check.

2. **Attack pattern awareness** -- CVE-2026-25253 (Control UI trusts `gatewayURL` query param) reveals that the WebSocket auth model is fragile. Even though it's patched, the class of vulnerability (trusting client-supplied URLs) might recur. Knowing the pattern helps you evaluate future updates.

3. **Audit baseline** -- When you run `openclaw security audit --deep`, you should know what it's checking for. The CVE list gives you context for the audit output.

---

## Why the Repo Structure Separates Config from Code

The `openclaw-bot` repo contains configs, scripts, and docs -- NOT the OpenClaw source code. This is intentional:

- **OpenClaw is installed via npm** -- it's a published package. You don't fork it. You configure it.
- **Config is your code** -- `openclaw.json`, the systemd unit file, the system prompt, the monitoring scripts -- these are what differentiate your bot from any other OpenClaw instance.
- **Secrets never go in the repo** -- `.env.example` shows the shape of secrets without containing them. The `.gitignore` already blocks `.env` files.
- **The repo is your deployment artifact** -- SSH to VPS, git pull, copy configs, restart service. Repeatable, auditable, rollbackable.

---

## What We're Still Evaluating

Transparency about uncertainty:

1. **API key auth migration timing** -- Claude Max IS metered (5-hour rolling windows, weekly caps). Setup-token without prompt caching wastes tokens on every message. Switching to API key auth with prompt caching is the clear optimization path -- the only question is when to do it.

2. **`tools.deny` completeness** -- The deny list blocks known-dangerous tools (gateway, nodes, sessions), but OpenClaw has 50+ tools. New ones may be added in updates. The `profile: "full"` setting is the baseline; the deny list is the targeted restriction. New tool additions in OpenClaw updates should be reviewed.

3. **Setup-token OAuth reliability** -- Some users report 401 errors with setup-token auth. The OAuth token refresh mechanism may fail due to network issues, password changes, or revoked access. `openclaw doctor --fix` is the recovery path, with API key as the fallback.

4. **Haiku quality for autonomous posts** -- Cron jobs use Haiku to save costs. Whether Haiku produces posts that meet quality standards over time requires ongoing monitoring. If quality degrades, reverting to Sonnet is a single cron edit.

5. **Long-term maintenance** -- OpenClaw is transitioning to a foundation model. How this affects release cadence, security patches, and backward compatibility is unknown. The plan is designed to be resilient to upstream changes (version pinning, minimal external dependencies, bundled-only skills).

---

*Every decision in the masterplan has a reason. If you disagree with any reasoning, the plan can be adjusted. The goal is to understand what you're deploying and why, not to follow steps blindly.*
