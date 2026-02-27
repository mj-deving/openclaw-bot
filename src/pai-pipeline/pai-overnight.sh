#!/usr/bin/env bash
# pai-overnight: Queue-based overnight PRD execution coordinator
# Runs ON VPS as openclaw user — manages sequential PRD processing
#
# Leverages existing pipeline infrastructure (pai-submit.sh, results watcher)
# to process a queue of PRD files overnight while Marius sleeps.
#
# Subcommands:
#   init [opts]   Build queue from staging/, submit first task
#   advance       Cron-called: check current task, submit next if done
#   status        Show queue progress
#   report        Generate/display morning report
#   cancel        Stop processing, mark remaining as cancelled
#   resume        Resubmit current failed/stuck item
#
# Usage:
#   pai-overnight.sh init --project openclaw-bot --timeout 120 --max-turns 50
#   pai-overnight.sh advance               (called by cron every 5 min)
#   pai-overnight.sh status [--json]
#   pai-overnight.sh report [--json]
#   pai-overnight.sh cancel
#   pai-overnight.sh resume
#
# Crontab entry:
#   */5 * * * * /home/openclaw/scripts/pai-overnight.sh advance >> ~/.openclaw/logs/pai-overnight.log 2>&1

set -euo pipefail

PIPELINE_DIR="/var/lib/pai-pipeline"
OVERNIGHT_DIR="${PIPELINE_DIR}/overnight"
STAGING_DIR="${OVERNIGHT_DIR}/staging"
ARCHIVE_DIR="${OVERNIGHT_DIR}/archive"
QUEUE_FILE="${OVERNIGHT_DIR}/queue.json"
RESULTS_DIR="${PIPELINE_DIR}/results"
INBOX_DIR="${HOME}/.openclaw/pipeline/inbox"
LOG_DIR="${HOME}/.openclaw/logs"
LOG_FILE="${LOG_DIR}/pai-overnight.log"
LOCK_FILE="/tmp/pai-overnight-advance.lock"
PAI_SUBMIT="${HOME}/scripts/pai-submit.sh"
MAX_TASK_SECONDS=18000  # 5 hours (Max window)

export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/scripts"

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Iseconds): $1" >> "$LOG_FILE"
}

die() {
    echo "Error: $1" >&2
    log "ERROR: $1"
    exit 1
}

# --- Argument parsing ---
SUBCMD="${1:-help}"
shift || true

PROJECT=""
TIMEOUT_MINUTES=120
MAX_TURNS=50
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)      PROJECT="$2"; shift 2 ;;
        --timeout)      TIMEOUT_MINUTES="$2"; shift 2 ;;
        --max-turns)    MAX_TURNS="$2"; shift 2 ;;
        --json)         JSON_OUTPUT=true; shift ;;
        --help|-h)
            echo "Usage: pai-overnight.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  init       Build queue from staging/, submit first task"
            echo "  advance    Check current task, submit next if done (cron)"
            echo "  status     Show queue progress"
            echo "  report     Generate/display morning report"
            echo "  cancel     Stop processing, mark remaining cancelled"
            echo "  resume     Resubmit current failed/stuck item"
            echo ""
            echo "Options (init):"
            echo "  --project <name>     Project name (default: openclaw-bot)"
            echo "  --timeout <minutes>  Per-task timeout (default: 120)"
            echo "  --max-turns <n>      Per-task max turns (default: 50)"
            echo ""
            echo "Options (status/report):"
            echo "  --json               Output as JSON"
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# ============================================================
# INIT: Build queue from staging PRD files, submit first task
# ============================================================
cmd_init() {
    mkdir -p "$STAGING_DIR" "$ARCHIVE_DIR"

    # Guard: reject if queue is already running
    if [[ -f "$QUEUE_FILE" ]]; then
        local current_status
        current_status=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    q = json.load(f)
print(q.get('status', 'unknown'))
" "$QUEUE_FILE" 2>/dev/null) || current_status="unknown"

        if [[ "$current_status" == "initialized" || "$current_status" == "running" ]]; then
            die "Queue already active (status: $current_status). Use 'cancel' first or wait for completion."
        fi
    fi

    # Collect PRD files from staging
    shopt -s nullglob
    local prd_files=("$STAGING_DIR"/*.md)
    if [[ ${#prd_files[@]} -eq 0 ]]; then
        die "No .md files in staging directory: $STAGING_DIR"
    fi

    local effective_project="${PROJECT:-openclaw-bot}"
    log "INIT: ${#prd_files[@]} PRDs, project=$effective_project, timeout=${TIMEOUT_MINUTES}m, max_turns=$MAX_TURNS"

    # Build queue.json and submit first task using python3
    python3 - "$QUEUE_FILE" "$STAGING_DIR" "$effective_project" \
        "$TIMEOUT_MINUTES" "$MAX_TURNS" "$PAI_SUBMIT" "${prd_files[@]}" << 'PYEOF'
import json, sys, os, subprocess, hashlib
from datetime import datetime, timezone

queue_file = sys.argv[1]
staging_dir = sys.argv[2]
project = sys.argv[3]
timeout_minutes = int(sys.argv[4])
max_turns = int(sys.argv[5])
pai_submit = sys.argv[6]
prd_paths = sys.argv[7:]

now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
date_slug = now.strftime("%Y%m%d-%H%M%S")
rand_suffix = hashlib.sha256(os.urandom(8)).hexdigest()[:8]
queue_id = f"overnight-{date_slug}-{rand_suffix}"

# PRD execution prompt template
PROMPT_TEMPLATE = """You are executing a PRD for the {project} project.
This is an autonomous overnight run — no human is available.

INSTRUCTIONS:
1. Read the PRD carefully and understand all requirements
2. Implement each item systematically, following existing code patterns
3. Create descriptive git commits after each logical unit of work
4. If you encounter ambiguity, make the reasonable default choice and document it
5. If you hit a blocker, document it clearly and move on to the next item

--- PRD: {title} ---
{content}
--- End PRD ---

DELIVERABLES: Report what was implemented, what was skipped (and why),
decisions Marius should review, and suggested follow-up items."""

# Build items from PRD files (sorted by filename for predictable order)
items = []
for i, prd_path in enumerate(sorted(prd_paths)):
    fname = os.path.basename(prd_path)
    # Extract title from first markdown heading or use filename
    title = fname
    try:
        with open(prd_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("# "):
                    title = line[2:].strip()
                    break
    except IOError:
        pass

    items.append({
        "index": i,
        "prd_file": fname,
        "prd_title": title,
        "task_id": None,
        "status": "pending",
        "submitted_at": None,
        "completed_at": None,
        "result_status": None,
        "session_id": None,
        "error": None,
    })

queue = {
    "id": queue_id,
    "created_at": timestamp,
    "status": "initialized",
    "project": project,
    "defaults": {
        "max_turns": max_turns,
        "timeout_minutes": timeout_minutes,
        "priority": "normal",
    },
    "items": items,
    "current_index": 0,
    "completed_count": 0,
    "failed_count": 0,
    "report_generated": False,
    "updated_at": timestamp,
}

# Submit first task
first = items[0]
prd_path = os.path.join(staging_dir, first["prd_file"])
with open(prd_path) as f:
    prd_content = f.read()

prompt = PROMPT_TEMPLATE.format(
    project=project,
    title=first["prd_title"],
    content=prd_content,
)

try:
    result = subprocess.run(
        [pai_submit, prompt,
         "--project", project,
         "--priority", "normal",
         "--timeout", str(timeout_minutes),
         "--max-turns", str(max_turns)],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        print(f"WARNING: pai-submit.sh failed: {result.stderr.strip()}", file=sys.stderr)
        first["status"] = "failed"
        first["error"] = f"submit failed: {result.stderr.strip()}"
        queue["failed_count"] = 1
    else:
        # Parse task ID from output: "Task submitted: <id>"
        for line in result.stdout.strip().split("\n"):
            if line.startswith("Task submitted: "):
                first["task_id"] = line.split(": ", 1)[1].strip()
                break
        first["status"] = "running"
        first["submitted_at"] = timestamp
        queue["status"] = "running"
        print(result.stdout.strip())
except subprocess.TimeoutExpired:
    first["status"] = "failed"
    first["error"] = "submit timed out"
    queue["failed_count"] = 1
    print("WARNING: pai-submit.sh timed out", file=sys.stderr)

# Write queue file
with open(queue_file, "w") as f:
    json.dump(queue, f, indent=2)
os.chmod(queue_file, 0o660)

print(f"\nQueue created: {queue_id}")
print(f"Items: {len(items)}")
print(f"Project: {project}")
print(f"Timeout: {timeout_minutes}m per task, Max turns: {max_turns}")
if first["task_id"]:
    print(f"First task submitted: {first['task_id']}")
PYEOF
}

# ============================================================
# ADVANCE: Check current task, submit next if done (cron)
# ============================================================
cmd_advance() {
    # flock to prevent overlapping cron invocations
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "ADVANCE: skipped (another instance running)"
        exit 0
    fi

    if [[ ! -f "$QUEUE_FILE" ]]; then
        exit 0  # No queue — nothing to do
    fi

    python3 - "$QUEUE_FILE" "$RESULTS_DIR" "$PAI_SUBMIT" "$STAGING_DIR" \
        "$INBOX_DIR" "$ARCHIVE_DIR" "$MAX_TASK_SECONDS" << 'PYEOF'
import json, sys, os, subprocess, glob, hashlib
from datetime import datetime, timezone

queue_file = sys.argv[1]
results_dir = sys.argv[2]
pai_submit = sys.argv[3]
staging_dir = sys.argv[4]
inbox_dir = sys.argv[5]
archive_dir = sys.argv[6]
max_task_seconds = int(sys.argv[7])

now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")

def parse_time(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None

# Read queue
with open(queue_file) as f:
    queue = json.load(f)

if queue.get("status") not in ("initialized", "running"):
    sys.exit(0)

items = queue.get("items", [])
idx = queue.get("current_index", 0)

if idx >= len(items):
    sys.exit(0)

current = items[idx]

# PRD execution prompt template (same as init)
PROMPT_TEMPLATE = """You are executing a PRD for the {project} project.
This is an autonomous overnight run — no human is available.

INSTRUCTIONS:
1. Read the PRD carefully and understand all requirements
2. Implement each item systematically, following existing code patterns
3. Create descriptive git commits after each logical unit of work
4. If you encounter ambiguity, make the reasonable default choice and document it
5. If you hit a blocker, document it clearly and move on to the next item

--- PRD: {title} ---
{content}
--- End PRD ---

DELIVERABLES: Report what was implemented, what was skipped (and why),
decisions Marius should review, and suggested follow-up items."""

def find_result(task_id):
    """Find result file with prefix fallback (matches pai-result.sh logic)."""
    if not task_id:
        return None
    # Exact match first
    exact = os.path.join(results_dir, f"{task_id}.json")
    if os.path.isfile(exact):
        return exact
    # Prefix fallback
    matches = sorted(glob.glob(os.path.join(results_dir, f"{task_id}*.json")))
    if len(matches) == 1:
        return matches[0]
    return None

def read_result(path):
    """Read result JSON and extract key fields."""
    try:
        with open(path) as f:
            r = json.load(f)
        return {
            "status": r.get("status", "unknown"),
            "session_id": r.get("session_id"),
            "error": r.get("error"),
            "summary": r.get("summary", r.get("result", "")),
        }
    except (json.JSONDecodeError, IOError):
        return None

def submit_next(item_idx):
    """Submit the next pending item."""
    item = items[item_idx]
    project = queue.get("project", "openclaw-bot")
    defaults = queue.get("defaults", {})

    prd_path = os.path.join(staging_dir, item["prd_file"])
    if not os.path.isfile(prd_path):
        item["status"] = "failed"
        item["error"] = f"PRD file not found: {item['prd_file']}"
        return False

    with open(prd_path) as f:
        prd_content = f.read()

    prompt = PROMPT_TEMPLATE.format(
        project=project,
        title=item["prd_title"],
        content=prd_content,
    )

    try:
        result = subprocess.run(
            [pai_submit, prompt,
             "--project", project,
             "--priority", defaults.get("priority", "normal"),
             "--timeout", str(defaults.get("timeout_minutes", 120)),
             "--max-turns", str(defaults.get("max_turns", 50))],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            item["status"] = "failed"
            item["error"] = f"submit failed: {result.stderr.strip()}"
            return False
        # Parse task ID
        for line in result.stdout.strip().split("\n"):
            if line.startswith("Task submitted: "):
                item["task_id"] = line.split(": ", 1)[1].strip()
                break
        item["status"] = "running"
        item["submitted_at"] = timestamp
        return True
    except subprocess.TimeoutExpired:
        item["status"] = "failed"
        item["error"] = "submit timed out"
        return False

def generate_morning_report():
    """Write morning report to Gregor's inbox."""
    project = queue.get("project", "openclaw-bot")
    completed = queue.get("completed_count", 0)
    failed = queue.get("failed_count", 0)
    total = len(items)

    # Calculate duration
    created = parse_time(queue.get("created_at"))
    duration_str = "unknown"
    if created:
        delta = now - created
        hours = int(delta.total_seconds() // 3600)
        minutes = int((delta.total_seconds() % 3600) // 60)
        duration_str = f"{hours}h {minutes}m"
        start_str = created.strftime("%H:%M")
        end_str = now.strftime("%H:%M UTC")
    else:
        start_str = "?"
        end_str = "?"

    # Build report body
    lines = [
        "=== PAI Overnight Report ===",
        f"Run: {queue.get('id', 'unknown')}",
        f"Project: {project}",
        f"Duration: {duration_str} ({start_str} - {end_str})",
        "",
    ]

    for item in items:
        idx_label = f"[{item['index']+1}/{total}]"
        status_label = item.get("status", "unknown").upper()
        title = item.get("prd_title", item.get("prd_file", "?"))
        # Calculate item duration
        item_dur = ""
        sub_t = parse_time(item.get("submitted_at"))
        comp_t = parse_time(item.get("completed_at"))
        if sub_t and comp_t:
            d = comp_t - sub_t
            m = int(d.total_seconds() // 60)
            if m >= 60:
                item_dur = f"({m // 60}h {m % 60}m"
            else:
                item_dur = f"({m}m"
            sid = item.get("session_id")
            if sid:
                item_dur += f", session: {sid[:8]}"
            item_dur += ")"
        elif item.get("error"):
            item_dur = f"(error: {item['error'][:40]})"

        lines.append(f"{idx_label} {status_label:12s} {item.get('prd_file', '?')} \"{title}\" {item_dur}")

    lines.append("")
    lines.append(f"Summary: {completed} completed, {failed} failed, {total - completed - failed} other")
    lines.append("")
    lines.append("Check full results: pai-overnight.sh report")
    lines.append("Check individual: pai-result.sh <task-id>")

    body = "\n".join(lines)

    # Determine priority
    priority = "high" if failed > 0 else "normal"
    subject = f"PAI Overnight Complete: {completed}/{total} succeeded"
    if failed > 0:
        subject = f"PAI Overnight: {completed}/{total} OK, {failed} FAILED"

    # Write to inbox (matching pai-result-notify.sh schema)
    os.makedirs(inbox_dir, exist_ok=True)
    date_slug = now.strftime("%Y%m%d-%H%M%S")
    rand_suffix = hashlib.sha256(os.urandom(8)).hexdigest()[:8]
    msg_id = f"{date_slug}-{rand_suffix}"
    filename = f"{date_slug}-overnight-report.json"

    message = {
        "id": msg_id,
        "from": "pai-pipeline",
        "to": "bot",
        "timestamp": timestamp,
        "type": "overnight-report",
        "subject": subject,
        "body": body,
        "priority": priority,
        "replyTo": None,
    }

    inbox_path = os.path.join(inbox_dir, filename)
    with open(inbox_path, "w") as f:
        json.dump(message, f, indent=2)
    os.chmod(inbox_path, 0o660)
    print(f"Morning report written: {filename}")

changed = False

# --- Check current running task ---
if current["status"] == "running" and current.get("task_id"):
    result_path = find_result(current["task_id"])

    if result_path:
        # Result found — read it
        rdata = read_result(result_path)
        if rdata:
            current["result_status"] = rdata["status"]
            current["session_id"] = rdata.get("session_id")
            current["completed_at"] = timestamp
            if rdata["status"] == "error":
                current["status"] = "failed"
                current["error"] = rdata.get("error", "task returned error")
                queue["failed_count"] = queue.get("failed_count", 0) + 1
            else:
                current["status"] = "completed"
                queue["completed_count"] = queue.get("completed_count", 0) + 1
            changed = True
            print(f"ADVANCE: item {idx} ({current['prd_file']}) -> {current['status']}")
    else:
        # No result yet — check for Max window expiry (5 hours)
        submitted = parse_time(current.get("submitted_at"))
        if submitted:
            elapsed = (now - submitted).total_seconds()
            if elapsed > max_task_seconds:
                current["status"] = "failed"
                current["error"] = "Max window expiry (>5h)"
                current["completed_at"] = timestamp
                queue["failed_count"] = queue.get("failed_count", 0) + 1
                changed = True
                print(f"ADVANCE: item {idx} ({current['prd_file']}) -> failed (Max window expiry)")

# --- If current is done, submit next ---
if current["status"] in ("completed", "failed"):
    # Find next pending item
    next_idx = None
    for i in range(idx + 1, len(items)):
        if items[i]["status"] == "pending":
            next_idx = i
            break

    if next_idx is not None:
        queue["current_index"] = next_idx
        if submit_next(next_idx):
            print(f"ADVANCE: submitted item {next_idx} ({items[next_idx]['prd_file']})")
            if items[next_idx]["status"] == "failed":
                queue["failed_count"] = queue.get("failed_count", 0) + 1
        else:
            print(f"ADVANCE: failed to submit item {next_idx}")
            queue["failed_count"] = queue.get("failed_count", 0) + 1
        changed = True
    else:
        # All items processed
        queue["status"] = "completed"
        queue["updated_at"] = timestamp
        changed = True
        print("ADVANCE: all items processed, queue complete")
        # Generate morning report
        if not queue.get("report_generated"):
            generate_morning_report()
            queue["report_generated"] = True
            # Archive the queue
            archive_name = f"{queue.get('id', 'unknown')}.json"
            archive_path = os.path.join(archive_dir, archive_name)
            # Will be written below as queue_file, copy after

if changed:
    queue["updated_at"] = timestamp
    with open(queue_file, "w") as f:
        json.dump(queue, f, indent=2)
    os.chmod(queue_file, 0o660)

    # Archive completed queue
    if queue.get("status") == "completed":
        archive_name = f"{queue.get('id', 'unknown')}.json"
        archive_path = os.path.join(archive_dir, archive_name)
        import shutil
        shutil.copy2(queue_file, archive_path)
        os.chmod(archive_path, 0o660)
PYEOF
}

# ============================================================
# STATUS: Show queue progress
# ============================================================
cmd_status() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "No active overnight queue."
        exit 0
    fi

    python3 - "$QUEUE_FILE" "$JSON_OUTPUT" << 'PYEOF'
import json, sys

queue_file = sys.argv[1]
json_output = sys.argv[2] == "True"

with open(queue_file) as f:
    queue = json.load(f)

if json_output:
    print(json.dumps(queue, indent=2))
    sys.exit(0)

items = queue.get("items", [])
total = len(items)
completed = queue.get("completed_count", 0)
failed = queue.get("failed_count", 0)
pending = total - completed - failed
running = sum(1 for i in items if i.get("status") == "running")

print(f"Queue:    {queue.get('id', 'unknown')}")
print(f"Status:   {queue.get('status', 'unknown')}")
print(f"Project:  {queue.get('project', 'unknown')}")
print(f"Progress: {completed}/{total} completed, {failed} failed, {pending} pending")
print(f"Created:  {queue.get('created_at', 'unknown')}")
print(f"Updated:  {queue.get('updated_at', 'unknown')}")
print()

for item in items:
    idx = item.get("index", 0)
    status = item.get("status", "?")
    marker = {"pending": "⏳", "running": "🔄", "completed": "✅", "failed": "❌", "cancelled": "🚫"}.get(status, "?")
    title = item.get("prd_title", item.get("prd_file", "?"))
    task_id = item.get("task_id", "")
    extra = ""
    if item.get("error"):
        extra = f" ({item['error'][:40]})"
    elif task_id:
        extra = f" [{task_id[:16]}]"
    print(f"  {marker} [{idx+1}/{total}] {item.get('prd_file', '?')} \"{title}\"{extra}")
PYEOF
}

# ============================================================
# REPORT: Generate/display morning report
# ============================================================
cmd_report() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "No overnight queue found."
        exit 0
    fi

    python3 - "$QUEUE_FILE" "$JSON_OUTPUT" "$INBOX_DIR" << 'PYEOF'
import json, sys, os, hashlib
from datetime import datetime, timezone

queue_file = sys.argv[1]
json_output = sys.argv[2] == "True"
inbox_dir = sys.argv[3]

with open(queue_file) as f:
    queue = json.load(f)

now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
items = queue.get("items", [])
total = len(items)
completed = queue.get("completed_count", 0)
failed = queue.get("failed_count", 0)

def parse_time(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None

# Calculate duration
created = parse_time(queue.get("created_at"))
duration_str = "unknown"
if created:
    end = parse_time(queue.get("updated_at")) or now
    delta = end - created
    hours = int(delta.total_seconds() // 3600)
    minutes = int((delta.total_seconds() % 3600) // 60)
    duration_str = f"{hours}h {minutes}m"

lines = [
    "=== PAI Overnight Report ===",
    f"Run: {queue.get('id', 'unknown')}",
    f"Project: {queue.get('project', 'unknown')}",
    f"Status: {queue.get('status', 'unknown')}",
    f"Duration: {duration_str}",
    "",
]

for item in items:
    idx_label = f"[{item['index']+1}/{total}]"
    status_label = item.get("status", "unknown").upper()
    title = item.get("prd_title", item.get("prd_file", "?"))
    item_dur = ""
    sub_t = parse_time(item.get("submitted_at"))
    comp_t = parse_time(item.get("completed_at"))
    if sub_t and comp_t:
        m = int((comp_t - sub_t).total_seconds() // 60)
        if m >= 60:
            item_dur = f"({m // 60}h {m % 60}m)"
        else:
            item_dur = f"({m}m)"
    elif item.get("error"):
        item_dur = f"(error: {item['error'][:40]})"

    lines.append(f"{idx_label} {status_label:12s} {item.get('prd_file', '?')} \"{title}\" {item_dur}")

lines.append("")
lines.append(f"Summary: {completed} completed, {failed} failed, {total - completed - failed} other")

report_text = "\n".join(lines)

if json_output:
    print(json.dumps({"report": report_text, "queue": queue}, indent=2))
else:
    print(report_text)
PYEOF
}

# ============================================================
# CANCEL: Stop processing, mark remaining as cancelled
# ============================================================
cmd_cancel() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        die "No active overnight queue."
    fi

    python3 - "$QUEUE_FILE" << 'PYEOF'
import json, sys
from datetime import datetime, timezone

queue_file = sys.argv[1]
now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")

with open(queue_file) as f:
    queue = json.load(f)

if queue.get("status") not in ("initialized", "running"):
    print(f"Queue is already {queue.get('status')} — nothing to cancel.")
    sys.exit(0)

cancelled_count = 0
for item in queue.get("items", []):
    if item.get("status") in ("pending", "running"):
        item["status"] = "cancelled"
        item["error"] = "manually cancelled"
        item["completed_at"] = timestamp
        cancelled_count += 1

queue["status"] = "cancelled"
queue["updated_at"] = timestamp

with open(queue_file, "w") as f:
    json.dump(queue, f, indent=2)

print(f"Queue cancelled. {cancelled_count} item(s) marked cancelled.")
PYEOF

    log "CANCEL: queue cancelled by user"
}

# ============================================================
# RESUME: Resubmit current failed/stuck item
# ============================================================
cmd_resume() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        die "No overnight queue found."
    fi

    python3 - "$QUEUE_FILE" "$STAGING_DIR" "$PAI_SUBMIT" << 'PYEOF'
import json, sys, os, subprocess
from datetime import datetime, timezone

queue_file = sys.argv[1]
staging_dir = sys.argv[2]
pai_submit = sys.argv[3]

now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")

with open(queue_file) as f:
    queue = json.load(f)

if queue.get("status") not in ("running", "cancelled"):
    print(f"Queue status is '{queue.get('status')}' — resuming only works on running or cancelled queues.")
    sys.exit(1)

items = queue.get("items", [])
idx = queue.get("current_index", 0)

# Find first non-completed item to resume
resume_idx = None
for i in range(idx, len(items)):
    if items[i].get("status") in ("failed", "cancelled", "running"):
        resume_idx = i
        break

if resume_idx is None:
    # Check for any pending items
    for i in range(len(items)):
        if items[i].get("status") == "pending":
            resume_idx = i
            break

if resume_idx is None:
    print("Nothing to resume — all items are completed.")
    sys.exit(0)

item = items[resume_idx]
project = queue.get("project", "openclaw-bot")
defaults = queue.get("defaults", {})

# If it was failed, decrement fail count
if item.get("status") == "failed":
    queue["failed_count"] = max(0, queue.get("failed_count", 0) - 1)

PROMPT_TEMPLATE = """You are executing a PRD for the {project} project.
This is an autonomous overnight run — no human is available.

INSTRUCTIONS:
1. Read the PRD carefully and understand all requirements
2. Implement each item systematically, following existing code patterns
3. Create descriptive git commits after each logical unit of work
4. If you encounter ambiguity, make the reasonable default choice and document it
5. If you hit a blocker, document it clearly and move on to the next item

--- PRD: {title} ---
{content}
--- End PRD ---

DELIVERABLES: Report what was implemented, what was skipped (and why),
decisions Marius should review, and suggested follow-up items."""

prd_path = os.path.join(staging_dir, item["prd_file"])
if not os.path.isfile(prd_path):
    print(f"Error: PRD file not found: {prd_path}")
    sys.exit(1)

with open(prd_path) as f:
    prd_content = f.read()

prompt = PROMPT_TEMPLATE.format(
    project=project,
    title=item["prd_title"],
    content=prd_content,
)

try:
    result = subprocess.run(
        [pai_submit, prompt,
         "--project", project,
         "--priority", defaults.get("priority", "normal"),
         "--timeout", str(defaults.get("timeout_minutes", 120)),
         "--max-turns", str(defaults.get("max_turns", 50))],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        print(f"Error: pai-submit.sh failed: {result.stderr.strip()}")
        sys.exit(1)

    # Parse task ID
    for line in result.stdout.strip().split("\n"):
        if line.startswith("Task submitted: "):
            item["task_id"] = line.split(": ", 1)[1].strip()
            break

    item["status"] = "running"
    item["submitted_at"] = timestamp
    item["completed_at"] = None
    item["result_status"] = None
    item["error"] = None
    queue["current_index"] = resume_idx
    queue["status"] = "running"
    queue["updated_at"] = timestamp

    with open(queue_file, "w") as f:
        json.dump(queue, f, indent=2)

    print(f"Resumed item {resume_idx} ({item['prd_file']})")
    if item.get("task_id"):
        print(f"Task ID: {item['task_id']}")
    print(result.stdout.strip())
except subprocess.TimeoutExpired:
    print("Error: pai-submit.sh timed out")
    sys.exit(1)
PYEOF

    log "RESUME: resubmitted item at index $(python3 -c "
import json
with open('$QUEUE_FILE') as f:
    print(json.load(f).get('current_index', '?'))
")"
}

# --- Dispatch ---
case "$SUBCMD" in
    init)     cmd_init ;;
    advance)  cmd_advance ;;
    status)   cmd_status ;;
    report)   cmd_report ;;
    cancel)   cmd_cancel ;;
    resume)   cmd_resume ;;
    help|--help|-h)
        echo "Usage: pai-overnight.sh <command> [options]"
        echo ""
        echo "Commands: init, advance, status, report, cancel, resume"
        echo "Run: pai-overnight.sh <command> --help for details"
        exit 0
        ;;
    *)
        die "Unknown command: $SUBCMD (try: init, advance, status, report, cancel, resume)"
        ;;
esac
