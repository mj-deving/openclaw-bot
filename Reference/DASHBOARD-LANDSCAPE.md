# Dashboard Landscape — Canonical OpenClaw Operator Surfaces

_Researched 2026-05-06 across 3 parallel agents (comparative maturity matrix, OpenClaw-official endorsement check, builderz-labs deep-read). This doc supersedes the earlier framing where we treated abhi1693's third-party "Mission Control" as the canonical option — it isn't, and the official docs explicitly recommend something else._

## TL;DR — what's actually canonical

| Need | Canonical answer | Status |
|---|---|---|
| **Single-bot dashboard** (chat, config, sessions, devices, debug, cron, presence) | **Bundled Control UI on `:18789/`** — Vite+Lit SPA served by the OpenClaw gateway itself; launched with `openclaw dashboard`; documented at `docs.openclaw.ai/web/control-ui` and `docs.openclaw.ai/web/dashboard`. Official, free, evolves with OpenClaw releases. | **Should be our default** for Gregor today. |
| **Multi-bot fleet console** (boards, RBAC, cost roll-up, approvals across N bots) | **No official endorsement.** The credible third-party is **`builderz-labs/mission-control`** (30 contributors, 6 tagged releases, 577 tests, multi-tenant `/api/super/*` API, hardened compose, MIT). | **Defer adoption** until Aldine bootstrap (`o38`) — the multi-tenant API becomes load-bearing then. |
| **What we currently run** | `abhi1693/openclaw-mission-control` at `https://missioncontrol.mjdeving.com` | **Already deployed, not hurting us, but not worth further investment.** Strategy below. |

## The terminology trap

OpenClaw's official term is **"Control UI"** (sometimes "Gateway dashboard"). It's the canonical single-bot operator surface and ships in the box. There's nothing called "Mission Control" in the OpenClaw codebase or docs.

**"Mission Control"** is a name some third-party projects took for themselves — most notably `abhi1693/openclaw-mission-control` (the one we registered Gregor against on 2026-05-05) and `builderz-labs/mission-control`. Neither is endorsed by OpenClaw.

When someone in our docs says "Mission Control" without qualifier, they almost certainly mean the third-party project. When OpenClaw's own docs say "dashboard" or "Control UI", they mean the bundled one.

**Cross-ref:** `Reference/MISSION-CONTROL.md` and `Reference/MISSION-CONTROL-OPERATIONS.md` are about the abhi1693 project specifically. They remain accurate for the live deployment but should not be read as "this is the canonical OpenClaw dashboard".

## What the bundled Control UI does (canonical single-bot)

From `docs.openclaw.ai/web/control-ui` and `docs.openclaw.ai/web/dashboard`:

- **Chat** with the bot through the same gateway WS the bot uses for its own conversations
- **Config** edit (form + raw JSON, with base-hash guard against concurrent edits — the strict-schema discipline from `Reference/KNOWN-BUGS.md` #8 still applies)
- **Sessions / devices** management — pair, revoke, list (the same surface as `openclaw devices` CLI)
- **Debug panel** with live log tail
- **Cron management** — same surface as `openclaw cron list`
- **Presence tracking**
- **Tailscale Serve integration** for remote access without exposing :18789 to the public internet

**Launch:** `openclaw dashboard` from the bot's user shell (or expose via `gateway.bind = "lan"` + reverse proxy as we already do for abhi1693's MC).

**Auth:** the same gateway token already minted for Gregor (4 operator scopes per `Reference/MISSION-CONTROL.md`). No separate Postgres/Redis/Caddy stack required.

**What it doesn't do:** boards · tasks · approvals queues · agent assignments · multi-bot views · cost dashboards · custom fields. For those, see the multi-bot section below.

## When to graduate to a fleet console (multi-bot)

The 5-bot pack design (`Reference/VERTICAL-AGENTS.md`: Gregor + Aldine + Vesalius + Hypatia + Dismas) means we'll eventually need:

- **Fleet view** — one screen showing all 5 bots' status, recent activity, errors
- **Cross-bot approvals queue** — single inbox for human-in-the-loop decisions
- **Cost roll-up** — token spend across the pack, broken out per bot
- **RBAC** — different humans (us + future collaborators) with different access levels
- **Multi-tenant separation** — Marius's bots vs (future) any other tenant

The bundled Control UI is single-instance and doesn't do these. **`builderz-labs/mission-control` does.** Deep-read findings below.

## The credible third-party: builderz-labs/mission-control

**Repo:** `github.com/builderz-labs/mission-control` · MIT · 4634 stars · 808 forks (queried 2026-05-06).

### Why it's credible (the maturity bars our brief required)

| Requirement | Evidence |
|---|---|
| **Not single-author** | 30 contributors. Top author (`0xNyk`) has 275 commits; long tail of 14, 11, 5, 5, 4, 3, … with active outside PRs (François Martin, Ravi Tharuma, AlessandroMartini, JiwaniZakir, RaviTharuma) |
| **Real release cadence** | 6 tagged releases v1.0.0 → v2.0.1 (latest 2026-03-18). Keep-a-Changelog format with Added/Changed/Fixed/Security/Tests sections per release |
| **Production deploy story** | `install.sh` (--local / --docker) · prebuilt `ghcr.io/builderz-labs/mission-control` multi-arch images · `docker-compose.hardened.yml` (read-only-FS + capability-dropping production overlay) · `docs/deployment.md` · `docs/SECURITY-HARDENING.md` |
| **Threat-model artifacts shipped** | `SECURITY.md`, `SECURITY-HARDENING.md`, `openclaw_hardening_guide.md`, non-root container (`USER nextjs:nodejs (1001)`), `MC_ALLOWED_HOSTS` allowlist, nonce-based CSP without `unsafe-inline` (per v2.0.1 changelog), SSRF + path-traversal hardening on skill-registry |
| **Tested in CI** | 577 tests (282 Vitest unit + 295 Playwright E2E) · 3 CI workflows (`quality-gate.yml`, `docker-publish.yml`, `screenshot-drift.yml`) |
| **Discussions on, active issues** | `has_discussions: true`. Issue #645 (filed 2026-05-05, day-of) tests MC against current OpenClaw gateway spawn — compat is live-tracked. |

### Architecture relevant to our deployment

- **Stack:** Next.js 16 + React 19 + TypeScript 5.7 + SQLite via `better-sqlite3` (WAL mode) + 39 schema migrations
- **Auth:** session cookie (scrypt + 7-day) + `x-api-key` header + Google OAuth with admin approval. RBAC roles `viewer / operator / admin`.
- **Multi-tenant API:** `/api/super/tenants` + `/api/super/provision-jobs` + per-tenant isolated workspace + dedicated gateway path + state directory.
- **OpenClaw transport:** **Same gateway WS protocol** as abhi1693. Env knobs: `OPENCLAW_GATEWAY_HOST`, `OPENCLAW_STATE_DIR`, `OPENCLAW_CONFIG_PATH`. Also supports `NEXT_PUBLIC_GATEWAY_OPTIONAL=true` standalone mode.
- **Built-in extras** abhi1693 doesn't have: Aegis quality-gate review system · Skills Hub (with security scanner) · 4-layer agent eval framework

### Caveats to enforce on adopt

1. **Disable Skills Hub network-install** (it pulls from ClawdHub/skills.sh — same npm-lifecycle attack surface that triggered our `audit-at-usage-time` doctrine, bead `xg5`).
2. **Deploy with `docker-compose.hardened.yml`** (not vanilla `docker-compose.yml`).
3. **Keep `MC_ALLOWED_HOSTS` strict** and behind Cloudflare Tunnel (replaces our deferred LAN-bind hardening).
4. **README still labels v2.0.1 alpha**: *"APIs, schemas, configs may change between releases."* Pin by tag, expect breaking changes.
5. Active OpenClaw spawn bug `#645` to watch (filed today during our research).

### Migration cost from abhi1693 → builderz-labs

**Estimated hours, not days** — same gateway WS protocol family. Concretely:
- Reconfigure `OPENCLAW_GATEWAY_HOST=172.21.0.1` + `OPENCLAW_STATE_DIR=/home/openclaw/.openclaw` + `OPENCLAW_CONFIG_PATH`
- Token rotation through the new admin wizard (or `MC_ALLOWED_HOSTS` config)
- Re-register Gregor's gateway via builderz's UI/API — same `wss://missioncontrol.mjdeving.com:443/openclaw-gateway` chain works (Caddy stays the same)
- Approve new device pairings (TWO again — backend + RQ-equivalent worker per builderz's architecture; verify before assuming)
- Decommission the abhi1693 compose stack on the VPS

**Recommended timing:** when Aldine bootstrap (`o38`) lands and we're already in MC config. Multi-tenant `/api/super/*` becomes load-bearing the moment bot #2 is registered. Premature migration before that is gold-plating.

## What about other third-party options?

The maturity matrix evaluated 5 candidates. Only `builderz-labs` cleared all four bars (not solo, real releases, production-deploy story, security artifacts shipped). The others (queried 2026-05-06):

| Project | ⭐ | Why we didn't pick | Best-fit case |
|---|---|---|---|
| `crshdn/mission-control` | 2,000 | Single-author (crshdn 58 commits, long tail of 1-commit drive-bys); no Discussions; no tests dir | "Autonomous Product Engine" / agents → PRs workflow if that's your primary use case |
| `robsannaa/openclaw-mission-control` | 609 | **Top contributor is `claude` the bot (48 commits, ahead of human at 24)**; no docs/, no tests, dormant 40+ days | Skip. Provenance concerning. |
| `mudrii/openclaw-dashboard` | 432 | Solo author (mudrii 222 commits + bot at 10) but **only Go entrant — single static binary, goreleaser, flake.nix, systemd built-in** | Minimum-blast-radius single-bot ops if you specifically don't want Node. Honorable mention. |
| `stainlu/openclaw-managed-agents` | 391 | Strictly solo (stainlu 181, no other contributors); 19 days old; only 2 releases | Architecture is the most security-aware (egress-proxy + isolated runtime per session, OpenAPI + generated SDKs, AWS/GCP/Hetzner deploy guides) — but you'd be the second user |
| `BlueOrangeDigital/openclaw-helm` | — | Helm-chart fork of abhi1693; doesn't change the underlying single-author dependency | If we ever go to K8s, this becomes the K8s entry point but the upstream issue persists |

The full comparative matrix lives in the research transcript (this session, 2026-05-06).

## Decision tree for our use case

```
Are you doing single-bot operations on Gregor?
├─ YES → Use the bundled Control UI on :18789. It's canonical, free,
│        and what OpenClaw itself recommends. Stop investing in abhi1693.
└─ NO → Are you operating ≥2 bots and need a fleet view?
        ├─ YES, AND that's coming within ~weeks → Migrate to builderz-labs/MC.
        │        Time the migration to Aldine bootstrap (`o38`).
        └─ NOT YET (still single-bot) → Use the bundled Control UI today.
                 Migrate later when bot #2 lands.
```

## What this means for the abhi1693 deployment we already have

**Don't tear it down today.** It's working, paired, and serving Gregor. But:

- **Stop adding features to our abhi1693-specific docs.** No more Polkit add-ons, no more new operator's-guide sections built on it. The bundled Control UI is where new operator effort should land.
- **Move single-bot day-to-day operations to the bundled Control UI** when convenient. Gregor's `:18789` already has the Control UI ready; it just needs to be exposed (Tailscale Serve is the official path; we already expose via Caddy).
- **Decommission the abhi1693 compose stack** as part of the Aldine-bootstrap migration window — when the right time to migrate to builderz-labs happens, the abhi1693 stack goes with it.

## Tracking

- **Maintainer beads (this repo):**
  - `openclaw-bot-2qp` (open, P2) — abhi1693 compose missing shared identity volume; **subsumed by the migration plan above** rather than fixed independently.
  - `openclaw-bot-cwh` (open, P3) — watch upstream issue #266 on abhi1693; will close when we migrate off.
  - `openclaw-bot-ab6` (open, P3) — orphan transcripts hygiene; orthogonal to dashboard choice.
- **Decision still to be made:** explicit go/no-go on the migration to builderz-labs at Aldine-bootstrap time. File a P3 bead `mc-migrate-builderz` blocked on `o38`.

## Sources (research transcript 2026-05-06)

- `docs.openclaw.ai/web/control-ui` — *"a small Vite + Lit single-page app served by the Gateway... communicates directly to the Gateway WebSocket on the same port."*
- `docs.openclaw.ai/web/dashboard` — *"The Gateway dashboard is the browser Control UI served at `/` by default."*
- `github.com/openclaw/openclaw` README — confirms `pnpm ui:build` / `pnpm ui:dev` build pipeline serving from `dist/control-ui`
- `github.com/rohitg00/awesome-openclaw` — Monitoring & Dashboards section opens with `openclaw dashboard` tagged **Built-in**, then 24+ unranked third-party alternatives
- `github.com/builderz-labs/mission-control` — README, CHANGELOG, contributor list, releases, openapi.json (332KB, 101 endpoints)
- `gh repo list openclaw -L 50` — official org has no `mission-control` / `dashboard` / `web-ui` repo; the bundled UI lives inside the main openclaw repo
- HN: only relevant thread is Show HN: Claworc with 1 point and zero comments. No convergence on a third-party canonical.

## Cross-references

- **Architecture of our current deployment (abhi1693):** [MISSION-CONTROL.md](MISSION-CONTROL.md)
- **Operations guide for our current deployment (abhi1693):** [MISSION-CONTROL-OPERATIONS.md](MISSION-CONTROL-OPERATIONS.md)
- **Procedural integration recipe (abhi1693):** [GUIDE.md Appendix M](../GUIDE.md#appendix-m--mission-control-integration-overlay-2026-05-05)
- **5-bot pack design driving the eventual fleet-console need:** [VERTICAL-AGENTS.md](VERTICAL-AGENTS.md)
- **Audit doctrine that constrains Skills Hub adoption on builderz-labs:** [DOCTRINE-AUDIT-AT-USAGE-TIME.md](DOCTRINE-AUDIT-AT-USAGE-TIME.md)
