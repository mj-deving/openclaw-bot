# Doctrine: Audit-at-Usage-Time

**Status:** Adopted 2026-04-30
**Supersedes:** "Bundled-only — zero ClawHub installs" (carried in CLAUDE.md / `SKILLS-AND-TOOLS.md` Priority Rec #1 since 2026-04-04)
**Driving plan:** `Plans/next-session-agent-packs.md`
**Companion:** `SKILL-LANDSCAPE.md` (catalog), `VERTICAL-AGENTS.md` (per-bot packs)

## Context

The original "Bundled-only" doctrine was the right posture when the project ran one bot (Gregor) and the supply-chain attack surface (ClawHavoc, 800+ malicious packages, ~37% of skills with security flaws per Snyk ToxicSkills) outweighed any incremental capability gain.

The agent-pack arsenal (3 new bots + revived Dismas + Gregor) **changes the math.** Five bots covering 14 of 15 verticals require curated skill packs across the full top-100 of awesome-claude-code-subagents. Authoring every skill from scratch is (a) prohibitively expensive in author-time and (b) reinvents work the community has already shipped.

The middle path is **forks-with-audit-at-usage-time**: we curate which skills enter the catalog, but defer per-skill audit until first invocation, with a fail-closed quarantine in between.

## The Doctrine

> **Skills are forked from upstream sources (awesome-claude-code-subagents top-100, clawskills.sh top-100) into our local repos. Forked skills load in `quarantined` state — registered but with `tools.profile: "read-only"`, `network: deny`, `child_process: deny`, and a `before_tool_call` shim that returns "audit-required" — until a signed `audit.json` sidecar exists in the skill directory. The audit runs at first-invocation, not at gateway-start, so cold-start latency is unaffected.**

## Audit Checklist (per skill, before first invocation)

Run before producing the `audit.json` sidecar. Each item maps to a ClawKeeper rule ID.

| # | Check | ClawKeeper rule | Pass criteria |
|---|-------|-----------------|---------------|
| 1 | License | `SC-LIC-*` | LICENSE present, OSI-approved (MIT/Apache-2.0/BSD), original author preserved |
| 2 | Dependencies | `SC-DEP-*` | Lockfile present; `npm audit` / `bun audit` clean; no transitive `child_process` invokers from untrusted deps |
| 3 | Network egress | `SC-NET-*` | Declared destinations only; `fetch()` / `http.request` call-sites enumerated and listed |
| 4 | `child_process` / `exec` / `spawn` | `SC-EXEC-*` | Zero usage, OR usage against hardcoded allowlist with no user-input interpolation (the ClawKeeper bug class) |
| 5 | Secrets access | `SC-CRED-*` | No reads from `~/.openclaw/credentials/`, `~/.openclaw/auth-profiles.json`, `/etc/`, or `process.env` beyond a documented allowlist |
| 6 | Prompt-injection surface | `SC-INJ-*` | Any tool ingesting untrusted external text (web pages, emails, file contents) declared and routed through Layer-1/2 of the defense system |
| 7 | Filesystem writes | `SC-FS-*` | Declared paths only; no writes outside workspace + state-dir |
| 8 | Plugin hook registrations | `SC-HOOK-*` | Enumerated; no `before_tool_call` hooks bypassing the existing defense pipeline |

**Output:** signed `audit.json` sidecar in the skill directory:
```json
{
  "skill_id": "<id>",
  "skill_version": "<git-rev or semver>",
  "audited_at": "<ISO-8601>",
  "auditor": "<user / agent>",
  "checks": {
    "SC-LIC-001": {"pass": true, "evidence": "LICENSE: MIT, author preserved"},
    "SC-DEP-001": {"pass": true, "evidence": "bun audit: 0 high, 0 critical"},
    "SC-EXEC-001": {"pass": true, "evidence": "No child_process usage"},
    "SC-CRED-001": {"pass": true, "evidence": "Reads only from process.env.X (declared)"},
    "SC-INJ-001": {"pass": true, "evidence": "Tool 'fetch_url' routes through L2 sanitization"},
    "SC-NET-001": {"pass": true, "evidence": "Egress: api.example.com only"},
    "SC-FS-001": {"pass": true, "evidence": "Writes only to <workspace>/output/"},
    "SC-HOOK-001": {"pass": true, "evidence": "No before_tool_call hooks registered"}
  },
  "verdict": "approved",
  "signature": "<sha256 of skill content + audit content + auditor key>"
}
```

## Fail-Closed Gate

When a skill is loaded WITHOUT a current audit.json sidecar:

1. **Skill registers** in `agents.subagents` (visible to the agent)
2. **Tool surface** reduced to `read-only` — no exec, no write, no network
3. **`before_tool_call` shim** intercepts every tool invocation and returns `{"error": "audit-required", "skill_id": "<id>", "remediation": "Run: openclaw clawkeeper scan-skill <path>"}`
4. **No silent degradation** — the agent gets an explicit error, the user gets a clear remediation step

**The gate is mandatory.** Disabling it (e.g., setting `audit.gate: "off"`) is forbidden by ClawKeeper and treated as configuration drift requiring revert.

## ClawKeeper Integration

`openclaw clawkeeper scan-skill /path` becomes the canonical audit tool:
- Inputs the 8-check audit checklist above
- Outputs the `audit.json` sidecar in the skill directory
- Fails (non-zero exit) on any check that returns `pass: false`
- `clawkeeper harden` refuses to enable any skill in `agents.subagents` whose `audit.json` is missing OR predates the skill's last `git rev-parse HEAD`

### Pre-deployment dependency

**Bead `32h` (ClawKeeper FP tuning) MUST close before this doctrine becomes a hard gate.** The existing SC-CRED-008 / SC-TRUST-001 false-positive noise (matches node_modules READMEs and recursively-injected constitutions) would block legitimate forks on noise — defeating the doctrine. Sequence:
1. Close `32h` (tune SC-CRED-008 + SC-TRUST-001 false-positive patterns)
2. Add `SC-LIC-* / SC-DEP-* / SC-NET-* / SC-EXEC-* / SC-INJ-* / SC-FS-* / SC-HOOK-*` rules to ClawKeeper v2
3. Implement `scan-skill` v2 to emit `audit.json` sidecar
4. Then enforce the gate via `clawkeeper harden`

## Doctrine Fit

### With single-VPS topology
Audit runs at first-invocation, not at gateway-start. Cold-start latency unaffected. Lazy-loaded subagents are perfect fit for first-invocation gating.

### With bundled-only legacy
Bundled skills are pre-audited at OpenClaw release time — they're a **degenerate case** of the new doctrine (audit happened upstream, audit.json is implicit / ships with the package). Forks-with-audit just extends the same trust model to a wider catalog.

### With AtlasForge chassis
The audit pipeline mirrors AtlasForge's "Failure → Guardrail" loop: every skill that fails an audit becomes a named regression loaded at boot via AGENTS.md → no skill can fail twice for the same reason. (See `ATLASFORGE-PATTERNS.md`.)

## Migration

For each new vertical bot (Aldine, Vesalius, Hypatia, revived Dismas):
1. Fork upstream skills per `VERTICAL-AGENTS.md` skill pack into `~/<bot>/.openclaw/skills/<skill>/`
2. Skills load `quarantined` until first invocation
3. On first invocation, agent surfaces audit-required error → user runs `openclaw clawkeeper scan-skill ~/<bot>/.openclaw/skills/<skill>/`
4. Audit emits signed `audit.json` → skill graduates to full tool surface
5. Subsequent invocations bypass the gate (audit.json signature verified, no rerun needed)

## Why this beats alternatives

| Alternative | Why rejected |
|-------------|--------------|
| Bundled-only (status quo until 2026-04-30) | Doesn't scale to 5-bot pack covering top-100 catalog. Reinvents community work. |
| Forks-with-audit-at-author-time (audit ALL skills before commit) | Author-time audit cost prohibitive for 100+ skills; many skills will never be invoked → wasted audit. |
| Trust-on-first-use without audit | Defeats the entire point of supply-chain risk management. |
| ClawHub install + post-install audit | ClawHub install runs npm lifecycle hooks (preinstall/postinstall) which is the entire ClawHavoc attack vector; **rejected at first principles**. |

## Cross-references

- `SKILLS-AND-TOOLS.md` — original supply-chain risk model + audit checklist (this doctrine refines it)
- `SKILL-LANDSCAPE.md` — the catalog this doctrine gates
- `VERTICAL-AGENTS.md` — per-bot skill packs governed by this doctrine
- `CLAWKEEPER.md` — ClawKeeper plugin reference; `scan-skill` v2 spec lives there
- `KNOWN-BUGS.md` §32h — ClawKeeper FP tuning that gates this doctrine becoming a hard gate
- `DEFENSE-SYSTEM.md` — Layer-1/2 prompt-injection defense referenced in SC-INJ-* checks
