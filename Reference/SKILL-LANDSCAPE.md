# Skill Landscape — Vertical-Indexed Catalog

**Last updated:** 2026-04-30
**Sources:** awesome-claude-code-subagents (real-world proxy for "awesome-openclaw-skills") + clawskills.sh top-100 (proxy ranks; numeric counts are order-of-magnitude, not audit-grade) + bundled OpenClaw 50-skill inventory (`openclaw skills list` from VPS, 11/55 ready as of 2026-04-30).
**Companion docs:** `SKILLS-AND-TOOLS.md` (skill mechanics + supply-chain risk), `DOCTRINE-AUDIT-AT-USAGE-TIME.md` (doctrine), `VERTICAL-AGENTS.md` (per-bot skill packs).

> **Doctrine shift logged:** As of 2026-04-30 the project moved from *bundled-only-at-author-time* to *forks-with-audit-at-usage-time* — see `DOCTRINE-AUDIT-AT-USAGE-TIME.md`. This catalog is the input to that audit pipeline. It does NOT authorize installation.

## Vertical Taxonomy (V1–V15)

| Vertical | One-line | Pack-owner bot | Avg cluster size in awesome-list |
|----------|----------|----------------|---------------------------------|
| V1 Dev / code-copilot | Coding assistance, review, refactor, test-gen | **Vesalius** | Large (~15+ subagents) |
| V2 Research / analyst | Multi-source web/document synthesis | **Hypatia** (transfer from Gregor) | Medium-large |
| V3 Content / Marketing / Entrepreneur | Long-form + social + SEO + brand voice | **Aldine** (LOCKED flagship) | Large (~15+) |
| V4 Sysadmin / VPS-ops | Linux host, log triage, hardening | **Dismas** | Medium |
| V5 Security-operator | Threat model, secret scan, CVE, prompt-injection | **Dismas** | Medium-large |
| V6 Finance / analytics | Personal+SMB FP&A, tax, accounting | **DEFERRED** (future Midas) | Medium |
| V7 Project Management | Backlog, sprint, risk register | **Vesalius** | Medium |
| V8 Creative writing | Fiction, screenplay, narrative | **Aldine** | Small-medium |
| V9 Personal CRM | Contact memory, follow-ups, life admin | **Gregor** | Small |
| V10 Education / learning | Tutoring, study-plan, spaced-rep | **Hypatia** | Medium (fastest-growing) |
| V11 Data / SQL / BI | Schema, queries, dashboards | **Vesalius** | Medium-large |
| V12 Design / UI | Visual, UX flow, design tokens | **Aldine** | Medium |
| V13 Devops / cloud | IaC, K8s, multi-account | **Dismas** | Large (most populated section) |
| V14 Knowledge / PKM | Note-graph, journaling, second-brain | **Hypatia** | Small-medium |
| V15 Health / habits / lifestyle | Fitness, nutrition, sleep, habit | **Gregor** | Small (emerging) |

## Per-Vertical Skill Catalog

Each entry: `skill-id` `[trust-tag]` `(source)` — purpose. Trust tags: `[bundled]` already in OpenClaw 50; `[fork-with-audit]` top-100 from awesome-list; `[inspiration-only]` aggregator-only; `[dangerous-avoid]` typosquat / malicious-flagged. Default for top-100 awesome entries = `[fork-with-audit]`.

### V1 — Dev / code-copilot (→ Vesalius)
- `code-reviewer` `[fork-with-audit]` (awesome) — PR-style review with severity tiers
- `debugger` `[fork-with-audit]` (awesome) — stack-trace + repro-loop driver
- `test-generator` / `test-writer` `[fork-with-audit]` (awesome) — unit + integration scaffolding
- `refactor-architect` `[fork-with-audit]` (awesome) — large-scale rename / extract-module
- `python-pro` / `typescript-pro` / `rust-pro` `[fork-with-audit]` (awesome) — idiomatic-style reviewer trio
- `legacy-modernizer` `[fork-with-audit]` (awesome) — incremental migration playbooks
- `api-designer` `[fork-with-audit]` (awesome) — REST/GraphQL contract review
- `coding-agent` `[bundled]` — Codex/Claude Code/Pi delegation router (already on VPS)
- `gh-issues` `[bundled]`, `github` `[bundled]`, `github-beads-workflow` `[bundled]` — GitHub + Beads ops
- `oracle` `[bundled]` — multi-engine prompt + file bundling
- `gemini` `[bundled]` — one-shot Q&A fallback
- `tmux` `[bundled]` — interactive CLI driver

### V2 — Research / analyst (→ Hypatia)
- `research-agent` `[fork-with-audit]` (awesome) — multi-source synthesis with citation discipline
- `deep-researcher` / `research-orchestrator` `[inspiration-only]` (aggregator) — multi-step search → synth
- `literature-reviewer` `[fork-with-audit]` (awesome) — academic-paper survey w/ structured tables
- `competitive-analyst` `[fork-with-audit]` (awesome) — market scan + positioning
- `fact-checker` `[inspiration-only]` (aggregator) — claim → source verification
- `data-extractor` `[inspiration-only]` (aggregator) — table/PDF → structured JSON
- `omniweb-research-agent` `[bundled, workspace]` — Marius's existing research bundle (legacy: stays on Gregor for operator-context, transfers V2 ownership to Hypatia)
- `summarize` `[bundled]` — URL/podcast/file → text fallback
- `session-logs` `[bundled]` — own-transcript search via jq
- `blogwatcher` `[bundled]` — RSS/Atom monitoring

### V3 — Content / Marketing / Entrepreneur (→ Aldine flagship)
- `content-marketer` `[fork-with-audit]` (awesome) — full content-calendar driver
- `seo-content-auditor` / `seo-keyword-strategist` `[fork-with-audit]` (awesome) — on-page + keyword work
- `copywriter` / `brand-voice` `[fork-with-audit]` (awesome) — tone-matched short-form
- `social-media-strategist` `[inspiration-only]` (aggregator) — platform-specific post adaptation
- `newsletter-writer` `[inspiration-only]` (aggregator) — recurring drafter
- `video-script-writer` `[inspiration-only]` (aggregator) — short-form vertical-video scripts
- `repurposer` `[inspiration-only]` (aggregator) — one canonical → N channels
- `xurl` `[bundled]` — X/Twitter API authenticated client
- `wacli` `[bundled]` — WhatsApp send/sync (use with care)

### V4 — Sysadmin / VPS-ops (→ Dismas)
- `devops-engineer` `[fork-with-audit]` (awesome) — CI/CD + systemd + container generalist
- `incident-responder` `[fork-with-audit]` (awesome featured) — alert → triage → postmortem
- `log-analyst` `[inspiration-only]` (aggregator) — journald/syslog pattern-mining
- `linux-admin` `[fork-with-audit]` (awesome) — package/user/service ops
- `backup-operator` `[inspiration-only]` (aggregator) — restore-drill driver
- `healthcheck` `[bundled]` — host hardening + risk posture (already in use on Gregor)
- `node-connect` `[bundled]` — pairing/gateway diagnostics
- `1password` `[bundled]` — secrets via op CLI

### V5 — Security-operator (→ Dismas)
- `security-auditor` `[fork-with-audit]` (awesome featured) — STRIDE/threat-model walkthroughs
- `penetration-tester` `[fork-with-audit + sandboxed-only]` (awesome) — recon + exploit-chain narration; **MUST scope-of-use review per invocation**
- `dependency-auditor` / `cve-scanner` `[inspiration-only]` (aggregator) — SBOM diff + CVE map
- `secret-scanner` `[inspiration-only]` (aggregator) — git history sweep
- `prompt-injection-defender` `[fork-with-audit]` (awesome, only 1-2 quality forks) — overlaps own 6-layer defense; **publish-back candidate** (project's defense is more mature than anything available)
- ClawKeeper plugin `[bundled, project-installed]` — config audit + drift detection

### V6 — Finance / analytics (DEFERRED)
- `financial-analyst` `[fork-with-audit]` (awesome) — variance + ratio analysis
- `quant-analyst` `[fork-with-audit]` (awesome) — backtest + signal sketch
- `tax-advisor` `[fork-with-audit + disclaimer-wrapper]` (awesome) — jurisdiction-tagged Q&A
- `bookkeeper` `[inspiration-only]` (aggregator) — categorize transactions, GL-style
- `kpi-dashboard-builder` `[inspiration-only]` (aggregator) — metric-tree to dashboard

> **V6 deferral note:** No bot owns V6 currently. Ad-hoc finance work routes to Hypatia (read-only synthesis) or Gregor (CRM-adjacent expense tracking) with bundled skills only until Marius operates client funds or runs an entity → revival as **Midas** (single-purpose finance bot, credential-isolated per Security Architect's design).

### V7 — Project Management (→ Vesalius)
- `project-manager` `[fork-with-audit]` (awesome) — milestone + dependency mapping
- `scrum-master` `[fork-with-audit]` (awesome) — ceremony facilitation prompts
- `risk-register` `[inspiration-only]` (aggregator) — RAID-log keeper
- `meeting-notetaker` `[inspiration-only]` (aggregator) — transcript → action items
- `roadmap-architect` `[inspiration-only]` (aggregator) — quarterly OKR-to-roadmap
- `taskflow` `[bundled]`, `taskflow-inbox-triage` `[bundled]` — durable flow substrate
- `beads-coordination` `[bundled, workspace]` — shared Beads ledger ops
- `gh-issues` `[bundled]` — already pulls double duty for V1 + V7

### V8 — Creative writing (→ Aldine)
- `novelist` / `fiction-writer` `[fork-with-audit]` (awesome) — chapter drafting w/ continuity bible
- `screenwriter` `[fork-with-audit]` (awesome) — three-act / eight-sequence structure
- `worldbuilder` `[inspiration-only]` (aggregator) — setting bible + faction graph
- `editor-developmental` `[inspiration-only]` (aggregator) — structural critique
- `poet` `[inspiration-only]` (aggregator) — form-constrained verse

### V9 — Personal CRM (→ Gregor)
- `personal-assistant` / `chief-of-staff` `[fork-with-audit]` (awesome) — calendar + commitment tracker
- `relationship-tracker` `[inspiration-only]` (aggregator) — last-contact + topics-graph
- `email-triage` `[inspiration-only]` (aggregator) — inbox-zero loop
- `gift-recommender` `[inspiration-only]` (aggregator) — preference-graph driven
- `gog` `[bundled]` — Google Workspace (Gmail/Cal/Drive/Contacts/Sheets/Docs)
- `himalaya` `[bundled]` — IMAP/SMTP CLI alt
- `apple-notes` / `apple-reminders` / `bear-notes` / `obsidian` / `notion` / `things-mac` / `trello` `[bundled]` — PKM/task surfaces
- `imsg` / `bluebubbles` `[bundled]` — iMessage adapters

> **V9 author opportunity:** `relationship-tracker` w/ Honcho-style memory is a skill-gap — only `personal-assistant` is awesome-listed; rest aggregator-only.

### V10 — Education / learning (→ Hypatia)
- `tutor` / `socratic-tutor` `[fork-with-audit]` (awesome) — concept-Q&A loop
- `study-plan-builder` `[inspiration-only]` (aggregator) — syllabus → schedule
- `flashcard-author` `[inspiration-only]` (aggregator) — Anki-style cloze
- `language-coach` `[inspiration-only]` (aggregator) — interlinear-translation drills

### V11 — Data / SQL / BI (→ Vesalius)
- `sql-pro` / `database-admin` `[fork-with-audit]` (awesome) — query-tuning + schema review
- `data-engineer` `[fork-with-audit]` (awesome) — ETL/ELT pipeline scaffolding
- `analytics-engineer` `[inspiration-only]` (aggregator) — dbt-style modeling
- `dashboard-architect` `[inspiration-only]` (aggregator) — metric-tree + viz spec

### V12 — Design / UI (→ Aldine)
- `ui-ux-designer` `[fork-with-audit]` (awesome) — wireframe + flow critique
- `design-system-curator` `[fork-with-audit]` (awesome) — token + component audit
- `accessibility-reviewer` `[inspiration-only]` (aggregator) — WCAG conformance pass
- `figma-bridge` `[inspiration-only + network-egress-flag]` (aggregator) — spec ↔ design parity

### V13 — Devops / cloud (→ Dismas)
- `cloud-architect` `[fork-with-audit]` (awesome) — AWS/GCP/Azure topology
- `kubernetes-operator` / `k8s-pro` `[fork-with-audit]` (awesome) — manifest + Helm review
- `terraform-pro` `[fork-with-audit + state-file-secret-leak-flag]` (awesome) — module + state-file hygiene; **audit before fork**
- `sre-on-call` `[inspiration-only]` (aggregator) — incident-loop driver

### V14 — Knowledge / PKM (→ Hypatia)
- `pkm-curator` `[inspiration-only]` (aggregator) — Zettelkasten-style atomic notes
- `journaling-coach` `[inspiration-only]` (aggregator) — daily/weekly review prompts
- `obsidian-bridge` `[inspiration-only + filesystem-write-flag]` (aggregator) — vault-aware ops
- `summarizer-archivist` `[inspiration-only]` (aggregator) — long-form → atomic notes

> **V14 author opportunity:** Entire vertical is aggregator-driven; no flagship in awesome-cc-subagents. `pkm-curator` and `obsidian-bridge` are skill-author candidates.

### V15 — Health / habits / lifestyle (→ Gregor)
- `fitness-coach` `[inspiration-only]` (aggregator) — periodized program writer
- `nutrition-planner` `[inspiration-only]` (aggregator) — macro-target meal planner
- `habit-tracker` `[inspiration-only]` (aggregator) — streak + cue-routine-reward log
- `sleep-coach` `[inspiration-only]` (aggregator) — chronotype-tagged advice
- `eightctl` `[bundled]` — Eight Sleep pod control

> **V15 deferral note:** Low-priority vertical until quantified-self rigs land. Skill-author opportunity is low ROI for now.

## Generic `[dangerous-avoid]` patterns

Apply at audit time, not pre-listed by name:
- **Typosquats** — `clade-code-*`, `claud-*`, `claude_code_*` (underscore-substitution), `claude-code-skils` (missing-letter)
- **`child_process.exec` against user input** — same class as the ClawKeeper bug already patched
- **Skills shipping `.env` or `auth-profiles.json`** in default configs
- **`network: any`** or no egress allowlist documented
- **No LICENSE file**, or copy-pasted MIT with original author stripped
- **Abandoned forks** — last commit > 12 months, open issues > 50, no maintainer response
- **`curl | bash`** in install scripts — supply-chain trojan vector
- **Skills referencing `~/.openclaw/`, `SOUL.md`, `MEMORY.md`** — memory-poisoning vectors

> **Note on the carried-forward "5,147 listings / 373 malicious" figure** in project memory: unverified from sandbox and **not used** as a quoted statistic in this catalog. Re-verify before external citation.

## Skill-author opportunities (file as beads)

| Vertical | Gap | Priority |
|----------|-----|----------|
| V9 Personal CRM | `relationship-tracker` w/ Honcho-style memory | Medium |
| V14 PKM | `pkm-curator` (Zettelkasten flagship) | Medium |
| V14 PKM | `obsidian-bridge` (filesystem-aware) | Medium |
| V15 Health | (none — deferred) | Low |
| V5 Security | **`prompt-injection-defender` PUBLISH-BACK** — project's 6-layer defense is more mature than anything in wild | High (community contribution) |

## Cross-references

- `SKILLS-AND-TOOLS.md` — skill mechanics, supply-chain risk model, audit checklist (existing)
- `CONCEPTS-INVENTORY.md` — sub-agent verdict (lean SKIP for current Gregor topology, ADOPT-candidate for agent-pack — relevant here)
- `ATLASFORGE-PATTERNS.md` — chassis identity layer (SOUL/AGENTS/IDENTITY/USER/MEMORY/SECURITY/HEARTBEAT/TOOLS) inherited by every bot in the pack
- `DOCTRINE-AUDIT-AT-USAGE-TIME.md` — the policy this catalog feeds
- `VERTICAL-AGENTS.md` — bot-by-bot skill packs derived from this catalog
- `KNOWN-BUGS.md` — config gotchas every new bot must respect (#6 OAuth compaction, #7 /tmp workspace, #8 strict-schema auto-restore)
