# Crabbox Hardening Doctrine

Companion to [`GREGOR-CRABBOX-RUNBOOK.md`](GREGOR-CRABBOX-RUNBOOK.md). The
runbook is operational ("how do I run this"); this doc is doctrine ("why this
shape, what's load-bearing, where the sharp edges are").

Read when:

- choosing a Crabbox provider for Gregor (or any future bot in the pack);
- designing a long-running coding task or automation that should NOT execute
  in-process inside the bot;
- writing a `.crabboxignore` or `.crabbox.yaml` for a project;
- updating Gregor's plugin set to include Crabbox;
- triaging a stuck or stale Crabbox lease.

Source-of-truth scrape: `github.com/openclaw/crabbox v0.13.0` checked out to
`/tmp/crabbox-src` on 2026-05-14.

---

## 1. Architecture (Two Components, One Mental Model)

Crabbox is two artifacts that ship from one repo:

```text
                ┌────────────────────────────────────────────┐
                │  openclaw.json plugins                     │
                │  └─ @openclaw/crabbox-plugin (Node, npm)   │   <- Plugin
                │     - 5 typed tools: run/warmup/status/    │
                │       list/stop                            │
                │     - registers on Gregor startup          │
                │     - shells out to the CLI binary         │
                └──────────────┬─────────────────────────────┘
                               │ spawn(crabbox, [...])
                               ▼
                ┌────────────────────────────────────────────┐
                │  ~/.local/bin/crabbox (Go binary, GH       │   <- CLI
                │  releases tarball)                         │
                │  - all commands: run, warmup, status,      │
                │    list, stop, sync-plan, doctor, attach,  │
                │    logs, results, events, history, ssh,    │
                │    code, vnc, webvnc, egress, cleanup, ... │
                │  - rsync + ssh + git ls-files              │
                └──────────────┬─────────────────────────────┘
                               │
                               ▼
              ┌────────────────────────────┐
              │  Cloudflare Worker broker  │   ← OPTIONAL.
              │  crabbox.openclaw.ai       │     Org-gated. Direct
              │  (or self-hosted)          │     providers bypass.
              └──────────┬─────────────────┘
                         │
                         ▼
         Provider (cloud or sandbox API or static SSH host)
```

**Two installs on Gregor:**

1. CLI binary (Go) — for the openclaw user, in `~/.local/bin/crabbox`. See
   runbook §Install On Gregor.
2. Plugin — **NOT on npm at v0.13.0** (verified 2026-05-14 against the
   live registry — `@openclaw/crabbox-plugin` returns 404). Install from a
   local clone of the source repo via `openclaw plugins install /tmp/
   crabbox-plugin-src --dangerously-force-unsafe-install`. The force flag
   is required because OpenClaw's install-time pattern matcher flags the
   plugin's documented `child_process.spawn` call as "dangerous." The
   plugin is `@openclaw/` first-party scope, which the audit-at-usage-time
   doctrine exempts (same as `@openclaw/discord` per bead `lcf`). Plugin
   compat requires `pluginApi: ">=2026.4.25"` — Gregor on v2026.5.6 is
   fine.

Without the plugin, Gregor can still drive Crabbox via shell, but he loses
schema validation and the explicit allowlists (`allowRun`, `allowWarmup`,
`allowStop`).

**Service PATH gotcha:** the systemd `Environment=PATH` for the openclaw
service does **NOT** include `/home/openclaw/.local/bin`. Verified
2026-05-14 against live Gregor: `Environment=PATH=/home/openclaw/.npm-
global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`.
So even after installing the CLI to `~/.local/bin/crabbox`, the plugin
(which spawns `crabbox` by name) cannot find it. Fix: set the plugin's
`binary` config to the absolute path `/home/openclaw/.local/bin/crabbox`.

---

## 2. The Plugin Surface Is Intentionally Minimal

`openclaw.plugin.json` advertises **5 tools**: `crabbox_run`, `crabbox_warmup`,
`crabbox_status`, `crabbox_list`, `crabbox_stop`. Each accepts a strict JSON
schema; the plugin enforces it before invoking the binary, so an agent cannot
pass arbitrary shell or non-string env values.

**Flags exposed through `crabbox_run`** (the agent contract):

```text
id, command, provider, env, noSync, syncOnly, forceSyncLarge,
checksum, debug, reclaim, junit, timeoutSeconds
```

**Flags NOT exposed** (shell only, as of v0.13.0):

```text
--keep-on-failure       — leave failed lease alive for SSH inspection
--preflight, --preflight-tools
--script, --script-stdin
--env-from-profile, --allow-env
--fresh-pr, --apply-local-patch
--full-resync, --fresh-sync
--capture-stdout, --capture-stderr
--env-helper
```

**Consequence — the hardening fork:**

| Need | Plugin path | Shell path |
|:-----|:------------|:-----------|
| Schema-validated, allowlisted | ✅ | ❌ |
| Per-tool gating (`allowRun: false`) | ✅ | ❌ |
| Output capped at `maxOutputBytes` | ✅ | ❌ (raw stdout) |
| `--keep-on-failure` for debugging | ❌ | ✅ |
| `--env-from-profile` for live secrets | ❌ | ✅ |
| Long script upload (`--script`) | ❌ | ✅ |
| Fresh-PR replay | ❌ | ✅ |
| Provider: `modal`, `proxmox`, `azure`, `gcp`, `tensorlake` | ❌ | ✅ |
| Provider: `aws`, `hetzner`, `ssh`, `blacksmith`, `namespace`, `semaphore`, `sprites`, `daytona`, `islo`, `e2b` | ✅ | ✅ |

**Default rule:** plugin-typed tools first. Drop to shell only for the
specific feature/provider the plugin doesn't cover.

---

## 3. Provider Choice — Verdict For Gregor

| Provider | Plugin? | Kind | Sandbox cap | Auth | First-time setup | Verdict |
|:---------|:-------:|:-----|:------------|:-----|:-----------------|:--------|
| **e2b** | ✅ | Delegated | 1 hr (Crabbox clamps) | `E2B_API_KEY` env | install client, set key | **Start here.** |
| **modal** | ❌ | Delegated | 24 hr | `MODAL_TOKEN_ID/SECRET` or `python3 -m modal setup` | `pip install modal` + token | Shell only. Use when E2B's 1hr cap bites. |
| **daytona** | ✅ | Delegated | provider-defined | Daytona SDK | Daytona account | Alternative to E2B. |
| **hetzner** | ✅ | Direct VM | session-based | Hetzner API token | Hetzner project + token | When SSH-into-lease is needed (real Linux box). |
| **ssh** (static) | ✅ | Static | host-defined | SSH key | None (use existing host) | Operator-local diagnostics only — proven by Codex. |
| **aws** | ✅ | Direct or Brokered | session-based | IAM | non-trivial | Skip until E2B is exhausted. |

**Recommendation: E2B first.** Reasons:

1. In the plugin allowlist → Gregor calls the typed `crabbox_run`, schema-
   validated, output-capped, owner-scoped.
2. Single `E2B_API_KEY` secret — clean credential surface.
3. 1-hr cap is a *feature* for hardening: it forces the task to be
   structured into bounded slices, not run forever. Long automations should
   never approach a 24-hr cap; if they need 23 hours, they need
   decomposition, not a bigger ceiling.
4. Pure delegated provider (`CoordinatorNever`) → no Cloudflare Worker broker
   needed. Bypasses the GitHub-org gate on `crabbox.openclaw.ai` entirely.

**Modal as second tier**, shell-only, for cases where the 1-hr cap is
demonstrably too short *after* the task has been decomposed correctly.

**Hetzner as third tier**, when the task needs `crabbox ssh`, VNC, code-
server, or GitHub Actions hydration — none of which delegated providers
support.

---

## 4. The Hosted Broker Is Org-Gated

The default broker URL `https://crabbox.openclaw.ai` is restricted to a
configured GitHub org/team. If `crabbox login` completes GitHub OAuth and
then returns an org-membership error, three paths:

1. **Direct-provider mode** — works out of the box for delegated providers
   (e2b, modal, daytona, islo, tensorlake) and for direct cloud providers
   (aws, azure, gcp, hetzner) with the operator's own cloud credentials.
   `provider.spec.Coordinator == CoordinatorNever` means "no broker needed."
2. **Self-host the Worker broker** — `docs/infrastructure.md#self-hosted-
   broker-minimum`. Cloudflare Workers + Durable Objects + provider
   credentials and spend caps owned by Marius.
3. **Get added to the openclaw GitHub org.** Slowest, social.

For Gregor's MVP, **path 1**. If Marius wants brokered AWS/Hetzner with
shared spend caps later, **path 2**.

---

## 5. Lease Lifecycle — Hardening Levers

The CLI heartbeats active leases while a command runs. Heartbeat updates
`lastTouchedAt` and extends idle expiry up to the TTL cap.

**Levers:**

```text
--ttl 60m            hard cap on lease lifetime
--idle-timeout 15m   idle expiry (extended on heartbeat up to TTL)
--keep               do not auto-release at command exit
                     (does NOT skip coordinator idle expiry)
--reclaim            move the local claim to this repo
--keep-on-failure    shell only — leave failed lease alive for inspection
```

**Rules:**

1. **No implicit lifetimes.** Every `crabbox_warmup` from Gregor sets `ttl`
   and `idleTimeout` explicitly. Default Gregor profile: `ttl=60m`,
   `idleTimeout=15m`.
2. **`keep=true` is a smell.** It skips command-exit release but not idle
   expiry — so a "kept" lease still dies. Use it consciously for warmup +
   multi-run flows, not as a "make it persistent" workaround.
3. **`--reclaim` for cross-repo workflows only.** If Gregor switches repos
   mid-task and wants to reuse a warm lease, `--reclaim` moves the claim
   file. Otherwise leases are repo-scoped via the local claim ledger at
   `.git/crabbox/`.
4. **Direct-provider cleanup is conservative.** `crabbox cleanup` refuses to
   sweep when a coordinator is configured (race-safe). For direct providers
   it skips running/keep states and only deletes clearly expired resources.
   Provider resources should carry Crabbox labels/tags so orphan ID works.

---

## 6. Sync Discipline

Crabbox syncs the Git-managed working set, not the whole tree:

- `git ls-files --cached` (tracked) +
- `git ls-files --others --exclude-standard` (nonignored untracked) +
- minus `.crabboxignore`, repo-local `sync.exclude`, and Crabbox defaults
  (`.git`, `.ignored`, `.vite`, `playwright-report`, `test-results`,
  `.crabbox`).

**Mandatory rule: `crabbox sync-plan` before first sync on any repo.**
This repo's recent untracked screenshots (`interceptor-screenshot-*.png`)
would have been synced — Codex flagged this. The fix is `.crabboxignore`
hygiene, not "remember to clean up before each sync."

**Sync controls (env, set in Gregor's service environment):**

```text
CRABBOX_SYNC_CHECKSUM       force checksum-based diff (slower, accurate)
CRABBOX_SYNC_DELETE         delete previously synced files that disappeared
CRABBOX_SYNC_FINGERPRINT    fingerprint reuse for fast skip
CRABBOX_SYNC_FAIL_FILES     150000 default
CRABBOX_SYNC_FAIL_BYTES     21474836480 (20 GiB) default
CRABBOX_SYNC_ALLOW_LARGE    bypass fail threshold (one-shot via --force-sync-large)
CRABBOX_ENV_ALLOW           env allowlist for command env forwarding
```

**Stale workdir recovery rule:** one `--full-resync` retry, then treat the
failure as real. Do not loop resyncs. (Already in the runbook.)

---

## 7. Output Handling — The Truncation Gotcha

The plugin captures stdout and stderr separately, trims each to
`maxOutputBytes` (60 KB default), and reports exit code + a truncation flag
back to the model. **The exit code reflects the wrapper outcome, not the
inner remote command.** On wrapper timeout, the plugin SIGTERMs, waits a
grace period, then SIGKILLs.

**Rules:**

1. **For long-running tasks producing large logs, increase `maxOutputBytes`
   in plugin config or use the shell `crabbox logs <run_id>` path.** Don't
   parse truncated tails for failure diagnosis.
2. **For test suites, use `--junit <paths>`** instead of log scraping. The
   plugin exposes `junit` as a typed param.
3. **Set `timeoutSeconds` per-call when the wrapper default (30 min) is too
   short.** The default catches truly stuck wrappers; long builds should
   override per-call, not globally raise the default.
4. **Treat plugin exit code `124` (timeout/SIGTERM) as inconclusive**, not
   as a real failure of the remote command.

---

## 8. Secrets Discipline

Crabbox enforces:

- **No secrets as command-line flag values.** Period.
- **Env forwarding by allowlist** — `env.allow` in repo config or
  `CRABBOX_ENV_ALLOW`.
- **Diagnostics redact known-secret-looking strings.**

For Gregor, this means:

1. **`E2B_API_KEY`, `MODAL_TOKEN_ID/SECRET`** etc. live in
   `~/.openclaw/.env` or the systemd service environment. NEVER passed as
   plugin tool `env` params (the agent doesn't need to see them).
2. **Repo config sets `env.allow`** with names of vars the build/test
   actually needs (e.g. `NODE_ENV`, `CI`, `GITHUB_TOKEN` for private deps).
   Default-deny everything else.
3. **Egress profiles default closed.** Don't enable mediated egress unless
   a specific QA scenario needs the operator-machine IP path.

---

## 9. Failure Modes That Crabbox Actually Solves

The motivation isn't "Crabbox is cool." It's that several specific Gregor
failure modes go away when long commands run on a disposable lease instead
of in-process:

| Failure mode (without Crabbox) | Crabbox lever |
|:------------------------------|:--------------|
| Bot process restart kills mid-task | Lease survives. `crabbox_status --wait` reconnects. |
| Tool output > model context window | 60 KB plugin cap forces summaries; full logs via `crabbox logs <run_id>` shell. |
| Build/test side effects pollute Gregor's workspace | Lease is disposable. `--full-resync` resets. |
| 49 AGENTS.md scan stalls subagent spawn (bead `44t`) | Long command offloads off-process; subagent stays light. |
| Defense plugin proxy delay on every tool call | Lease commands traverse the defense pipeline once (Gregor's tool invocation), not per-shell-command. |
| Cron payloads collide on shared workspace | Each cron gets its own lease. |
| `/tmp` workspace drift breaks identity | Lease workspace is `/workspace/crabbox`; Gregor's own workspace untouched. |
| Long compaction trims execution context | Run summary survives compaction (it's a structured tool result). |

This is the value proposition. None of these are theoretical — each maps to
a real Gregor incident or a documented Reference/KNOWN-BUGS entry.

---

## 10. Hardening Rules (Doctrine)

When Gregor uses Crabbox for any task:

1. **Plugin tools first, shell second.** Drop to shell only for unsupported
   providers (modal) or shell-only flags (`--keep-on-failure`,
   `--env-from-profile`, `--script`, `--fresh-pr`).
2. **Explicit `ttl` + `idleTimeout` on every warmup.** Default
   `ttl=60m, idleTimeout=15m`. Document overrides per workflow.
3. **`crabbox sync-plan` before first sync on every new repo.** Fix
   `.crabboxignore` before any real sync.
4. **One-shot vs warmup discipline.** Single command → `crabbox_run` (auto
   lease lifecycle). Repeated commands → `crabbox_warmup` + multiple
   `crabbox_run --id <slug>` + explicit `crabbox_stop`.
5. **`--full-resync` ONCE, then diagnose.** Not a debugging loop.
6. **JUnit for tests, structured output for everything else.** `--junit`
   parses XML; use it instead of log scraping.
7. **Output budget per call.** Default 60 KB enforces summary discipline.
   Raise only when there's a specific need.
8. **Env allowlist for secrets.** Never `env: { SECRET: '...' }` as a tool
   param. Set in service environment, allowlist by name in repo config.
9. **Egress profiles default closed.** Per-scenario opt-in only.
10. **Provider pinned per repo.** Set `provider:` in `.crabbox.yaml` so
    Gregor doesn't drift across providers mid-task.
11. **`crabbox doctor` in agent boot sequence.** Cheap, local, no billable
    API calls. Gates whether Gregor accepts Crabbox-routed tasks.
12. **Labels for orphan cleanup.** Provider resources get Crabbox labels
    automatically — verify after first provider configured.
13. **Lease IDs in Telegram summaries.** Every Crabbox-routed task summary
    includes `cbx_...` ID + slug + run_id so the operator can attach
    later. Truncated output gets a tail marker by design — don't hide it.
14. **`crabbox_stop` takes lease ID only.** No flags carrying state.
15. **No warmup-sharing across crons.** A cron that needs Crabbox creates
    a dedicated lease per run. Don't share warm pools between automations.

---

## 11. Open Questions / Falsifiers

- **OpenClaw plugin allowlist for `modal` will land when?** Watch upstream
  `openclaw/crabbox` `openclaw.plugin.json` + `index.js` provider enum. When
  it lands, Modal moves from shell-only to plugin-typed.
- **E2B 1-hour cap vs Gregor's longest legitimate single-command workload.**
  If a real task needs >1hr in one Crabbox call (not decomposable), E2B is
  the wrong provider. Falsifier: first task that genuinely cannot be split.
- **Worker self-host vs delegated providers only.** Current bet: delegated
  providers (E2B/Modal) cover Gregor's needs without self-hosted Worker. If
  Marius starts wanting brokered AWS with spend caps, revisit.
- **Defense pipeline interaction.** Crabbox plugin tools traverse the
  defense pipeline at Gregor's tool-invocation boundary. Lease-side shell
  commands inside `crabbox run` do NOT. Confirm this is the intended trust
  boundary before enabling the plugin for live use.

---

## 12. Cross-References

- [`GREGOR-CRABBOX-RUNBOOK.md`](GREGOR-CRABBOX-RUNBOOK.md) — operational
  steps (install, smoke test, normal coding loop, recovery).
- [`KNOWN-BUGS.md`](KNOWN-BUGS.md) — Gregor-side bugs Crabbox sidesteps
  (e.g. #15 AGENTS.md scan stalls; bead `44t`).
- [`AGENT-TOPOLOGY.md`](AGENT-TOPOLOGY.md) — when other bots in the pack
  (Aldine/Vesalius/Hypatia/Dismas) come online, they each get their own
  Crabbox provider config; no shared leases.
- Upstream: `github.com/openclaw/crabbox` v0.13.0 — `docs/features/openclaw-
  plugin.md`, `docs/features/lifecycle-cleanup.md`,
  `docs/features/sync.md`, `docs/features/egress.md`, `docs/security.md`.
