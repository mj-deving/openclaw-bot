# PAI Pipeline — Cross-Agent Communication Architecture

> How Gregor (OpenClaw/Sonnet) and Isidore Cloud (Claude Code/Opus) collaborate on the same VPS through a filesystem-based task pipeline.

## Overview

The PAI pipeline enables two AI agents running as separate Linux users on the same VPS to exchange work asynchronously. Gregor (the always-on Telegram bot) submits complex tasks to Isidore Cloud (the heavy-computation Opus agent) via shared JSON files, and reads results back when complete.

**Design philosophy:** Everything is a file. Every task is auditable. No privilege escalation. No shared processes.

## Architecture

```
┌──────────────────┐                        ┌──────────────────────┐
│  Gregor           │  ── Forward Pipeline ──>│  Isidore Cloud        │
│  (openclaw user)  │                        │  (isidore_cloud user) │
│  OpenClaw/Sonnet  │  <── Reverse Pipeline ──│  Claude Code/Opus     │
│  Always-on        │                        │  On-demand             │
└────────┬─────────┘                        └──────────┬─────────────┘
         │                                             │
         │  pai-submit.sh (forward)                    │  bridge watcher
         │  openclaw agent (reverse)                   │  polls tasks/ + writes reverse-tasks/
         ▼                                             ▼
    ┌──────────────────────────────────────────────────────┐
    │  /var/lib/pai-pipeline/                               │
    │  ├── tasks/          ← Gregor → Isidore (forward)     │
    │  ├── results/        ← Isidore → Gregor (forward)     │
    │  ├── ack/            ← processed forward tasks         │
    │  ├── reverse-tasks/  ← Isidore → Gregor (reverse)     │
    │  ├── reverse-results/← Gregor → Isidore (reverse)     │
    │  ├── reverse-ack/    ← processed reverse tasks         │
    │  ├── workflows/      ← multi-step workflow state       │
    │  └── artifacts/      ← shared build artifacts          │
    │                                                        │
    │  Owned: root:pai  Mode: 2770 (setgid)                  │
    └──────────────────────────────────────────────────────┘
```

### Flow

1. Gregor determines a task needs Opus-grade processing
2. `pai-submit.sh` writes a JSON task file to `tasks/`
3. Isidore Cloud's bridge watcher detects the new file
4. Bridge dispatches: `claude -p "<prompt>" --resume <sessionId>`
5. Bridge writes result JSON to `results/`, moves original to `ack/`
6. Gregor reads result via `pai-result.sh` (or polls with `--wait`)

## Layer 1 — Shared Infrastructure

### Setup

```bash
# Create shared group
sudo groupadd pai
sudo usermod -aG pai openclaw
sudo usermod -aG pai isidore_cloud

# Create pipeline directory with setgid
sudo mkdir -p /var/lib/pai-pipeline/{tasks,results,ack,reverse-tasks,reverse-results,reverse-ack,workflows,artifacts}
sudo chown -R root:pai /var/lib/pai-pipeline
sudo chmod -R 2770 /var/lib/pai-pipeline
```

### Why setgid?

The `2770` mode with setgid bit means:
- New files automatically inherit `pai` group (not the creator's primary group)
- Both users can read/write each other's files through group membership
- No sudo, no su, no privilege escalation needed
- Directory is not world-readable — only `pai` group members can access

### Verification

```bash
# As openclaw user:
touch /var/lib/pai-pipeline/tasks/test.txt
stat -c "%U:%G %a" /var/lib/pai-pipeline/tasks/test.txt
# Expected: openclaw:pai 664

# As isidore_cloud user:
cat /var/lib/pai-pipeline/tasks/test.txt  # Should succeed
```

## Layer 2 — Bridge Watcher (Isidore Cloud Side)

The `isidore-cloud-bridge` service handles both Telegram messages and pipeline tasks. The bridge:

- Polls `/var/lib/pai-pipeline/tasks/` for new `.json` files
- Validates the task schema
- Resolves `cwd` from the `project` field (with fallback to `$HOME` if directory doesn't exist)
- Dispatches via `claude -p "<prompt>" --resume <sessionId>` using Bun.spawn
- Writes result to `/var/lib/pai-pipeline/results/<taskId>.json`
- Moves processed task to `ack/`

### Known behaviors

- **cwd resolution:** If the `project` field maps to a non-existent directory, `Bun.spawn` reports `ENOENT` on the binary path rather than the cwd. The bridge should validate cwd before dispatch.
- **Consumption speed:** The watcher picks up files within seconds. During testing, files were consumed faster than manual inspection could read them.

## Layer 3 — Sender Scripts (Gregor/OpenClaw Side)

Three scripts deployed to `~/scripts/` on the VPS as the `openclaw` user.

### pai-submit.sh — Submit Tasks

```bash
# Simple task
pai-submit.sh "Review backup.sh for edge cases"

# With options
pai-submit.sh "Refactor the auth module" \
  --project openclaw-bot \
  --priority high \
  --timeout 60 \
  --max-turns 20

# Resume an existing session
pai-submit.sh "Continue the refactor" --session abc-123

# Attach file context
pai-submit.sh "Analyze this config" --context-file /path/to/config.json
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--project <name>` | (none) | Project name for cwd resolution |
| `--priority <level>` | `normal` | `high`, `normal`, or `low` |
| `--mode <mode>` | `async` | `async` (fire-and-forget) or `sync` (future HTTP) |
| `--session <id>` | (none) | Resume an existing Claude session |
| `--timeout <min>` | `30` | Max execution time in minutes |
| `--max-turns <n>` | `10` | Max agent turns |
| `--context-file <path>` | (none) | Attach file content as context |

### pai-result.sh — Read Results

```bash
# List all pending results
pai-result.sh

# Read specific result
pai-result.sh 20260226-172309-32b045fe

# Read latest result
pai-result.sh --latest

# Wait for a result (polls every 5s, 10min timeout)
pai-result.sh --wait 20260226-172309-32b045fe

# Read and acknowledge (move to ack/)
pai-result.sh 20260226-172309-32b045fe --ack
```

### pai-status.sh — Pipeline Dashboard

```bash
# Human-readable overview
pai-status.sh

# Machine-readable JSON (for Gregor's programmatic use)
pai-status.sh --json
```

Example output:
```
=== PAI Pipeline Status ===

  Tasks pending:    0
  Results ready:    2
  Acknowledged:     5

--- Results Ready ---
  [completed] 20260226-183045-abc12345  Refactored backup.sh with error handling
  [error] 20260226-172250-a032e7ce      (no summary)

Commands:
  pai-submit.sh <prompt>       Submit a task to Isidore Cloud
  pai-result.sh <task-id>      Read a specific result
  pai-result.sh --latest       Read the most recent result
```

## Schemas

### Task File (Gregor → Isidore Cloud)

Written to `/var/lib/pai-pipeline/tasks/<id>.json`:

```json
{
  "id": "20260226-183045-73485264",
  "from": "gregor",
  "to": "isidore-cloud",
  "timestamp": "2026-02-26T18:30:45Z",
  "type": "task",
  "priority": "normal",
  "mode": "async",
  "project": "openclaw-bot",
  "session_id": null,
  "prompt": "Review backup.sh for edge cases",
  "context": {
    "file": "/path/to/relevant/file",
    "file_content": "..."
  },
  "constraints": {
    "max_turns": 10,
    "timeout_minutes": 30
  }
}
```

### Result File (Isidore Cloud → Gregor)

Written to `/var/lib/pai-pipeline/results/<taskId>.json`:

```json
{
  "id": "9e054420-c950-457a-837c-fb1a8f0c5204",
  "taskId": "20260226-183045-73485264",
  "from": "isidore_cloud",
  "to": "gregor",
  "timestamp": "2026-02-26T18:42:12Z",
  "status": "completed",
  "result": "Refactored backup.sh: added error handling for...",
  "usage": {
    "input_tokens": 12400,
    "output_tokens": 3200
  },
  "session_id": "abc-123-def",
  "error": null
}
```

**Field notes:**
- `id` in results is the bridge's internal UUID; `taskId` references the original task
- `status`: `completed`, `error`, or `in_progress`
- `result` field contains the summary (scripts also check `summary` as fallback)
- `usage` may vary in structure depending on bridge implementation
- `session_id` enables resuming the same Claude session for follow-up work

## Security Model

### What's enforced

- **User isolation:** `openclaw` and `isidore_cloud` are separate Linux users with separate home directories, separate processes, separate credentials
- **Group-only access:** Pipeline directory is `pai` group only (mode `2770`). No world-readable files
- **No privilege escalation:** No sudo, no su, no setuid. Scripts operate purely within group permissions
- **File permissions:** Task files are `0660` (owner + group read/write). Setgid ensures group inheritance
- **Audit trail:** Every task and result is a JSON file on disk. The `ack/` directory preserves processed tasks for forensic review

### What's NOT enforced (by design)

- **No authentication on task submission.** Any process running as `openclaw` or `isidore_cloud` can write to the pipeline. This is intentional — the Linux user model IS the authentication layer.
- **No encryption at rest.** Task files contain prompts in plaintext. The pipeline directory should be on an encrypted filesystem if prompt confidentiality matters.
- **No rate limiting.** The bridge processes tasks as fast as they arrive. Gregor could flood the pipeline. Rate limiting belongs in the sender logic, not the shared directory.

### Threat model considerations

| Threat | Mitigation | Residual Risk |
|--------|-----------|---------------|
| Gregor submits malicious prompts | Isidore Cloud has its own system prompt and tool restrictions | Low — same as any user input |
| Task file injection from other users | Directory is `pai` group only, not world-writable | None unless a `pai` group member is compromised |
| Pipeline used for data exfiltration | All files are local-only, no network exposure | Same as any local file — depends on VPS security |
| Denial of service via task flooding | No mitigation currently | Low priority — both agents are under our control |

## Differences from Internal Pipeline

This is a **different pipeline** from OpenClaw's built-in `~/.openclaw/pipeline/` system:

| Aspect | Internal Pipeline | PAI Pipeline |
|--------|------------------|-------------|
| Location | `~/.openclaw/pipeline/` | `/var/lib/pai-pipeline/` |
| Users | `openclaw` only (bot ↔ local assistant) | `openclaw` ↔ `isidore_cloud` (cross-user) |
| Scripts | `src/pipeline/send.sh` (runs via SSH) | `src/pai-pipeline/pai-submit.sh` (runs on VPS) |
| Purpose | Human → bot messaging | Agent → agent task delegation |
| Consumer | OpenClaw's pipeline-check cron job | Isidore Cloud's bridge watcher |

Both pipelines coexist. They serve different purposes and don't interact.

## Layer 4 — Result Notification

When Isidore Cloud writes a result to `results/`, a long-running inotify watcher detects the new file and triggers a notification script. The script reads the result, formats a message, and drops it into Gregor's internal pipeline inbox for processing on the next `pipeline-check` cron cycle.

```
Result appears in results/
        │
        ▼
  pai-result-watcher.py    Python inotify watcher (systemd user service)
  (IN_CREATE event)        detects new file, debounces 2s
        │
        ▼
  pai-result-notify.sh     reads un-notified results
        │                  writes notification to ~/.openclaw/pipeline/inbox/
        │                  creates .notified-<taskId> marker
        ▼
  pipeline-check cron      Gregor processes notification on next cycle
```

### Components

| File | Location | Purpose |
|------|----------|---------|
| `pai-result-watcher.py` | `~/scripts/` (VPS) | inotify watcher: detects new result files |
| `pai-result-notify.sh` | `~/scripts/` (VPS) | Notification script: reads results, writes inbox messages |
| `pai-notify.service` | `~/.config/systemd/user/` | systemd user service (Type=simple, Restart=on-failure) |

### Why inotify watcher instead of systemd path unit?

systemd user-level path units (`PathChanged=`) cannot watch directories under `/var/lib/` — the user manager's process doesn't inherit supplementary groups added after it started, and user units can't call `setgroups()`. A Python inotify watcher using ctypes works reliably because it runs as a child of the user manager with the correct group membership (after the user manager is restarted to pick up the `pai` group).

### Marker files

After notifying about a result, the script creates a hidden marker file alongside it:

```
results/abc123.json           ← the result (untouched)
results/.notified-abc123      ← marker (empty, prevents re-notification)
```

Markers are pruned automatically — files older than 7 days are deleted on every notification pass. Manual cleanup: `pai-result-notify.sh --cleanup`.

### Notification format

The notification written to Gregor's inbox matches the internal pipeline schema (`src/pipeline/send.sh`):

```json
{
  "id": "20260226-184500-a1b2c3d4",
  "from": "pai-pipeline",
  "to": "bot",
  "timestamp": "2026-02-26T18:45:00Z",
  "type": "notification",
  "subject": "PAI Result Ready: 20260226-183045-abc12345",
  "body": "Task ID: ...\nStatus: completed\n...\n--- Summary ---\n...",
  "priority": "normal",
  "replyTo": null
}
```

Error results (`status: "error"`) get `priority: "high"` and subject prefix `PAI Result FAILED`.

### Latency

| Segment | Latency |
|---------|---------|
| Result appears → notification in inbox | ~100-500ms (systemd inotify + script) |
| Notification in inbox → Gregor reads it | Up to 30 min (pipeline-check cron interval) |

To reduce end-to-end latency, increase the pipeline-check cron frequency:
```bash
openclaw cron edit pipeline-check --cron "*/5 14-21 * * *"  # 5-min checks
```

### Troubleshooting

```bash
# Check watcher service status
systemctl --user status pai-notify.service

# Check service logs
journalctl --user -u pai-notify --since "1 hour ago"

# Restart watcher
systemctl --user restart pai-notify.service

# Dry run (no writes)
~/scripts/pai-result-notify.sh --dry-run

# View notification log
tail -20 ~/.openclaw/logs/pai-notify.log

# Clean up old markers
~/scripts/pai-result-notify.sh --cleanup
```

## Layer 5 — Auto-Escalation (Two-Stage Classification)

Gregor's `pipeline-check` cron job evaluates incoming messages for complexity and automatically escalates complex tasks to Isidore Cloud. This uses a **two-stage pattern**: AI classifies, deterministic scripts execute.

```
Message arrives in ~/.openclaw/pipeline/inbox/
        │
        ▼
  pipeline-check cron           Haiku evaluates complexity
  (every N min, Berlin TZ)      using rules from AGENTS.md
        │
   ┌────┴────┐
   │         │
 SIMPLE    COMPLEX
   │         │
   ▼         ▼
 Handle    Copy to ~/.openclaw/pipeline/escalate/
 locally   Move original to ack/
   │         │
   ▼         ▼
  Done     pai-escalation.path      systemd path unit detects new file
              │
              ▼
           pai-escalation.service   oneshot: runs pai-escalation-submit.sh
              │
              ▼
           pai-escalation-submit.sh extracts body/priority/project from JSON
              │                     calls pai-submit.sh
              ▼
           Task appears in /var/lib/pai-pipeline/tasks/
```

### Why two stages?

Haiku in OpenClaw cron sessions cannot reliably execute shell commands — it "role-plays" running them and fabricates plausible output (e.g., reporting "permission denied" for commands that would succeed). The two-stage pattern separates classification (AI is good at this) from execution (scripts are reliable at this).

### Components

| File | Location | Purpose |
|------|----------|---------|
| `pai-escalation.path` | `~/.config/systemd/user/` | Watches `~/.openclaw/pipeline/escalate/` for new files |
| `pai-escalation.service` | `~/.config/systemd/user/` | Oneshot: triggered by path unit, runs submit script |
| `pai-escalation-submit.sh` | `~/scripts/` | Reads escalated JSON, extracts fields, calls `pai-submit.sh` |

### Why systemd path unit works here

Unlike `/var/lib/`, the `~/.openclaw/pipeline/escalate/` directory is inside the user's home — systemd user-level path units CAN watch home directories. This avoids the Python inotify workaround needed for `/var/lib/pai-pipeline/`.

### Cron prompt

The pipeline-check cron classifies messages using rules from `~/.openclaw/workspace/AGENTS.md`:

```
Check ~/.openclaw/pipeline/inbox/ for pending messages. For each message:

1. EVALUATE COMPLEXITY using the auto-escalation rules in AGENTS.md
   (section: PAI Pipeline). Messages involving security review, architecture
   decisions, multi-file refactoring, deep analysis, complex debugging, or
   anything beyond Sonnet depth are COMPLEX.

2. IF COMPLEX: COPY the file to ~/.openclaw/pipeline/escalate/ (same filename).
   Then move the original to ~/.openclaw/pipeline/ack/. A separate watcher
   will handle the actual PAI submission. Do NOT run pai-submit.sh yourself.

3. IF SIMPLE: Handle locally (answer, summarize, or acknowledge). Move
   processed message to ~/.openclaw/pipeline/ack/.

Always move every processed message to ack/ regardless of path taken.
```

### Troubleshooting

```bash
# Check escalation path unit
systemctl --user status pai-escalation.path

# Check escalation service (shows last trigger)
systemctl --user status pai-escalation.service

# View escalation log
tail -20 ~/.openclaw/logs/pai-escalation.log

# Manual test: place a file in escalate/
cp test.json ~/.openclaw/pipeline/escalate/
```

## Layer 6 — Reverse Pipeline (Isidore Cloud → Gregor)

The reverse pipeline enables Isidore Cloud to delegate tasks back to Gregor. This completes the bidirectional communication loop — Gregor can escalate to Isidore (forward), and Isidore can delegate back to Gregor (reverse).

```
Isidore Cloud writes task to reverse-tasks/
        │
        ▼
  pai-reverse-watcher.py     Python inotify watcher (systemd user service)
  (IN_CREATE event)          detects new file, debounces 2s
        │
        ▼
  pai-reverse-handler.sh     reads task JSON, extracts prompt
        │                    calls: openclaw agent --session-id reverse-<taskId>
        │                           --message "$prompt" --json
        ▼
  Result written to reverse-results/<taskId>.json
  Original moved to reverse-ack/<taskId>.json
        │
        ▼
  Isidore Cloud's bridge consumes result from reverse-results/
```

### Components

| File | Location | Purpose |
|------|----------|---------|
| `pai-reverse-watcher.py` | `~/scripts/` (VPS) | inotify watcher for `reverse-tasks/` |
| `pai-reverse-handler.sh` | `~/scripts/` (VPS) | Processes tasks via `openclaw agent` gateway CLI |
| `pai-reverse.service` | `~/.config/systemd/user/` | systemd user service (Type=simple, Restart=on-failure) |

### Why inotify (not systemd path unit)?

Same reason as Layer 4: `/var/lib/pai-pipeline/reverse-tasks/` is outside the user's home directory. Systemd user-level path units cannot watch it. Python ctypes inotify works.

### Reverse-Task Schema (Isidore Cloud → Gregor)

Written to `/var/lib/pai-pipeline/reverse-tasks/<id>.json`:

```json
{
  "id": "a7593ac4-8899-40bc-9d81-c474c247d6c3",
  "from": "isidore_cloud",
  "to": "gregor",
  "timestamp": "2026-02-27T08:32:43.757Z",
  "type": "delegate",
  "priority": "normal",
  "prompt": "Verify that all TypeScript files have correct headers...",
  "context": {
    "workflow_id": "2ada7b66-...",
    "step_id": "step-004"
  }
}
```

### Reverse-Result Schema (Gregor → Isidore Cloud)

Written to `/var/lib/pai-pipeline/reverse-results/<taskId>.json`:

```json
{
  "taskId": "a7593ac4-8899-40bc-9d81-c474c247d6c3",
  "status": "completed",
  "summary": "All 14 files have correct headers. tsc --noEmit passed.",
  "usage": { "input_tokens": 12400, "output_tokens": 800 },
  "session_id": "reverse-a7593ac4-...",
  "timestamp": "2026-02-27T08:35:12Z",
  "context": { "workflow_id": "2ada7b66-...", "step_id": "step-004" }
}
```

### How `openclaw agent` works

The handler uses `openclaw agent --session-id <id> --message <prompt> --json` to submit the task to Gregor's gateway for processing. Each reverse-task gets an isolated session (prefixed `reverse-`) to prevent cross-contamination.

This is the Gregor-side equivalent of `claude -p` on Isidore Cloud's side — programmatic one-shot agent execution through the gateway.

### Security notes

- Reverse-tasks come from `isidore_cloud` (trusted). Gregor processes them through its normal security stack (tools.profile, deny list, exec.security).
- Gregor cannot access `isidore_cloud`'s home directory — tasks asking to read/write `/home/isidore_cloud/...` will fail. This is correct behavior (Linux user isolation).
- The handler script does all file I/O deterministically (bash + python3). `openclaw agent` only processes the prompt text — no LLM-driven shell execution.

### Troubleshooting

```bash
# Check watcher service
systemctl --user status pai-reverse.service

# Check service logs
journalctl --user -u pai-reverse --since "1 hour ago"

# Restart watcher
systemctl --user restart pai-reverse.service

# Dry run handler (no execution)
~/scripts/pai-reverse-handler.sh --dry-run

# View handler log
tail -20 ~/.openclaw/logs/pai-reverse.log
```

## Future Enhancements

- **HTTP endpoint (Layer 2+):** Add a `localhost:PORT/task` HTTP endpoint to the bridge for synchronous task submission. Coexists with file-based queue — HTTP writes to the same directory.
- **Sender-side validation:** `--strict` mode in `pai-submit.sh` to verify that `--project` maps to an existing directory before submitting.
- ~~**Complexity classifier:**~~ **Implemented (Layer 5).** Two-stage auto-escalation: Haiku classifies → deterministic script submits. Rules in `~/.openclaw/workspace/AGENTS.md` under `## Partner & Delegation`.
- ~~**Reverse pipeline:**~~ **Implemented (Layer 6).** Isidore Cloud can delegate tasks back to Gregor via `reverse-tasks/`. inotify watcher + `openclaw agent` gateway CLI.
- **PRD-driven overnight workflow:** Gregor queues PRD files as tasks before Marius's 5-hour Max subscription window, Isidore processes autonomously.
