# PAI Pipeline — Cross-Agent Communication Architecture

> How Gregor (OpenClaw/Sonnet) and Isidore Cloud (Claude Code/Opus) collaborate on the same VPS through a filesystem-based task pipeline.

## Overview

The PAI pipeline enables two AI agents running as separate Linux users on the same VPS to exchange work asynchronously. Gregor (the always-on Telegram bot) submits complex tasks to Isidore Cloud (the heavy-computation Opus agent) via shared JSON files, and reads results back when complete.

**Design philosophy:** Everything is a file. Every task is auditable. No privilege escalation. No shared processes.

## Architecture

```
┌──────────────────┐         ┌──────────────────────┐
│  Gregor           │         │  Isidore Cloud        │
│  (openclaw user)  │         │  (isidore_cloud user) │
│  OpenClaw/Sonnet  │         │  Claude Code/Opus     │
│  Always-on        │         │  On-demand             │
└────────┬─────────┘         └──────────┬─────────────┘
         │                              │
         │  pai-submit.sh               │  bridge watcher
         │  writes task JSON            │  polls tasks/
         ▼                              ▼
    ┌─────────────────────────────────────────┐
    │  /var/lib/pai-pipeline/                  │
    │  ├── tasks/    ← pending tasks           │
    │  ├── results/  ← completed results       │
    │  └── ack/      ← processed originals     │
    │                                           │
    │  Owned: root:pai  Mode: 2770 (setgid)    │
    └─────────────────────────────────────────┘
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
sudo mkdir -p /var/lib/pai-pipeline/{tasks,results,ack}
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

## Future Enhancements

- **HTTP endpoint (Layer 2+):** Add a `localhost:PORT/task` HTTP endpoint to the bridge for synchronous task submission. Coexists with file-based queue — HTTP writes to the same directory.
- **Sender-side validation:** `--strict` mode in `pai-submit.sh` to verify that `--project` maps to an existing directory before submitting.
- **Result notification:** systemd path unit or cron job that watches `results/` and pushes completed results to Gregor's Telegram interface.
- **Complexity classifier:** Gregor auto-escalates to Isidore based on token estimate, task type, or user request.
- **PRD-driven overnight workflow:** Gregor queues PRD files as tasks before Marius's 5-hour Max subscription window, Isidore processes autonomously.
