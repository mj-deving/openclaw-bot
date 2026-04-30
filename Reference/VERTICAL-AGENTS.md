# Vertical Agent-Pack Design

**Date:** 2026-04-30
**Status:** Design (no deployments yet — bootstrap follows this spec)
**Driving plan:** `Plans/next-session-agent-packs.md`
**Companion docs:** `SKILL-LANDSCAPE.md` (skill catalog), `DOCTRINE-AUDIT-AT-USAGE-TIME.md` (skill policy), `ATLASFORGE-PATTERNS.md` (chassis identity), `KNOWN-BUGS.md` (mandatory config gotchas)

## Pack Overview

5 OpenClaw bots on a single VPS, multi-user pattern. Each bot is `<user>@vps` with its own systemd service, gateway port, workspace, sudoers drop-in, and AtlasForge identity scaffold. The chassis (defense-shield + ClawKeeper plugins, scoped sudo wrappers, OpenRouter compaction, Codex OAuth chat) is shared. **Only skill / channel / persona maps differ.**

| Bot | Status | Verticals | Channels | Linux user | Port | Persona origin |
|-----|--------|-----------|----------|-----------|------|---------------|
| **Gregor** | Live | V9 Personal CRM · V15 Health/lifestyle · (V2 Research being transferred to Hypatia) | TG | openclaw | 18789 | Kafka — operator/observer |
| **Aldine** | New (1st) | V3 Content/Marketing/Entrepreneur · V8 Creative writing · V12 Design/UI | TG · Slack socket · Discord DM-only Ph1 | aldine | 18791 | Aldus Manutius — Renaissance master printer/publisher |
| **Vesalius** | New (2nd) | V1 Dev/code-copilot · V11 Data/SQL/BI · V7 Project Management | Slack socket · CLI | vesalius | 18792 | Andreas Vesalius — anatomist / inspector of structures |
| **Hypatia** | New (3rd) | V2 Research · V10 Education · V14 Knowledge/PKM | TG · Discord DM | hypatia | 18793 | Hypatia of Alexandria — scholar / synthesist |
| **Dismas** | Revive (4th) | V5 Security-operator · V4 Sysadmin/VPS-ops · V13 Devops/cloud | TG-only allowlist=[Marius] | dismas | 18790 | The Penitent Thief — adversary/redeemer twin |

**V6 Finance/analytics is DEFERRED** — see "Deferred verticals" below.

## Coverage Map (V1–V15 → Bot)

| Vertical | Owner | Notes |
|----------|-------|-------|
| V1 Dev/code-copilot | **Vesalius** | Workspace-scoped pair; never holds prod credentials |
| V2 Research | **Hypatia** | Transferred from Gregor with 2-week co-existence period |
| V3 Content/Marketing/Entrepreneur | **Aldine** (LOCKED flagship) | Marius's stated #1 interest |
| V4 Sysadmin/VPS-ops | **Dismas** | Audit + drift response loops |
| V5 Security-operator | **Dismas** | MUST be isolated from dev-paste paths (Security Architect ruling) |
| V6 Finance/analytics | **DEFERRED** (future Midas) | Ad-hoc routes to Hypatia/Gregor with bundled skills until trigger |
| V7 Project Management | **Vesalius** | Bundled `gh-issues`/`taskflow`/`beads-coordination` already cluster here |
| V8 Creative writing | **Aldine** | Same voice/style memory as V3 |
| V9 Personal CRM | **Gregor** | Existing; `gog`/`himalaya`/PKM bundled skills |
| V10 Education | **Hypatia** | Synthesis cluster (long-context, teach-back) |
| V11 Data/SQL/BI | **Vesalius** | Same terminal-mode / sandbox tooling as V1 |
| V12 Design/UI | **Aldine** | Visual content lives in publishing pipeline |
| V13 Devops/cloud | **Dismas** | SPLIT FROM Vesalius — prod cloud token isolated from dev paste |
| V14 Knowledge/PKM | **Hypatia** | Feeds research synthesis more than content |
| V15 Health/lifestyle | **Gregor** | Personal-CRM-adjacent; aggregator-only skills (deferred build-out) |

**14 of 15 covered.** V6 deferred with named revival trigger.

## Bot Specifications

### Aldine — Flagship Publisher (1st deployment)

```yaml
codename: Aldine
linux_user: aldine
systemd_unit: aldine.service
gateway_port: 18791
workspace: /home/aldine/.openclaw/workspace
verticals: [V3, V8, V12]
```

**Why this cluster:** Output-heavy, low-secret, all three live in the publishing pipeline. V3+V8 share voice/style memory; V12 design is visual-content adjacent. Concentrates the inevitable Slack/Discord ingestion risk on ONE bot whose blast radius is "embarrassing draft," not "drained wallet" (Security Architect's framing).

**Channel surface:**
- **Telegram:** primary (mobile-first capture). Allowlist=[Marius] initially.
- **Slack:** socket-mode (loopback-safe). Phase 2 after Telegram stable.
- **Discord:** DM-only Phase 1 (preserves loopback; no tunnel needed). Guild-wide deferred to v1.0 channel adapter.
- **Web (loopback HTTP) + CLI:** inherent.
- **L2 sanitization MANDATORY** on all Slack/Discord paths (Layer-2 prompt-injection scoping).

**Models:**
```yaml
agents.defaults.model:
  primary: openai-codex/gpt-5.4
  fallbacks:
    - openrouter/anthropic/claude-sonnet-4-6
    - openrouter/anthropic/claude-haiku-4-5
    - openrouter/openrouter/free  # acceptable here — no secrets at risk
agents.defaults.compaction.model: openrouter/openai/gpt-4.1-mini
```

**Skill pack (curated from `SKILL-LANDSCAPE.md` V3+V8+V12, audit-at-usage-time):**
- Forks: `content-marketer`, `seo-content-auditor`, `seo-keyword-strategist`, `copywriter`, `brand-voice`, `novelist`, `screenwriter`, `ui-ux-designer`, `design-system-curator`
- Bundled: `xurl` (X/Twitter), `summarize`, `gog` (Gmail/Drive read), `obsidian`, `notion`, `nano-pdf`, `gifgrep`, `video-frames`, `taskflow`
- Inspiration (audit-and-author-our-own): `social-media-strategist`, `newsletter-writer`, `repurposer`

**Persona scaffolding:** AtlasForge full chassis. IDENTITY.md primary persona = "Aldine — printer-publisher in service of Marius's voice." AGENTS.md = publishing pipeline procedures (capture → draft → revise → publish → repurpose).

**Differentiator from Gregor:** Gregor is private operator/CRM — never speaks publicly. Aldine is the **only bot allowed to touch public channels**. Gregor handles people; Aldine ships artifacts.

---

### Vesalius — Terminal-Mode Pair (2nd deployment)

```yaml
codename: Vesalius
linux_user: vesalius
systemd_unit: vesalius.service
gateway_port: 18792
workspace: /home/vesalius/.openclaw/workspace
verticals: [V1, V11, V7]
```

**Why this cluster:** Code, query, and project-mgmt share a mental mode (structured artifacts, idempotent ops, terminal-native tools). V13 Devops/cloud is **deliberately SPLIT to Dismas** to keep prod cloud tokens away from dev-copilot's "fix this" paste surface (Security Architect's strongest landed argument).

**Channel surface:**
- **Slack:** socket-mode (dev-team lingua franca). Primary.
- **CLI:** inherent (`openclaw agent --message`).
- **No Telegram, no Discord, no web for chat:** code blocks suck on phone; untrusted code paste = game over.

**Models:**
```yaml
agents.defaults.model:
  primary: openai-codex/gpt-5.4   # Codex shines on code
  fallbacks:
    - openrouter/anthropic/claude-sonnet-4-6
    - openrouter/anthropic/claude-haiku-4-5
  # NO free fallback — production-adjacent code reasoning never silently degrades
agents.defaults.compaction.model: openrouter/openai/gpt-4.1-mini
```

**Skill pack:**
- Forks: `code-reviewer`, `debugger`, `test-generator`, `refactor-architect`, `python-pro`, `typescript-pro`, `rust-pro`, `legacy-modernizer`, `api-designer`, `sql-pro`, `database-admin`, `data-engineer`, `project-manager`, `scrum-master`
- Bundled: `coding-agent`, `gh-issues`, `github`, `github-beads-workflow`, `oracle`, `gemini`, `tmux`, `taskflow`, `taskflow-inbox-triage`, `beads-coordination`
- Inspiration (audit-and-author-our-own): `analytics-engineer`, `dashboard-architect`, `risk-register`

**Persona scaffolding:** AtlasForge chassis. IDENTITY.md persona = "Vesalius — anatomist who reads codebases like cadavers, never moves to surgery without a map." AGENTS.md = TDD-first, save-point-pattern, atomic-commit discipline.

**Differentiator from Gregor:** Gregor never opens a repo. Vesalius lives in workspace-scoped pairs and only reads/writes/commits within `/home/vesalius/repos/<allowed>`.

---

### Hypatia — Synthesis Bot (3rd deployment)

```yaml
codename: Hypatia
linux_user: hypatia
systemd_unit: hypatia.service
gateway_port: 18793
workspace: /home/hypatia/.openclaw/workspace
verticals: [V2, V10, V14]
```

**Why this cluster:** All three are "long-context reading, structured synthesis, teach-back" mode. V14 PKM resolves the council's tension on the side of research (PKM feeds research more than content; content gets atomic outputs, research gets graphs of knowledge). V2 transfers from Gregor with co-existence period.

**Channel surface:**
- **Telegram:** primary (read-aloud while walking; voice memos via `openai-whisper`).
- **Discord:** DM-only (research threads in private). Guild-wide deferred.
- **No Slack** (research isn't team comms; would force events-API tunnel).
- **Web/CLI:** inherent.

**Models:**
```yaml
agents.defaults.model:
  primary: openai-codex/gpt-5.4   # Codex Pro long-context capable
  fallbacks:
    - openrouter/anthropic/claude-sonnet-4-6
    - openrouter/anthropic/claude-haiku-4-5
    - openrouter/openrouter/free
agents.defaults.compaction.model: openrouter/openai/gpt-4.1-mini
```

**Skill pack:**
- Forks: `research-agent`, `literature-reviewer`, `competitive-analyst`, `tutor`, `socratic-tutor`
- Bundled: `omniweb-research-agent` (transferred from Gregor's workspace), `summarize`, `session-logs`, `blogwatcher`, `nano-pdf`, `obsidian`, `apple-notes`, `bear-notes`, `notion`, `openai-whisper`
- Inspiration (audit-and-author-our-own): `deep-researcher`, `fact-checker`, `data-extractor`, `pkm-curator` (V14 author opportunity), `obsidian-bridge` (V14 author opportunity), `study-plan-builder`, `flashcard-author`

**Persona scaffolding:** AtlasForge chassis. IDENTITY.md persona = "Hypatia — Alexandrian scholar; synthesizes, teaches back, never claims certainty without sources." AGENTS.md = epistemic-tagging discipline (consensus / observed / inferred / speculative / contrarian).

**Differentiator from Gregor:** Gregor is "what's happening?" (operator/CRM); Hypatia is "what does it mean?" (synthesis). Gregor's `omniweb-research-agent` overlay narrows to operator-context only after V2 transfer.

---

### Dismas — Adversary / Ops Twin (4th deployment, REVIVED)

```yaml
codename: Dismas
linux_user: dismas               # already exists from prior scaffold
systemd_unit: dismas.service     # already exists
gateway_port: 18790              # already reserved
workspace: /home/dismas/.openclaw/workspace
verticals: [V5, V4, V13]
```

**Why this cluster:** Security Architect's blast-radius argument wins — V5 must be isolated from V1 (dev paste) and V3 (Discord ingestion). Bundling V5 with V4 (sysadmin) and V13 (prod cloud) under ONE root-tier isolation boundary is the cleanest split that respects security without burning a bot per single vertical (Pragmatist's density argument). Marius-Voice's "adversary/ops twin" framing names the role.

**Channel surface:**
- **Telegram-only, allowlist=[Marius]**, group-policy=allowlist.
- **NEVER Slack, Discord, web.** Untrusted ingestion paths reach root-tier credentials.
- **Sub-agent isolation:** if Dismas spawns sub-agents, `agents.defaults.subagents.model` MUST be a non-OAuth API-key model (KNOWN-BUGS #6).

**Models:**
```yaml
agents.defaults.model:
  primary: openai-codex/gpt-5.4
  fallbacks:
    - openrouter/anthropic/claude-sonnet-4-6
    - openrouter/anthropic/claude-haiku-4-5
  # NO free fallback — security ops never silently degrades to an unvetted model
agents.defaults.compaction.model: openrouter/openai/gpt-4.1-mini
```

**Skill pack:**
- Forks: `security-auditor`, `penetration-tester` (sandboxed-only, scope-of-use review per invocation), `devops-engineer`, `incident-responder`, `linux-admin`, `cloud-architect`, `kubernetes-operator`, `terraform-pro` (state-file-secret-leak audit before fork)
- Bundled: `healthcheck`, `node-connect`, `1password`, `tmux`, `summarize`
- Plugins: ClawKeeper (audit/drift), defense-shield (Layer-1..6 prompt-injection)
- Inspiration (audit-and-author-our-own): `dependency-auditor`, `cve-scanner`, `secret-scanner`, `log-analyst`, `backup-operator`, `sre-on-call`
- **Publish-back candidate:** the project's 6-layer defense system → release as `prompt-injection-defender` (more mature than anything in awesome-list)

**Persona scaffolding:** AtlasForge chassis. IDENTITY.md persona = "Dismas — the penitent thief; knows attacks because he's been one; second-pair-of-eyes for Gregor's outputs." AGENTS.md = adversarial-review-of-Gregor procedure, drift-detection loops, blast-radius checklist.

**Concrete capability gap that justifies revival** (per Marius-Voice's "name the gap" challenge): **Adversarial review of Gregor's outputs** — currently nobody owns this, so prompt-injection successes against Gregor go undetected. **VPS hygiene loops** — `audit-vps.sh`, ClawKeeper drift response, fail2ban tuning have no resident operator. **Cross-bot adversary** — different model lineage means Dismas can question Gregor's reasoning genuinely.

**Differentiator from Gregor:** Gregor *uses* defense-shield as a passive plugin; Dismas *operates* it as an active workflow. Gregor never holds prod-cloud credentials; Dismas does (scoped sudo + dedicated `auth-profiles.json`).

---

### Gregor — Existing Operator (UNCHANGED)

```yaml
codename: Gregor
linux_user: openclaw     # existing
systemd_unit: openclaw.service   # existing
gateway_port: 18789      # existing
workspace: /home/openclaw/.openclaw/workspace
verticals: [V9, V15]     # V2 transferred to Hypatia with co-existence period
```

**No migration.** Gregor stays as the chassis reference — its 50-bundled-skill setup, AtlasForge identity (OmniWeb research overlay confirmed intentional), Codex OAuth chat path, and OpenRouter Sonnet/Haiku/free fallback chain are the template every new bot copies.

**V2 handover plan:** 2-week co-existence period during which Gregor's `omniweb-research-agent` overlay narrows to "operator-context research only" (research about Marius's day-to-day people/projects, not deep web synthesis). Hypatia takes over deep research. Memory copy of relevant research files transferred to Hypatia's workspace at handover.

## Deferred Verticals

### V6 Finance/analytics — DEFERRED until Midas trigger

**Why deferred:** Security Architect's blast-radius argument prevails — finance credentials cannot share a process with content publishing or sub-agent fan-out, and dedicating a single-vertical bot now is premature density expense. Ad-hoc finance work routes to:
- **Hypatia** — read-only synthesis (financial-analyst, kpi-dashboard-builder skills, no credentials)
- **Gregor** — CRM-adjacent expense tracking (gog Gmail receipts, bookkeeper-style categorization with bundled skills only)

**Revival trigger:** Marius operates client funds OR runs an entity with payroll/AR/AP needs. At that point: revive as **Midas** per Security Architect's design — single-purpose finance bot, dedicated `auth-profiles.json` no other bot can read, separate Linux user, Telegram-only allowlist=[Marius], no public channels under any circumstance.

### Channel staging — DEFERRED for some bots
- Aldine Discord guild-wide → wait for v1.0 channel adapter (currently alpha)
- Vesalius public channels → never (dev-paste surface)
- Dismas any non-TG → never (root-tier blast radius)

## Bootstrap Pattern (overlay on GUIDE.md)

**Goal:** From "I want vertical N agent" to "agent running" in <30 minutes.

This is a vertical-pack overlay on the existing 15-phase `GUIDE.md` flow — does NOT rewrite the GUIDE. See `GUIDE.md` Appendix L (added 2026-04-30) for the templated commands.

**High-level shape (per new bot):**
1. **User + sudoers** (3 min) — `sudo openclaw-install-user <bot>` + drop-in scoped sudoers for that bot's user
2. **Workspace + AtlasForge chassis** (5 min) — copy Gregor's workspace template; substitute persona/IDENTITY/AGENTS files from `Reference/AtlasForge-Bundle/`; pin workspace path under `/home/<bot>/.openclaw/workspace` (NEVER /tmp — KNOWN-BUGS #7)
3. **Authentication** (5 min) — Codex OAuth done locally then `scp` to `/home/<bot>/.openclaw/agents/main/agent/auth-profiles.json` (mode 0600); add OpenRouter API key for compaction
4. **Config** (5 min) — generate `openclaw.json` from per-bot template (port, workspace, channels, models per spec above); `openclaw config validate` clean; **read-back from live JSON** post-restart (KNOWN-BUGS #8)
5. **Channels** (5 min) — register Telegram bot token; opt-in Slack socket-mode + Discord DM-only per bot's spec
6. **Skill pack** (5 min) — copy bundled skills (already on host); fork upstream skills into `~/<bot>/.openclaw/skills/` and run `openclaw clawkeeper scan-skill /path` per skill (audit-at-usage-time gate per `DOCTRINE-AUDIT-AT-USAGE-TIME.md`)
7. **Plugins + linger** (2 min) — install ClawKeeper + defense-shield; `loginctl enable-linger <bot>`
8. **Smoke test** (varies) — `openclaw agent --agent main --json --message "ping"`; check identity, fallback chain, workspace path

## Top 5 Risks + Mitigations

1. **Codex OAuth Pro rate limit across 5 active bots** (UNKNOWN ceiling) — Mitigation: stagger deployments (1 bot per 2 weeks); monitor `model-usage` skill output per bot; OpenRouter Sonnet keys ready as immediate fallback for any 429s. **File bead.**

2. **Sub-agent IDENTITY-loss** (orchestrator workers lose persona consistency — CONCEPTS-INVENTORY §6) — Mitigation: Aldine + Hypatia (most fan-out-prone) load IDENTITY essentials into AGENTS.md as a hard fallback; sub-agents use API-key model only (KNOWN-BUGS #6). **File bead.**

3. **V2 ownership transfer Gregor → Hypatia** (handover risk) — Mitigation: 2-week co-existence; memory file copy; Gregor's OmniWeb overlay narrows to operator-context only post-handover. **File bead.**

4. **Audit-at-usage-time queue rot** (skills loaded `quarantined` until signed `audit.json`; if audit never runs, skill never works → user disables gate → catastrophe) — Mitigation: `DOCTRINE-AUDIT-AT-USAGE-TIME.md` defines fail-closed gate + ClawKeeper SC-* rule mapping; bead `32h` ClawKeeper FP tuning **MUST close** before doctrine becomes hard gate. **File bead.**

5. **Dismas V5+V13 co-location** (Security flagged dev-paste + prod-cloud as game over; we split V1 to Vesalius but V13 still co-locates with V5) — Mitigation: TG-only allowlist=[Marius] (no Discord/Slack ingestion), separate `auth-profiles.json`, ClawKeeper SC-CRED-* enforcement, no sub-agent spawning of untrusted-input skills. **File bead.**

## Bootstrap Order

1. **Aldine** — Marius's #1 stated interest; flagship validates the chassis-overlay pattern; lowest blast-radius for first-deployment learning
2. **Vesalius** — high-utility for ongoing PAI dev; validates Slack socket-mode adapter; Codex shines on code (model-fitness highest)
3. **Hypatia** — research bot needs V2 transfer from Gregor (most coordination)
4. **Dismas revival** — security-isolated, requires most-careful chassis hygiene; do this last once the bootstrap pattern has been exercised three times

## Council Decision Log

Synthesized 2026-04-30 from 4-seat council debate (2 rounds: opening proposals + cross-examination):
- **Pragmatist** (Felix/Cato/Ada, defer 4) — conceded V12 cluster + Vesalius naming
- **Coverage Maximalist** (Archimedes/Pulitzer/Hippocrates, revive Dismas) — defended quant-cluster but conceded V14 → Aldine/Hypatia, V12 → Pulitzer
- **Security Architect** (Goliath/Midas/Scribe, V5 alone) — strongest argument: dev-paste + prod-cloud = game over → V13 split off Vesalius; conceded V4 audit fold; HELD line on V5 isolation
- **Marius-Voice** (Aldine/Vesalius/Hypatia, revive Dismas adversary) — conceded V6 overflow; surfaced V14 placement tension

**Final shape borrows:** Marius-Voice's three-bot codenames + Coverage Max's Dismas revival role + Security Architect's V13-split + Pragmatist's V12 cluster concession. **V6 deferred** (Security Architect wins on credential isolation; not enough current need to justify Midas).

**Cross-references:**
- `SKILL-LANDSCAPE.md` — top-100 skill catalog feeding the per-bot packs above
- `DOCTRINE-AUDIT-AT-USAGE-TIME.md` — skill audit policy for every fork
- `ATLASFORGE-PATTERNS.md` — chassis identity layer
- `KNOWN-BUGS.md` — config gotchas (#6 OAuth compaction, #7 /tmp workspace, #8 strict-schema auto-restore)
- `GUIDE.md` Appendix L (to be added) — vertical-pack bootstrap overlay
