# Gregor Crabbox Runbook

Operational runbook. For architecture, plugin-vs-shell fork, provider verdict,
lifecycle controls, and the 15 hardening rules, read
[`CRABBOX-HARDENING.md`](CRABBOX-HARDENING.md) first.

Read when:

- Gregor is asked over Telegram to do project-based coding work;
- a coding task needs install/test/build/browser checks without blocking the live bot process;
- a long agent run smells stale and needs a disposable or fully resynced workdir.

## Mental Model

Telegram stays the only user channel.

```text
Marius on Telegram
  -> Gregor/OpenClaw
  -> shell-capable coding workflow
  -> crabbox CLI
  -> isolated runner or static SSH target
  -> command output and logs
  -> Gregor summary back to Telegram
```

Crabbox is not a chat surface. It is the execution harness Gregor should use
when a project command is long-running, state-sensitive, expensive, or risky to
run directly inside the live bot environment.

## Current Proven Lane

Verified locally on 2026-05-14 from the operator machine:

- `ssh vps` works as `openclaw@213.199.32.18`.
- Crabbox static SSH works against the literal IP when using
  `CRABBOX_SSH_KEY=/home/USER/.ssh/vps`.
- Do not use the SSH alias as the Crabbox static host. Crabbox readiness probes
  the raw host/port and did not reliably honor the `vps` SSH config alias.
- Static SSH must use port `22`, not Crabbox's default `2222`.
- Remote preflight found `git`, `tar`, `node`, `npm`, `corepack`, Docker,
  `sudo`, and `apt`; `pnpm`, `bun`, and `bubblewrap` were missing.

The proven static-SSH command shape is:

```sh
CRABBOX_SSH_KEY=/home/USER/.ssh/vps crabbox run \
  --provider ssh \
  --static-host 213.199.32.18 \
  --static-port 22 \
  --static-user openclaw \
  --static-work-root /tmp/crabbox-openclaw-bot \
  --preflight \
  --no-sync \
  -- echo vps-crabbox-ok
```

This is an operator-local proof lane, not the normal Telegram-to-Gregor lane.
It proves Crabbox can sync and execute against the VPS when driven from this
machine. Do not paste `CRABBOX_SSH_KEY=/home/USER/.ssh/vps` into Gregor; that key
path is local to the operator machine.

For Gregor itself, install the Crabbox CLI on the VPS and configure a real
disposable provider, such as Modal, E2B, Namespace, Hetzner, AWS, or another
Crabbox-backed sandbox. Running arbitrary project code on Gregor's own VPS is
less isolated than running it on a disposable runner.

## Install On Gregor

Install for the `openclaw` user, not root:

```sh
ssh vps 'mkdir -p ~/.local/bin /tmp/crabbox-install'
ssh vps 'cd /tmp/crabbox-install && curl -fsSLO https://github.com/openclaw/crabbox/releases/download/v0.13.0/crabbox_0.13.0_linux_amd64.tar.gz'
ssh vps 'cd /tmp/crabbox-install && tar -xzf crabbox_0.13.0_linux_amd64.tar.gz crabbox && install -m 0755 crabbox ~/.local/bin/crabbox'
ssh vps '~/.local/bin/crabbox --version'
ssh vps '~/.local/bin/crabbox doctor || true'
```

At this stage `doctor` may still report missing provider auth. The install is
usable once local tools are present and a provider-specific check passes.

If Gregor's systemd service does not include `~/.local/bin` on `PATH`, either
call `/home/openclaw/.local/bin/crabbox` explicitly in runbooks or add the path
through the service environment.

### Plugin install (the safety-gate gotcha)

CLI alone gives Gregor shell access to Crabbox. To get the **typed agent
tools** (`crabbox_run`, `crabbox_warmup`, etc.), the OpenClaw plugin must
also be installed.

`@openclaw/crabbox-plugin` is **not on npm** at v0.13.0 (registry returns
404). Install from a local clone of the source repo:

```sh
ssh vps 'rm -rf /tmp/crabbox-plugin-src && git clone --depth=1 --branch=v0.13.0 https://github.com/openclaw/crabbox.git /tmp/crabbox-plugin-src'
ssh vps 'export PATH=$HOME/.npm-global/bin:$PATH && openclaw plugins install /tmp/crabbox-plugin-src'
```

**Expected gotcha** — OpenClaw's install-time pattern matcher will block the
plugin with:

```text
WARNING: Plugin "crabbox" contains dangerous code patterns:
  Shell command execution detected (child_process) (.../index.js:127); ...
Plugin "crabbox" installation blocked: dangerous code patterns detected ...
```

This is a **false positive on documented mechanism**. The plugin's entire
purpose is to shell out to the CLI binary via `child_process.spawn`. The
official `openclaw.plugin.json` ships with this pattern; it is the agent-
facing contract for run/warmup/etc.

The plugin is `@openclaw/` first-party scope, which the repo doctrine
(audit-at-usage-time, `Reference/DOCTRINE-AUDIT-AT-USAGE-TIME.md`) exempts
from the third-party audit gate, same as `@openclaw/discord` (bead `lcf`).

**Bypass with explicit authorization:**

```sh
ssh vps 'export PATH=$HOME/.npm-global/bin:$PATH && openclaw plugins install /tmp/crabbox-plugin-src --dangerously-force-unsafe-install'
```

Then configure the plugin to point at the absolute binary path (because
`~/.local/bin` is NOT on the systemd service `Environment=PATH`):

```sh
ssh vps 'sudo -u openclaw openclaw plugins config crabbox binary=/home/openclaw/.local/bin/crabbox'
ssh vps 'sudo -u openclaw openclaw config validate'
ssh vps 'sudo systemctl restart openclaw && sleep 8 && sudo -u openclaw openclaw plugins list | grep -i crabbox'
```

Acceptance:

- `openclaw plugins list` shows `crabbox` as **enabled**;
- `openclaw config validate` passes;
- gateway is up on `:18789` after restart;
- `src/scripts/config-invariants.sh` I1-I4 still PASS;
- I5 either PASSES with `applicable=true,exit=0` (provider configured) or
  PASSES with `applicable=false,reason="no provider configured"` (provider
  pending — see `src/config/crabbox.yaml.example`).

## First Project Kickoff

Use this only after Gregor has a disposable Crabbox provider configured.

From Telegram, give Gregor a scoped instruction like:

```text
For this repo, use Crabbox for long coding commands. First run crabbox sync-plan
and tell me what would sync. Then run the provider preflight or smallest safe
smoke command. Do not run install, test, or build until you show me the command
you plan to run.
```

Gregor should run:

```sh
crabbox sync-plan

crabbox run --provider <disposable-provider> -- echo preflight-ok
```

If the sync plan includes screenshots, local logs, secrets, build artifacts, or
large generated trees, stop and fix ignores before the first real sync. Crabbox
syncs tracked files plus nonignored untracked files.

## Normal Coding Loop

For a narrow project command:

```sh
crabbox run \
  --provider <disposable-provider> \
  --timing-json \
  -- <command>
```

Examples:

```sh
-- npm test
-- bash -lc 'corepack enable && pnpm install --frozen-lockfile && pnpm test'
-- bash -lc 'npm ci && npm run typecheck && npm test'
-- bash -lc 'python -m pytest -q'
```

Gregor's Telegram report should include:

- command run;
- exit code;
- sync time and whether sync was skipped;
- the relevant failing lines, not full logs;
- the next proposed action.

## Stale Workdir Recovery

Use `--full-resync` once when symptoms suggest stale remote state:

- tests fail only remotely and not locally;
- files appear missing or old after a prior run;
- dependency/build cache state looks inconsistent;
- Crabbox suggests retrying with `--full-resync`.

```sh
crabbox run \
  --provider <disposable-provider> \
  --full-resync \
  --timing-json \
  -- <command>
```

If `--full-resync` does not change the failure, treat the failure as real until
proven otherwise. Do not loop resyncs.

## Disposable Provider Track

Configure this before asking Gregor to use Crabbox from Telegram.

Modal bootstrap shape:

```sh
ssh vps 'python3 -m pip install --user modal'
ssh vps 'python3 -m modal setup'

crabbox run --provider modal \
  --shell 'echo modal-ok && uname -a'
```

Modal is useful for isolated command execution. It is not an SSH lease, so do
not expect `crabbox ssh`, VNC, code-server, or Actions hydration through Modal.

If `python3 -m modal setup` cannot complete from the headless VPS, create a
Modal token locally and install it into Gregor's service environment as
`MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET`. Keep the token out of Telegram and
shell history.

## Operator-Local Static VPS Lane

Use this only when you, from the operator machine, want to exercise Crabbox
against the VPS directly. This is useful for diagnostics, not for normal
Telegram-driven Gregor coding work.

```sh
CRABBOX_SSH_KEY=/home/USER/.ssh/vps crabbox run \
  --provider ssh \
  --static-host 213.199.32.18 \
  --static-port 22 \
  --static-user openclaw \
  --static-work-root /tmp/crabbox-<project-slug> \
  --preflight \
  --no-sync \
  -- echo ok
```

## Telegram Prompts

Use these as copy-paste starts.

### Smoke Test

```text
Run a Crabbox smoke test for this repo. Use sync-plan first, then a no-sync
preflight, then run only `echo ok`. Report the exact commands, whether sync
would include dirty/untracked files, and the exit code.
```

### Test Suite

```text
Use Crabbox to run this repo's normal test suite. Before running it, inspect the
repo scripts and tell me the command you selected. Use one `--full-resync` retry
only if the first remote result smells like stale state.
```

### Long Agent Coding Task

```text
For this coding task, edit normally but run installs/builds/tests through
Crabbox. Keep Telegram updates short: plan, command started, result, next step.
Do not paste full logs unless I ask; summarize the failing lines and preserve
the command needed to reproduce.
```

## Cleanup

For operator-local static VPS runs, remove project temp workdirs when done:

```sh
ssh vps 'rm -rf /tmp/crabbox-<project-slug>'
```

For kept/disposable Crabbox leases:

```sh
crabbox list
crabbox stop <slug-or-cbx-id>
crabbox cleanup --dry-run
```

## Safety Rules

- Do not pass secrets as command-line arguments.
- Do not use broad env forwarding. Allow only named variables needed by the
  command.
- Do not run arbitrary third-party code on Gregor's own VPS when a disposable
  provider is available.
- Do not put the operator machine's SSH key paths in Gregor instructions.
- Do not use `/tmp` as Gregor's OpenClaw workspace. `/tmp` is only acceptable
  for Crabbox disposable sync roots.
- Do not let a stale-state suspicion become an infinite retry loop: normal run,
  one `--full-resync`, then diagnose the actual failure.
