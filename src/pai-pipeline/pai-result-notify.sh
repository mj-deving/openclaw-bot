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
import json, sys, os
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

# Truncate summary for notification
if len(summary) > 300:
    summary = summary[:297] + "..."

# Errors get high priority
priority = "high" if status == "error" else "normal"

# Build subject line
if status == "error":
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
if usage:
    inp = usage.get("input_tokens", usage.get("input", 0))
    out = usage.get("output_tokens", usage.get("output", 0))
    if inp or out:
        body_lines.append(f"Tokens: {inp} in / {out} out")
if session_id:
    body_lines.append(f"Session: {session_id} (resumable with --session)")
body_lines.append("")
body_lines.append("--- Summary ---")
body_lines.append(summary)
if error_msg:
    body_lines.append("")
    body_lines.append("--- Error ---")
    body_lines.append(str(error_msg))
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
}

# Write to inbox
inbox_path = os.path.join(inbox_dir, filename)
with open(inbox_path, "w") as f:
    json.dump(message, f, indent=2)
os.chmod(inbox_path, 0o660)

print(f"NOTIFIED: [{status}] {task_id} -> {filename}")
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
