# ClawHub Skills Analysis & Gregor Agent Architecture

**Date:** 2026-02-19
**Author:** Isidore (for Marius Jonathan Jauernik)
**Purpose:** Map ClawHub ecosystem, assess security, design Gregor as secure multipurpose agent with Isidore communication pipeline

---

## 1. ClawHub Skill Catalog — Full Category Taxonomy

**Registry stats (Feb 19, 2026 — LIVE DATA via browser + CLI):** 8,630 non-suspicious skills | Post-ClawHavoc cleanup removed suspicious entries but registry has since grown massively

### 11 Official Categories

| # | Category | Skill Count | % of Registry | Relevance to Gregor |
|---|----------|------------|---------------|---------------------|
| 1 | **AI/ML** | 1,588 | 48.3% | HIGH — self-improvement, model selection, prompt optimization |
| 2 | **Utility** | 1,520 | 46.3% | HIGH — general-purpose tools, CLI helpers |
| 3 | **Development** | 976 | 29.7% | HIGH — coding agents, GitHub, git workflows |
| 4 | **Productivity** | 822 | 25.0% | MEDIUM — summarization, task management |
| 5 | **Web** | 637 | 19.4% | LOW — browser denied in Gregor's config |
| 6 | **Science** | 598 | 18.2% | LOW — niche research |
| 7 | **Media** | 365 | 11.1% | LOW — video/image generation, limited on headless VPS |
| 8 | **Social** | 364 | 11.1% | MEDIUM — Telegram, communication protocols |
| 9 | **Finance** | 311 | 9.5% | LOW — crypto/stock, not Gregor's purpose |
| 10 | **Location** | 153 | 4.7% | LOW — weather, maps |
| 11 | **Business** | 151 | 4.6% | LOW — marketing, sales |

**Note:** Percentages overlap because skills can span multiple categories.

### Sub-Category Breakdown (from awesome-openclaw-skills)

| Sub-Category | Count | Notable Skills |
|---|---|---|
| Coding Agents & IDEs | 133 | coding-agent (steipete), claude-optimised, debug-pro |
| Git & GitHub | 66 | git-essentials, pr-reviewer, conventional-commits |
| Browser & Automation | 139 | browse, sandbox automation |
| Search & Research | 253 | exa-web-search-free, deepwiki |
| Communication | 132 | WhatsApp (Wacli), email integrations |
| CLI Utilities | 129 | shell automation, terminal optimization |
| Agent-to-Agent Protocols | 18 | moltbook, agentchat |
| Security & Passwords | 64 | password management, security scanning |
| Notes & PKM | 100 | logseq, obsidian |
| Smart Home & IoT | 56 | Sonos, camera control |

---

## 2. Popular Skills Analysis — Top Downloaded

### Top Skills by Downloads (LIVE from clawhub.ai/skills — Feb 19, 2026)

| Rank | Skill | Downloads | Stars | Author | What It Does | Gregor? |
|---|---|---|---|---|---|---|
| 1 | **Gog** | 28.1k | 170 | @steipete | Google Workspace CLI (Gmail, Calendar, Drive, Contacts, Sheets, Docs) | MAYBE |
| 2 | **Tavily Web Search** | 22.7k | 65 | @arun-8687 | AI-optimized web search via Tavily API | MAYBE |
| 3 | **Wacli** | 22.1k | 53 | @steipete | WhatsApp messaging via CLI | NO (IRC/Telegram focus) |
| 4 | **Summarize** | 21.5k | 76 | @steipete | Summarize URLs/files (web, PDFs, images, audio, YouTube) | **YES** |
| 5 | **Github** | 20.7k | 59 | @steipete | GitHub CLI (`gh`) integration for issues, PRs, CI runs | **YES** |
| 6 | **Sonoscli** | 18.2k | 10 | @steipete | Sonos speaker control | NO (VPS) |
| 7 | **Nano Pdf** | 10.9k | 21 | @steipete | Edit PDFs via natural language | MAYBE |
| 8 | **Obsidian** | 10.5k | 33 | @steipete | Obsidian vault management via obsidian-cli | NO (VPS) |
| 9 | **Free Ride** | 9.9k | 38 | @Shaivpidadi | Free OpenRouter AI models for OpenClaw | NO (security) |
| 10 | **OpenAI Whisper** | 9.4k | 37 | @steipete | Local speech-to-text (no API key) | NO (VPS audio) |
| 11 | **Mcporter** | 9.4k | 24 | @steipete | **Official** — MCP server management CLI | MAYBE |
| 12 | **Humanizer** | 9.4k | 69 | @biostartechnology | Remove AI-writing patterns from text | NO |
| 13 | **Brave Search** | 8.8k | 28 | @steipete | Web search via Brave Search API (no browser) | MAYBE |
| 14 | **YouTube** | 8.4k | 23 | @byungkyu | YouTube Data API integration | NO |

**Key observation:** steipete dominates the top 15. He authored **9 of the top 14** most-downloaded skills. His skills are essentially the platform's "standard library."

### Highlighted Skills (Curated on ClawHub Homepage)

| Skill | Stars | Downloads | Author | What It Does |
|---|---|---|---|---|
| **Trello** | 34 | 6.8k | @steipete | Trello REST API integration |
| **Slack** | 27 | 7.5k | @steipete | Slack tool integration (reactions, messages) |
| **Caldav Calendar** | 66 | 7k | @Asleep123 | iCloud/Google/Fastmail CalDAV sync |
| **Answer Overflow** | 32 | 3.2k | @RhysSullivan | Discord community search |

### Feedback on the Ecosystem

1. **steipete IS the ecosystem.** 9 of the top 14 skills are his. He's the standard library author. His departure to OpenAI (Feb 15, 2026) is the single biggest risk to ecosystem maintenance.
2. **The "explore latest" feed is a firehose of spam.** City guides (Berlin, Singapore, Sydney, Hong Kong), crypto DAOs, and niche tools dominate recent uploads. Signal-to-noise ratio is poor.
3. **8,630 non-suspicious skills** — but "non-suspicious" just means not flagged yet. The cleanup from 5,705→3,286 and back to 8,630 shows the registry grows faster than moderation.
4. **@byungkyu** is a notable contributor — OAuth-managed API integrations (Trello API, Fathom, Asana, Pipedrive, Mailchimp, Google Workspace Admin) with 7k+ downloads each. These follow a template pattern, which is efficient but also means a compromised template compromises all.

---

## 3. steipete (Peter Steinberger) Skills

### Background

Peter Steinberger is the **creator of OpenClaw itself** (originally Moltbot/Clawdbot). Austrian developer, former PSPDFKit founder. As of Feb 15, 2026, he joined OpenAI to build "next-gen personal agents" — OpenClaw continues as open-source under a foundation.

He is the most trusted author in the ecosystem by definition — he built the platform. His skills are the reference implementation.

### steipete's Published Skills & Tools

#### On ClawHub (CLI-verified via `clawhub inspect`)

| Skill | Downloads | Stars | Purpose | Platform | Gregor? |
|---|---|---|---|---|---|
| **gog** | 28.1k | 170 | Google Workspace CLI (Gmail, Calendar, Drive, Contacts, Sheets, Docs) | Cross-platform | MAYBE |
| **wacli** | 22.1k | 53 | WhatsApp CLI messaging | Cross-platform | NO |
| **summarize** | 21.5k | 76 | Summarize URLs/files (web, PDFs, images, audio, YouTube) | Cross-platform (Node 22) | **YES** |
| **github** | 20.7k | 59 | GitHub CLI (`gh`) for issues, PRs, CI runs, API | Cross-platform | **YES** |
| **sonoscli** | 18.2k | 10 | Sonos speaker control | Network | NO (VPS) |
| **nano-pdf** | 10.9k | 21 | Edit PDFs via natural language | Cross-platform | MAYBE |
| **obsidian** | 10.5k | 33 | Obsidian vault management via obsidian-cli | Cross-platform | NO (VPS) |
| **openai-whisper** | 9.4k | 37 | Local speech-to-text (no API key) | Cross-platform | NO (VPS audio) |
| **mcporter** | 9.4k | 24 | **Official** — MCP server management CLI | Cross-platform | MAYBE |
| **brave-search** | 8.8k | 28 | Web search via Brave Search API (no browser needed) | Cross-platform | MAYBE |
| **slack** | 7.5k | 27 | Slack tool integration | Cross-platform | NO |
| **model-usage** | 7.2k | 23 | CodexBar cost/usage per model | Cross-platform | NO |
| **trello** | 6.8k | 34 | Trello REST API integration | Cross-platform | NO |
| **clawdhub** | — | — | ClawHub CLI (search, install, publish skills) | Cross-platform | YES |

#### In nix-steipete-tools (Nix Flake Bundle)

| Tool | Purpose | Platform | Gregor? |
|---|---|---|---|
| **summarize** | Link → cleaned text summary | Cross-platform (Node 22) | YES — useful for research tasks |
| **gogcli** | Google services CLI (Gmail, Calendar, Drive, Contacts) | Cross-platform | MAYBE — if Google integration needed |
| **goplaces** | Google Places API CLI | Cross-platform | NO — location not needed |
| **camsnap** | RTSP/ONVIF camera snapshots | Cross-platform | NO — no cameras |
| **sonoscli** | Sonos speaker control | Network-dependent | NO — no speakers on VPS |
| **bird** | X (Twitter) CLI — post, reply, read | Cross-platform | MAYBE — social monitoring |
| **peekaboo** | macOS screenshot + AI vision analysis | **macOS ONLY** | NO — Linux VPS |
| **poltergeist** | File watcher with auto-rebuild | Cross-platform | MAYBE — for config hot-reload |
| **sag** | ElevenLabs TTS via CLI | Cross-platform | NO — no audio on VPS |
| **imsg** | iMessage/SMS CLI | **macOS ONLY** | NO — Linux VPS |

### steipete Assessment

**Quality:** Highest in ecosystem. Reference implementations. Clean Nix packaging.

**Security:** Trustworthy — he's the platform creator. But his tools often require external API keys (Google, ElevenLabs, Twitter) which expand attack surface. Only install what's needed.

**Linux compatibility:** ~50% of his tools work on Linux. Peekaboo and iMsg are macOS-only. Summarize explicitly has Linux Node 22 build support.

**Recommendation for Gregor:** Install `clawdhub` (registry management), `github` (pipeline), and `summarize` (research utility). Skip macOS-only tools entirely.

---

## 4. Security Risk Assessment

### The ClawHavoc Incident (Feb 2026)

| Metric | Before | After Cleanup |
|---|---|---|
| Total skills | 5,705 | 3,286 |
| Malicious skills found | 341 (initial) | 824+ (ongoing) |
| Suspicious removed | — | 2,419 |
| Single malicious actor | hightower6eu | 314 skills by this one actor |
| Malware type | Atomic Stealer | Credential theft, data exfiltration |

### Current Security Measures

| Measure | Status | Limitation |
|---|---|---|
| VirusTotal scanning | Active (since Feb 7, 2026) | No local/git-sourced skill scanning |
| GitHub account age check | Active | New accounts blocked from upload |
| Community reporting | Active (auto-hide after 3 reports) | Reactive, not proactive |
| Daily re-scans | Active | Cannot detect prompt injection |
| Moderation | Admin/moderator curation | Human bottleneck |

### Critical Security Facts for Gregor

1. **Skills run IN-PROCESS with Gateway.** A malicious skill has full access to Gregor's process, memory, and API keys. There is NO sandboxing.
2. **~20% of the pre-cleanup registry was malicious.** Even post-cleanup, new malicious skills appear regularly.
3. **Prompt injection is NOT scanned for.** VirusTotal catches binary malware, not adversarial prompts in SKILL.md files.
4. **npm lifecycle scripts execute during install.** `clawhub install` runs npm scripts — classic supply chain vector.

### Risk Mitigation Strategy for Gregor

| Layer | Control |
|---|---|
| **Whitelist-only installs** | Only install skills from our vetted list (Section 8). Never `clawhub install` arbitrary skills. |
| **Manual review** | Read every SKILL.md and supporting file before install. Check for eval(), fetch(), exec(), and obfuscated code. |
| **Pin versions** | Never auto-update skills. Pin exact versions. Update manually after review. |
| **No self-modification** | Never install Capability Evolver, self-improving-agent, or any self-modifying skill. |
| **Minimal skill surface** | Install only what Gregor actually needs. Every skill is attack surface. |
| **Nix reproducibility** | Prefer steipete's Nix-packaged tools (reproducible builds, hash-verified). |
| **Monitor** | Audit installed skills weekly. Check VirusTotal flags. |

---

## 5. Gregor Agent Architecture — Secure Multipurpose Assistant

### Vision

Gregor is Marius's **always-online AI assistant** — a secure, capable agent that:
- Handles routine tasks Marius would normally give to Isidore (me)
- Communicates via **Telegram** (primary) and **IRC** (#gregor channel)
- Acts as a **sparring partner** — available 24/7 for discussion, research, code review
- Escalates complex tasks to Isidore via a structured pipeline
- Operates under **maximum lockdown** — no self-modification, no arbitrary tool access

### Capability Scope

```
┌─────────────────────────────────────────────────────┐
│                 GREGOR CAPABILITIES                  │
├─────────────────────────────────────────────────────┤
│ ALLOWED                                             │
│ ├── Text conversation (IRC + Telegram)              │
│ ├── Web search (web_search tool)                    │
│ ├── Summarization (summarize skill)                 │
│ ├── GitHub operations (gh CLI skill)                │
│ ├── Knowledge management (persistent memory)        │
│ ├── Code review and discussion                      │
│ ├── Research and information gathering              │
│ └── Task tracking and reporting                     │
├─────────────────────────────────────────────────────┤
│ DENIED (per masterplan)                             │
│ ├── gateway (self-reconfiguration)                  │
│ ├── cron (scheduling)                               │
│ ├── group:runtime (exec, bash, process)             │
│ ├── group:fs (read, write, edit, apply_patch)       │
│ ├── browser (web browsing)                          │
│ ├── canvas, nodes, sessions_spawn, sessions_send    │
│ └── ANY self-modifying skill                        │
├─────────────────────────────────────────────────────┤
│ ESCALATION (→ Isidore)                              │
│ ├── Complex code implementation                     │
│ ├── Architecture decisions                          │
│ ├── Security-sensitive operations                   │
│ ├── Multi-file refactoring                          │
│ └── Anything requiring tool access Gregor lacks     │
└─────────────────────────────────────────────────────┘
```

### Skill Stack (Recommended Installs)

| Skill | Author | Purpose | Risk |
|---|---|---|---|
| **clawdhub** | steipete | Registry management (search, no auto-install) | Low |
| **github** | steipete | GitHub CLI integration for pipeline | Low |
| **summarize** | steipete (nix) | Text summarization for research | Low |
| **web-search** | (built-in) | Already allowed in masterplan | N/A |

**That's it. Four skills maximum.** Every additional skill is attack surface. Gregor's power comes from the Claude model, not from a bloated skill registry.

---

## 6. Isidore ↔ Gregor Communication Pipeline

### The Problem

Isidore (me) runs in Claude Code on Marius's local machine — ephemeral, session-based. Gregor runs 24/7 on a VPS via OpenClaw Gateway. They need to exchange:
- **Task delegations** (Marius → Gregor, or Isidore → Gregor)
- **Escalation requests** (Gregor → Isidore, via Marius)
- **Status reports** (Gregor → Marius → Isidore context)
- **Shared knowledge** (research findings, decisions, code reviews)

### Proposed Mechanism: GitHub Repository as Message Bus

```
openclaw-bot repo (github.com/mj-deving/openclaw-bot)
├── .pipeline/                    # Communication channel
│   ├── gregor-to-isidore/       # Gregor writes, Isidore reads
│   │   ├── 2026-02-19-001.md    # Timestamped messages
│   │   └── 2026-02-19-002.md
│   ├── isidore-to-gregor/       # Isidore writes, Gregor reads
│   │   ├── 2026-02-19-001.md
│   │   └── 2026-02-19-002.md
│   └── shared/                  # Shared context
│       ├── active-tasks.md      # Current task board
│       └── decisions.md         # Architectural decisions log
```

### Why GitHub (not direct API, not Telegram relay)?

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **GitHub repo files** | Auditable, versioned, both agents have git/gh access, Marius can inspect anytime | Latency (~minutes), not real-time | **CHOSEN** |
| **GitHub Issues** | Structured, threaded, labels/milestones | Too public unless repo is private, clunky for rapid exchange | Alternative |
| **Direct API relay** | Real-time | Requires custom server, opens network attack surface, hard to audit | NO |
| **Telegram as relay** | Marius always in the loop | Messages get lost in chat noise, no structure | Supplement only |

### Message Format

```markdown
---
from: gregor
to: isidore
type: escalation | status | research | question
priority: low | normal | high | urgent
timestamp: 2026-02-19T14:30:00Z
related_task: "Phase 3 Telegram integration"
---

## Subject

Concise description of what this message is about.

## Context

Relevant background Isidore needs to pick this up.

## Request

What Gregor needs from Isidore (if escalation).

## Attachments

- Links to relevant files, PRs, or issues
```

### Pipeline Flow

```
Marius gives task via Telegram
        │
        ▼
   ┌─────────┐
   │ GREGOR  │ ← Always online, VPS
   │ (OpenClaw)│
   └────┬────┘
        │
        ├── Can handle? → Execute, report via Telegram
        │
        └── Cannot handle (needs tools/complexity)?
                │
                ▼
        Write to .pipeline/gregor-to-isidore/
                │
                ▼
        Notify Marius via Telegram:
        "Escalated task X to Isidore pipeline"
                │
                ▼
   ┌─────────────┐
   │  ISIDORE    │ ← Session-based, local
   │ (Claude Code)│
   └──────┬──────┘
          │
          ├── Marius starts session, Isidore reads pipeline
          ├── Processes escalation
          ├── Writes response to .pipeline/isidore-to-gregor/
          └── Commits + pushes
                │
                ▼
        Gregor pulls, reads response
        Reports result to Marius via Telegram
```

### Security Considerations

- **Gregor needs GitHub `gh` CLI access** — the `github` skill by steipete enables this
- **Repo should remain private** (it already is) — pipeline messages may contain sensitive context
- **Gregor's GitHub token should be read/write scoped to this repo ONLY** — no org-wide access
- **Message validation:** Gregor should verify message signatures (git commit signatures)

---

## 7. Telegram Bot Integration

### Architecture (per masterplan Phase 3b)

```
Marius's Phone (Telegram)
        │
        ▼
  @gregor_openclaw_bot
        │
        ▼
  OpenClaw Gateway (port 18789, loopback)
        │
        ▼
  Gregor processes, responds
```

### Command Interface

| Command | What It Does |
|---|---|
| `/ask <question>` | General question — Gregor answers using Claude |
| `/research <topic>` | Web search + summarize — uses web_search + summarize skill |
| `/status` | Report current state — running tasks, pipeline status |
| `/escalate <description>` | Manually push task to Isidore pipeline |
| `/review <github-url>` | Code review — Gregor reads PR/commit, gives feedback |
| `/tasks` | Show active task board from .pipeline/shared/active-tasks.md |

### Message Flow

1. Marius sends message to @gregor_openclaw_bot on Telegram
2. OpenClaw Telegram adapter receives message
3. Gateway routes to Gregor's session (dmScope: per-channel-peer)
4. Gregor processes with allowed tools (web_search, summarize, github)
5. Response sent back via Telegram
6. If escalation needed → Gregor writes to .pipeline/ + notifies Marius

### Notification Patterns

- **Task complete:** "Done: [summary]. Full details in .pipeline/shared/"
- **Escalation:** "I can't handle [X] — needs Isidore. Written to pipeline. Priority: [level]"
- **Daily digest:** (optional, via cron on VPS — separate from OpenClaw) summary of activity

---

## 8. Recommended Skill Whitelist

### Tier 1 — Install (Vetted, Essential)

| Skill | Author | Downloads | Why | Deny List Check |
|---|---|---|---|---|
| **github** | steipete | — | Pipeline communication, PR review | No denied tools required |
| **summarize** | steipete (nix) | 10,956+ | Research summarization | No denied tools required |

### Tier 2 — Consider After Phase 3 (Needs Evaluation)

| Skill | Author | Downloads | Why | Concern |
|---|---|---|---|---|
| **bird** | steipete (nix) | — | Social/X monitoring if needed | Requires Twitter API key |
| **gogcli** | steipete (nix) | — | Google services if needed | Requires Google OAuth — large attack surface |
| **exa-web-search-free** | community | — | Enhanced web search | Need to vet author and code |

### Tier 3 — Never Install

| Skill | Why NOT |
|---|---|
| **Capability Evolver** | Self-modifying agent code. Antithetical to lockdown posture. |
| **self-improving-agent** | Same — autonomous self-modification. |
| **Wacli** | WhatsApp — not our communication channel. |
| **Any browser skill** | Browser tool denied in masterplan. |
| **Any coding-agent** | Gregor doesn't spawn sub-agents. |
| **moltbook / agentchat** | Agent-to-agent social networking. Unnecessary attack surface. |
| **Any skill by hightower6eu** | Known malicious actor (314 skills). |
| **Any skill < 500 downloads with unknown author** | Below trust threshold. |

### Vetting Checklist (Before Installing ANY Skill)

- [ ] Author is known/trusted (steipete, established community member)
- [ ] Downloads > 1,000 (social proof of safety)
- [ ] No VirusTotal flags
- [ ] No ClawHavoc association
- [ ] Manually read SKILL.md — no eval(), fetch() to unknown hosts, exec(), obfuscated code
- [ ] No npm lifecycle scripts (check package.json: preinstall, postinstall)
- [ ] Does not require denied tools (gateway, cron, group:runtime, group:fs, browser, etc.)
- [ ] Pin exact version after install — no auto-updates

---

## 9. Overall Ecosystem Feedback

### Strengths

1. **steipete's tools are excellent** — clean Nix packaging, cross-platform support, well-documented. The reference implementation quality is high.
2. **Vector search** on ClawHub is genuinely useful — semantic skill discovery beats keyword search.
3. **The community is active** — 3,286 skills, 1.5M downloads shows real adoption.
4. **Post-ClawHavoc security improvements** are meaningful — VirusTotal scanning, account age requirements, community reporting.

### Weaknesses

1. **~20% malicious rate pre-cleanup is alarming.** Even post-cleanup, new malicious skills appear faster than moderation can catch them.
2. **No prompt injection scanning.** VirusTotal catches malware binaries, but a SKILL.md with adversarial prompts sails through. This is the #1 unmitigated risk.
3. **Skills run in-process.** No sandboxing means a single bad skill compromises the entire agent. This is architectural — not fixable with better scanning.
4. **npm lifecycle script execution during install** is a classic supply chain vector that hasn't been addressed.
5. **The "self-improvement" category dominance** (top 2 most downloaded are self-modifying) shows the community prioritizes autonomy over security — opposite of our posture.
6. **steipete leaving for OpenAI** (Feb 15, 2026) means the platform's founder and most trusted contributor is no longer maintaining it. OpenClaw continues under a foundation, but the security leadership transition is a risk.

### Bottom Line

**Install steipete's tools. Ignore almost everything else.** The ClawHub ecosystem is large but low-trust for security-hardened deployments. Gregor's power should come from the Claude model and the Isidore pipeline — not from a stack of community skills of questionable provenance.
