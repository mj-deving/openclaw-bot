#!/usr/bin/env bash
# pai-result-notify: Notify Gregor when PAI pipeline results are ready
# Runs ON VPS as openclaw user — triggered by systemd path unit
#
# Reads all un-notified results from /var/lib/pai-pipeline/results/,
# formats a notification for each, and writes it to Gregor's internal
# pipeline inbox (~/.openclaw/pipeline/inbox/).
#
# Marker files (.notified-<taskId>) prevent duplicate notifications.
# This script MUST drain ALL pending results in one invocation because
# systemd PathChanged won't re-trigger while the service is active.
#
# Usage:
#   pai-result-notify.sh           Process all un-notified results
#   pai-result-notify.sh --dry-run Show what would be sent (no writes)
#   pai-result-notify.sh --cleanup Remove markers older than 7 days

set -euo pipefail

PAI_RESULTS_DIR="/var/lib/pai-pipeline/results"
INBOX_DIR="${HOME}/.openclaw/pipeline/inbox"
LOG_DIR="${HOME}/.openclaw/logs"
LOG_FILE="${LOG_DIR}/pai-notify.log"
MARKER_RETENTION_DAYS=7

# --- Logging ---
log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Iseconds): $1" >> "$LOG_FILE"
}

# --- Argument parsing ---
DRY_RUN=false
CLEANUP_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true; shift ;;
        --cleanup)   CLEANUP_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: pai-result-notify.sh [--dry-run] [--cleanup]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be sent (no writes)"
            echo "  --cleanup    Remove stale markers (older than ${MARKER_RETENTION_DAYS} days)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# --- Marker cleanup ---
cleanup_markers() {
    local pruned
    pruned=$(find "$PAI_RESULTS_DIR" -maxdepth 1 -name '.notified-*' -mtime +"$MARKER_RETENTION_DAYS" -delete -print 2>/dev/null | wc -l)
    if [[ "$pruned" -gt 0 ]]; then
        log "Pruned $pruned stale marker files (older than ${MARKER_RETENTION_DAYS} days)"
    fi
}

if $CLEANUP_ONLY; then
    cleanup_markers
    exit 0
fi

# --- Main: drain all un-notified results ---
mkdir -p "$INBOX_DIR"

NOTIFIED_COUNT=0
SKIPPED_COUNT=0

for result_file in "$PAI_RESULTS_DIR"/*.json; do
    # Handle glob non-match (no json files in directory)
    [[ -e "$result_file" ]] || continue

    # Extract task ID from filename (filename is <taskId>.json per bridge convention)
    basename_noext=$(basename "$result_file" .json)
    marker_file="${PAI_RESULTS_DIR}/.notified-${basename_noext}"

    # Skip already-notified results
    if [[ -f "$marker_file" ]]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    if $DRY_RUN; then
        # Dry run: show what would be sent without writing anything
        python3 - "$result_file" << 'PYEOF'
import json, sys, os

result_path = sys.argv[1]
try:
    with open(result_path) as f:
        r = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(f"  SKIP (unreadable): {os.path.basename(result_path)} -- {e}")
    sys.exit(0)

task_id = r.get("taskId", r.get("id", os.path.splitext(os.path.basename(result_path))[0]))
status = r.get("status", "unknown")
summary = r.get("summary", r.get("result", "(no summary)"))
if len(summary) > 80:
    summary = summary[:77] + "..."

print(f"  WOULD NOTIFY: [{status}] {task_id}")
print(f"    Summary: {summary}")
PYEOF
    else
        # Real run: read result, write notification to inbox, create marker
        python3 - "$result_file" "$INBOX_DIR" << 'PYEOF'
import json, sys, os, glob
from datetime import datetime, timezone
import hashlib

result_path = sys.argv[1]
inbox_dir = sys.argv[2]

# Read result JSON
try:
    with open(result_path) as f:
        r = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(f"ERROR: cannot read {os.path.basename(result_path)}: {e}", file=sys.stderr)
    sys.exit(1)

# Extract fields with safe fallbacks
task_id = r.get("taskId", r.get("id", os.path.splitext(os.path.basename(result_path))[0]))
status = r.get("status", "unknown")
summary = r.get("summary", r.get("result", "(no summary)"))
error_msg = r.get("error")
usage = r.get("usage", r.get("token_usage", {}))
session_id = r.get("session_id")
result_timestamp = r.get("timestamp", "unknown")
structured = r.get("structured", {})
branch = r.get("branch")

# --- Check original task type from ack/ directory ---
# The task file is moved to ack/ after bridge picks it up, with same taskId prefix
ack_dir = "/var/lib/pai-pipeline/ack"
original_type = "request"  # default
for ack_file in glob.glob(os.path.join(ack_dir, f"{task_id}*.json")):
    try:
        with open(ack_file) as af:
            orig = json.load(af)
        original_type = orig.get("type", "request")
        break
    except (json.JSONDecodeError, IOError):
        pass

is_orchestrate = (original_type == "orchestrate")

# Truncate summary for notification (2000 chars keeps total body under Telegram's 4096 limit)
original_len = len(summary)
if original_len > 2000:
    summary = summary[:1970] + f"\n\n...[truncated, {original_len} chars total — run: pai-result.sh {task_id}]"

# Priority: errors are high, follow_up_needed is high, else normal
follow_up_needed = False
if isinstance(structured, dict):
    follow_up_needed = structured.get("follow_up_needed", False)
priority = "high" if (status == "error" or follow_up_needed) else "normal"

# Build subject line
if is_orchestrate:
    subject = f"PAI Workflow Initiated: {task_id}"
elif status == "error":
    subject = f"PAI Result FAILED: {task_id}"
elif status == "completed":
    subject = f"PAI Result Ready: {task_id}"
else:
    subject = f"PAI Result [{status}]: {task_id}"

# Build notification body
body_lines = [
    f"Task ID: {task_id}",
    f"Status: {status}",
    f"Completed: {result_timestamp}",
]
if is_orchestrate:
    body_lines.append(f"Type: orchestrate")
    body_lines.append("")
    body_lines.append("--- Workflow Initiated ---")
    body_lines.append("This task has been decomposed into a multi-step workflow.")
    body_lines.append("Progress and completion will be reported via Telegram.")
    body_lines.append("Use pai-workflow-status.sh to check workflow progress.")
else:
    if usage:
        inp = usage.get("input_tokens", usage.get("input", 0))
        out = usage.get("output_tokens", usage.get("output", 0))
        if inp or out:
            body_lines.append(f"Tokens: {inp} in / {out} out")
    if session_id:
        body_lines.append(f"Session: {session_id} (resumable with --session)")
    if branch:
        body_lines.append(f"Branch: {branch}")
    body_lines.append("")
    body_lines.append("--- Summary ---")
    body_lines.append(summary)
    if error_msg:
        body_lines.append("")
        body_lines.append("--- Error ---")
        body_lines.append(str(error_msg))
    # Structured field enrichment (one-shot results)
    if isinstance(structured, dict) and structured:
        artifacts = structured.get("artifacts", [])
        if artifacts:
            body_lines.append("")
            body_lines.append("--- Artifacts ---")
            for a in artifacts:
                body_lines.append(f"  - {a}")
        recs = structured.get("recommendations_for_sender")
        if recs:
            body_lines.append("")
            body_lines.append("--- Recommendations ---")
            body_lines.append(str(recs))
    if follow_up_needed:
        body_lines.append("")
        body_lines.append("*** FOLLOW-UP NEEDED: Isidore Cloud flagged this result for your review. ***")
        suggested = structured.get("suggested_next_prompt") if isinstance(structured, dict) else None
        if suggested:
            body_lines.append(f"Suggested next: {suggested}")

body_lines.append("")
body_lines.append(f"Full result: pai-result.sh {task_id}")
body_lines.append(f"Acknowledge: pai-result.sh {task_id} --ack")

body = "\n".join(body_lines)

# Generate message ID and filename
now = datetime.now(timezone.utc)
msg_timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
date_slug = now.strftime("%Y%m%d-%H%M%S")
rand_suffix = hashlib.sha256(os.urandom(8)).hexdigest()[:8]
msg_id = f"{date_slug}-{rand_suffix}"

# Filename follows internal pipeline convention
slug = f"pai-result-{task_id}"[:30]
filename = f"{date_slug}-notification-{slug}.json"

# Build internal pipeline message (matches send.sh schema)
message = {
    "id": msg_id,
    "from": "pai-pipeline",
    "to": "bot",
    "timestamp": msg_timestamp,
    "type": "notification",
    "subject": subject,
    "body": body,
    "priority": priority,
    "replyTo": None,
    "workflow_initiated": is_orchestrate,
    "structured": structured if isinstance(structured, dict) else {},
    "branch": branch,
    "follow_up_needed": follow_up_needed,
}

# Write to inbox
inbox_path = os.path.join(inbox_dir, filename)
with open(inbox_path, "w") as f:
    json.dump(message, f, indent=2)
os.chmod(inbox_path, 0o660)

label = "WORKFLOW" if is_orchestrate else status
print(f"NOTIFIED: [{label}] {task_id} -> {filename}")
PYEOF

        # Create marker only if python3 succeeded
        if [[ $? -eq 0 ]]; then
            touch "$marker_file"
            NOTIFIED_COUNT=$((NOTIFIED_COUNT + 1))
        else
            log "ERROR: failed to process ${basename_noext}"
        fi
    fi
done

# Run marker cleanup after every pass
cleanup_markers

# Log summary
if [[ $NOTIFIED_COUNT -gt 0 ]] || [[ $SKIPPED_COUNT -gt 0 ]]; then
    log "Notification pass: ${NOTIFIED_COUNT} notified, ${SKIPPED_COUNT} skipped (already notified)"
fi

if $DRY_RUN; then
    echo ""
    echo "Dry run complete. No notifications sent."
fi
