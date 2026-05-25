---
title: "Moritz Kremb Blueprint — Personal-OS architecture applied to Gregor"
doctrine_status: Reference / strategy
created: 2026-05-14
unified: 2026-05-17 (merged the two separate Moritz docs into this one)
created_by: isidore
sources:
  - episode: "Peter Yang × Moritz — Behind the Craft (2026-05-10, 42m)"
    url: https://www.youtube.com/watch?v=ACRd0Ikg_KI
    raw: ~/.claude/PAI/MEMORY/RAW/2026-05/2026-05-14T134736Z-mx-add-youtube-com-watch/transcript.md
    lens: 4-layer architecture ("Claudia" — his Claude Code port)
  - episode: "Greg Eisenberg × Moritz — Startup Ideas Pod (OpenClaw masterclass)"
    url: https://www.youtube.com/watch?v=fd4k16REDOU
    raw: ~/.claude/PAI/MEMORY/RAW/2026-05/2026-05-14T133800Z-manual-startup-ideas-pod-moritz-openclaw-blueprint/payload.md
    lens: 10-step OpenClaw setup walkthrough
bead_epic: openclaw-bot-k0a
---

# Moritz Kremb Blueprint — Personal-OS applied to Gregor

> Two episodes, one guest, one architecture. Moritz built a content+life OS
> on OpenClaw, then ported the *same* 4-layer architecture to Claude Code
> ("Claudia") when he hit reliability + model-access limits. **We stay on
> OpenClaw.** This doc is what we copy from his architecture, what we skip,
> and where Gregor already does it better. Surname is from ASR transcripts
> ("Kram"/"Kremb" both appear) — treated as the same person.

## TL;DR — the few parts worth adopting

Most of Moritz's 10 steps, Gregor already does as well or better (see
[§Where Gregor is ahead](#where-gregor-is-already-ahead)). The genuinely
adopt-worthy gaps, ranked by leverage × low cost:

| # | Adopt | Why it's worth it | Bead | Cost |
|---|-------|-------------------|------|------|
| 1 | **Memory loop** — verify `memorySearch.experimental.sessionMemory`, author a real `HEARTBEAT.md`, add a nightly "dreaming" compression cron | Memory is *the* differentiator and ours is half-wired (heartbeat body is empty). This is the single highest-ROI move. | `0vh` + `o3n.3` | ~1h |
| 2 | **`TOOLS.md` registry** — one workspace file listing every CLI/MCP/API the bot has | The only real *architectural* gap. Tool inventory is currently scattered across `openclaw.json`, plugins, MCP entries — nothing answers "what can I use?" | `o3n.1` | ~30m |
| 3 | **CLI > MCP > API doctrine** — prefer tools in that order when picking SaaS | Free, one-line rule. Append to `CLAUDE.md` Operational Rules. | `o3n.4` | ~15m |
| 4 | **`SOUL.md` split** — personality/voice file separate from `AGENTS.md` behavior config | Closes part of `je6` (sub-agent identity loss); canonicalizes the workspace file shape before any second bot. | `3b7` | ~30m |
| 5 | **GWS CLI** — Google Workspace CLI, Moritz's "most powerful tool" | Unlocks Drive/Calendar/Gmail automation; directly serves G3 (Festanstellung admin). | `o3n.2` | install |

Lower-leverage / situational (real, but not "the few"): Telegram topic
structure (`o4b`), browser access mode (`gwj`), agent-owned accounts
(`2o6`), grocery skill (`o3n.5`), sub-agent gate re-eval (`o3n.6`), V12
content pipeline (`o3n.7`). These are **standalone beads** — de-parented
from the build epic, deferred indefinitely. See [§Bead chain](#bead-chain).

**Adopt nothing else.** See [§What NOT to adopt](#what-not-to-adopt).

## The 4-layer mental model

Moritz's organising frame — platform-agnostic, maps cleanly onto OpenClaw:

| Layer | What it is | OpenClaw equivalent | Gregor status |
|-------|-----------|---------------------|---------------|
| 1 · Folder + Memory | Files read every session start: identity, user, context, memory | `AGENTS.md` + workspace identity files + Ollama memory + daily files | Strong — gap is empty heartbeat + no `SOUL.md` split |
| 2 · Tools | CLIs/MCPs/APIs the agent can call | `openclaw.json` + plugins + MCP entries | **Gap — no single-file registry** |
| 3 · Skills | Reusable instructions for repeated workflows | `~/.openclaw/extensions/*` + workspace skills | Ahead — audit-at-usage-time doctrine |
| 4 · Routines | Scheduled proactive jobs | OpenClaw crons + heartbeat | Strong — 6 active crons |

OpenClaw covers all 4 natively. The only structural hole is **Layer 2
hygiene**; the only loop missing is the **Layer 1 nightly memory
compression**.

## Where Gregor is already ahead

Moritz's 10-step walkthrough vs. Gregor — steps where no action is needed:

- **Troubleshooting** — `GUIDE.md` (15 phases) + `Reference/` deep-dives are a stronger fault-recovery base than Moritz's "load docs into a Claude Project".
- **Model chain** — `openai-codex/gpt-5.4` primary, OpenRouter fallbacks, subagents fail-closed (`I2`). More sophisticated than his: chat (OAuth) and compaction (API key) are correctly split.
- **Skills** — `DOCTRINE-AUDIT-AT-USAGE-TIME.md` (forked skills quarantined until a signed `audit.json`). Moritz just says "security-scan everything".
- **Security** — 6-layer Berman defense plugin across 5 events + 162 tests + 4-layer permission pipeline + invariants `I1`–`I4`. Moritz's step 9 is one paragraph. **This is our publish-back artifact** (bead `2r9`, toward G2).
- **Beyond his scope entirely** — multi-bot topology, config invariants with auto-check, major-version upgrade-trap discipline, Mission Control, compaction routing (OAuth can't compact).

## The real gaps — adopt list

### 1 · Memory loop — `0vh` + `o3n.3`

Moritz: memory only works if it's *saved*. New installs don't auto-create
`memory.md`. His knobs: `compaction.memoryFlush.enabled: true`,
`memorySearch.experimental.sessionMemory: true`, and a heartbeat that logs
a session summary every 30 min. He also runs a **nightly "dreaming" cron**
— reads the day's daily-memory files, writes a compressed version into
long-term memory.

Gregor: `compaction.memoryFlush.enabled: true` ✅. Ollama
`nomic-embed-text:v1.5`, 7/7 indexed. **But** — `sessionMemory` status is
unverified, and `rotating-heartbeat` runs every 30 min against an *empty*
`HEARTBEAT.md` (DISABLED 2026-05-02 precisely because empty = pure
ceremony at ~1500 msgs/mo).

**Action:**
- `0vh` — read-back `~/.openclaw/openclaw.json` to confirm `sessionMemory`; author `HEARTBEAT.md` with Moritz's 3 modules (memory maintenance, todo auto-update, cron health-check); re-enable the cron once the body does real work.
- `o3n.3` — new `memory-dreaming` cron ~02:45: "Read today's daily memory file, compress to 3–5 bullets, append to `workspace/memory/long-term.md`." Cap growth via yearly rollover or a weekly-summary layer (matches the existing PARA cycle).

### 2 · `TOOLS.md` registry — `o3n.1`

Moritz: *"tools.md is super important. Every time I add a new tool I say
add this to your tools.md … that's the most important part actually."*

Gregor has no equivalent — tool inventory is spread across `openclaw.json`,
the bundled-plugins list, `tools.profile`, MCP registrations, CLI install
state. Nothing a human (or the bot) can read to answer "what tools do I
have?"

**Action:** `o3n.1` — create `~/.openclaw/workspace/TOOLS.md`, sections
per category (CLI / MCP / API), each entry with status + path + usage
pointer. Link from `AGENTS.md`. Doubles as the per-bot template for any
future pack member.

### 3 · `SOUL.md` / 4-file workspace identity split — `3b7`

Moritz's workspace identity files: `AGENTS.md` (behavior — most
important), `SOUL.md` (personality / reply voice), `IDENTITY.md`,
`USER.md`. Auto-load every session; he tells the bot to update them on
drift.

Gregor has `AGENTS.md` (with the `## Programs` section) but no documented
`SOUL.md` discipline. Bead `je6` flags sub-agent identity loss as a known
risk for any orchestrator pattern.

**Action:** `3b7` — audit `~/.openclaw/workspace/` for SOUL/IDENTITY/USER
coverage; document the canonical four-file split. With `o3n.1` shipped,
the workspace has the full 5-file shape (AGENTS + SOUL + IDENTITY + USER +
TOOLS).

### 4 · CLI > MCP > API doctrine — `o3n.4`

Moritz: when evaluating any new tool — *"first do they have a CLI? Then
MCP? If not, at least an API? If not, find another tool."*

**Action:** `o3n.4` — append the rule to `CLAUDE.md` Operational Rules
alongside "bun always, never npm". One-line doctrine, zero build cost.

### 5 · GWS CLI install — `o3n.2`

Moritz: Google Workspace CLI is *"right now the most powerful tool for me
… I can access my G drive and do anything with it."* Marius is already on
Google Workspace (standard tier); G3 Festanstellung admin (inbox,
calendar, Drive) benefits directly.

**Action:** `o3n.2` — install GWS CLI on Gregor, register in `TOOLS.md`.
Pro-tier upgrade decision feeds `2o6` (agent-account separation).

### 6 · Telegram groups + topics — `o4b`

Moritz: one Telegram thread becomes chaos. Create groups per domain
(todos, journaling, content); use **topics** for finer separation; set
**group/topic-specific system prompts** so the bot knows the context.

Gregor runs a single thread + direct-DM `daily-report`. No group/topic
structure.

**Action:** `o4b` — design a 3–5 topic structure aligned to TELOS
(admin/config, content/blog, journaling, agency/inbound for G3), each with
a per-topic system prompt captured as a workspace file.

### 7 · Browser access mode — `gwj`

Moritz: OpenClaw reaches the web three ways — (1) WebFetch (public, no
login); (2) **managed browser** (bot-owned Chrome profile, log in once —
enables form-filling / ordering); (3) **Chrome Relay** (extension on your
machine, bot uses your session — natural for a VPS bot, less secure).

Gregor uses none — browser capability is currently unused. This is the
single largest capability Moritz unlocks that Gregor lacks.

**Action:** `gwj` — decide the mode + which bot owns it; document the
three modes. Blocks the grocery skill (`o3n.5`).

### 8 · Agent-owned accounts — `2o6`

Moritz: treat the agent like a new employee — give it its *own* Google
account, X account, mailbox, calendar. Don't merge into yours.

Gregor has his own Telegram bot account ✅ but auth profiles use
`<your-email>` — Marius's identity. Any future Workspace
integration routes through Marius's personal identity → blast radius.

**Action:** `2o6` — design the separation pattern (per-bot? per-domain?)
before a Workspace Pro upgrade or any second bot forces it ad-hoc.

## Content pipeline (V12 — deferred)

Moritz demoed a step-by-step short-form video pipeline. It maps almost 1-1
onto a future content/marketing vertical, but agent-pack bootstraps are
deferred indefinitely — so this is captured, not scheduled.

| Step | Moritz | OpenClaw rewrite |
|------|--------|------------------|
| Idea capture | Telegram + weekly YT scrape + X-DM-to-bot | Telegram (have) + `bird` CLI scrape + X-DM (new) |
| Weekly plan | Skill: idea bank → Mon–Sun schedule | Skill, sources ideas dir |
| Script | Skill drafts notes from past-script library | Mirror; notes-first |
| Refine | Manual + Whisper voice notes → polish skill | Marius edits via Telegram |
| Film | Manual phone teleprompter | Manual — stays human |
| Upload/post | Drive folder skill + Postits CLI (YT/IG/TikTok) | Same; depends on GWS CLI |
| Analytics | Fetch → feed back to weekly plan | Same |

Posting gotchas to encode before any auto-post: warm new TikTok accounts
with manual uploads first; IG may perform better posted via Meta's "Edits"
app than direct API. Tracked as deferred bead `o3n.7`.

> **Content-pipeline note for Marius:** the shape also maps onto
> `blog-creator-page` for long-form. The anti-slop discipline
> (`opinions.yaml` anti-slop-mandate) is the piece *missing* from Moritz's
> pipeline — we already have it. Substrate-first doctrine holds: this is
> distribution, not substrate. Defer until substrate items ship.

## Sub-agent gate

Moritz: most people don't need sub-agents — a main agent + Telegram groups
is enough. Sub-agents earn their place only to **separate distinct
contexts** (one agent per business) or as **bias-free reviewers** (a
drafter shouldn't grade its own draft).

Our 5-bot pack is 5 *separate top-level bots* (own user + systemd +
workspace + memory) — that's context separation, passes his test.
**Sub-agents *within* a bot** are the real gate: `agents.defaults.
subagents.model` is fail-closed (`I2`); any new in-bot sub-agent must pass
the context-separation OR reviewer test — anything else is decomposition
theater. This is the re-evaluation criterion for bead `kcy` / `o3n.6`.

## What NOT to adopt

1. **"Bypass permission mode always active"** — Moritz admits it's "less secure". Our answer is **tier-appropriate defaults** (`k0a.1`: Tier 0 auto-allows within a per-bot allowlist for low-risk personal-OS work; Tier 2 keeps the gate for money/adversary surfaces). Not blanket bypass.
2. **Migrating off OpenClaw** — he migrated for reliability + model access; we've engineered around both (invariants `I1`–`I4`, Codex OAuth primary, OpenRouter fallback, post-restart gate). Migrating would dump real assets — chat-first UX, heartbeat, native crons/sub-agents.
3. **Drive-first storage** — he prefers Drive for phone access; our Telegram-first UX already gives phone access without the cloud-only latency/audit cost. Hybrid is fine.
4. **Editing docs in Cursor / Claude Code extension** — Claude-Code-specific UX, irrelevant here.

> **Watch (`[10:04]`):** Moritz: *"GPT-5.4 is terrible with OpenClaw … not
> as proactive as Opus."* Our `gpt-5.4` setting did land us in compaction
> failure historically. Don't pin sub-agents to a model OpenClaw wasn't
> designed around; re-evaluate when 5.5 ships.

## Bead chain

The 5 good parts are the **build epic `openclaw-bot-k0a`** — "Moritz
blueprint — adopt-list build chain". 8 children: the 5 adopt-list parts
(6 beads) + 2 doctrine beads they feed into (`k0a.1` security tiers,
`k0a.2` GUIDE-bake capstone — both ID-locked to the epic).

```
bd children openclaw-bot-k0a     # the build chain
bd show openclaw-bot-0vh         # start here — highest ROI
```

**Dependency waves** (the chain — start anything in wave 1 now):

| Wave | Beads | Blocked on |
|------|-------|------------|
| 1 — ready now, parallel | `o3n.4` (CLI>MCP>API, ~15m) · `0vh` (memory loop, ~45m) · `3b7` (SOUL audit, ~30m) · `k0a.1` (security tiers, ~1h) | — |
| 2 | `o3n.3` (memory-dreaming cron) · `o3n.1` (TOOLS.md) | `0vh` / `3b7` |
| 3 | `o3n.2` (GWS CLI install) | `o3n.1` |
| 4 — capstone | `k0a.2` (GUIDE Phase 16 + workspace template) | `3b7` + `o3n.1` + `k0a.1` |

Chains: `o3n.4` standalone · `0vh → o3n.3` · `3b7 → o3n.1 → o3n.2` ·
`{3b7, o3n.1, k0a.1} → k0a.2`.

**Not in the build epic** — de-parented to standalone beads, deferred
indefinitely (the old agent-pack sprawl): `gwj` browser mode, `o4b`
Telegram topics, `2o6` agent accounts, `o3n.5` grocery skill, `o3n.6`
sub-agent gate, `o3n.7` V12 pipeline. Agent-pack bootstraps
(`o38`/`8bi`/`o6a`/`cgy`) also deferred indefinitely.

## Cross-references

- Raw transcripts: see `sources:` frontmatter (canonical: `~/.claude/PAI/MEMORY/RAW/2026-05/`).
- Related repo docs: `CLAUDE.md`, `Reference/DEFENSE-SYSTEM.md`, `Reference/DOCTRINE-AUDIT-AT-USAGE-TIME.md`, `Reference/VERTICAL-AGENTS.md`, `Reference/AGENT-TOPOLOGY.md`, `Reference/KNOWN-BUGS.md`.
- TELOS anchors: G1 (PAI), G2 (open-source contribution), G3 (Festanstellung), G6 (commercial PAI).
