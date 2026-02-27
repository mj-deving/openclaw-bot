#!/usr/bin/env bash
# pai-workflow-monitor: Detect stale workflows and alert via Gregor's inbox
# Runs ON VPS as openclaw user — called by system crontab every 15 minutes
#
# Stale = active workflow with in_progress steps and no update in >1 hour.
# 4+ hours stale = possible Max window expiry (high-priority alert).
#
# Marker files in /tmp/pai-workflow-alerts/ prevent duplicate alerts.
# Markers for non-active workflows are cleaned up each run.
# /tmp/ is auto-cleaned on reboot for additional safety.
#
# Usage:
#   pai-workflow-monitor.sh           Check and alert (normal operation)
#   pai-workflow-monitor.sh --dry-run Show what would be alerted (no writes)
#
# Crontab entry:
#   */15 * * * * /home/openclaw/scripts/pai-workflow-monitor.sh

set -euo pipefail

WORKFLOWS_DIR="/var/lib/pai-pipeline/workflows"
INBOX_DIR="${HOME}/.openclaw/pipeline/inbox"
MARKER_DIR="/tmp/pai-workflow-alerts"
LOG_DIR="${HOME}/.openclaw/logs"
LOG_FILE="${LOG_DIR}/pai-workflow-monitor.log"
STALE_THRESHOLD=3600     # 1 hour in seconds
MAX_WINDOW_THRESHOLD=14400  # 4 hours in seconds

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Iseconds): $1" >> "$LOG_FILE"
}

# Ensure marker directory exists
mkdir -p "$MARKER_DIR"

# Exit early if no workflows directory
if [[ ! -d "$WORKFLOWS_DIR" ]]; then
    exit 0
fi

# No workflow files? Clean up orphan markers and exit
shopt -s nullglob
wf_files=("$WORKFLOWS_DIR"/*.json)
if [[ ${#wf_files[@]} -eq 0 ]]; then
    # Clean all markers — no workflows exist
    rm -f "$MARKER_DIR"/.alerted-* 2>/dev/null
    exit 0
fi

python3 - "$WORKFLOWS_DIR" "$INBOX_DIR" "$MARKER_DIR" "$DRY_RUN" \
    "$STALE_THRESHOLD" "$MAX_WINDOW_THRESHOLD" << 'PYEOF'
import json, sys, os, glob, hashlib
from datetime import datetime, timezone

wf_dir = sys.argv[1]
inbox_dir = sys.argv[2]
marker_dir = sys.argv[3]
dry_run = sys.argv[4] == "True"
stale_threshold = int(sys.argv[5])
max_window_threshold = int(sys.argv[6])

now = datetime.now(timezone.utc)

def parse_time(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None

# Collect active workflow IDs for marker cleanup
active_ids = set()
stale_alerts = []

for path in glob.glob(os.path.join(wf_dir, "*.json")):
    try:
        with open(path) as f:
            wf = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue

    wf_id = wf.get("id", os.path.splitext(os.path.basename(path))[0])
    wf_status = wf.get("status", "unknown")

    if wf_status == "active":
        active_ids.add(wf_id)
    else:
        continue  # Only check active workflows for staleness

    # Check if any steps are in_progress
    steps = wf.get("steps", [])
    has_in_progress = any(s.get("status") == "in_progress" for s in steps)
    if not has_in_progress:
        continue

    # Check staleness
    updated = parse_time(wf.get("updatedAt"))
    if not updated:
        age_seconds = stale_threshold + 1  # No timestamp = assume stale
    else:
        age_seconds = (now - updated).total_seconds()

    if age_seconds < stale_threshold:
        continue  # Not stale

    # Check marker
    marker_path = os.path.join(marker_dir, f".alerted-{wf_id}")
    if os.path.exists(marker_path):
        continue  # Already alerted

    # Determine severity
    is_max_window = age_seconds >= max_window_threshold
    desc = wf.get("description", "")
    completed = sum(1 for s in steps if s.get("status") == "completed")
    total = len(steps)

    stale_alerts.append({
        "id": wf_id,
        "description": desc,
        "age_hours": age_seconds / 3600,
        "is_max_window": is_max_window,
        "steps_completed": completed,
        "steps_total": total,
        "marker_path": marker_path,
    })

# --- Clean up markers for non-active workflows ---
for marker_file in glob.glob(os.path.join(marker_dir, ".alerted-*")):
    marker_wf_id = os.path.basename(marker_file).replace(".alerted-", "")
    if marker_wf_id not in active_ids:
        if dry_run:
            print(f"WOULD CLEAN marker: {marker_wf_id} (no longer active)")
        else:
            os.remove(marker_file)

# --- Send alerts ---
if not stale_alerts:
    sys.exit(0)

for alert in stale_alerts:
    severity = "CRITICAL" if alert["is_max_window"] else "WARNING"
    age_str = f"{alert['age_hours']:.1f}h"

    subject = f"Workflow {severity}: {alert['id']} stale ({age_str})"
    body_lines = [
        f"Workflow: {alert['id']}",
        f"Description: {alert['description']}",
        f"Progress: {alert['steps_completed']}/{alert['steps_total']} steps done",
        f"Last update: {age_str} ago",
        "",
    ]
    if alert["is_max_window"]:
        body_lines.append("*** POSSIBLE MAX WINDOW EXPIRY ***")
        body_lines.append("The Claude Max 5-hour window may have expired mid-workflow.")
        body_lines.append("Check bridge service status and consider resubmitting.")
    else:
        body_lines.append("No progress detected in over 1 hour.")
        body_lines.append("The bridge may be processing a long step, or it may be stuck.")
    body_lines.append("")
    body_lines.append(f"Check status: pai-workflow-status.sh {alert['id']}")

    body = "\n".join(body_lines)

    if dry_run:
        print(f"WOULD ALERT: [{severity}] {alert['id']} (stale {age_str})")
        print(f"  {alert['description']}")
        print(f"  Progress: {alert['steps_completed']}/{alert['steps_total']}")
        continue

    # Write alert to inbox
    os.makedirs(inbox_dir, exist_ok=True)
    date_slug = now.strftime("%Y%m%d-%H%M%S")
    rand_suffix = hashlib.sha256(os.urandom(8)).hexdigest()[:8]
    msg_id = f"{date_slug}-{rand_suffix}"
    filename = f"{date_slug}-workflow-alert-{alert['id'][:20]}.json"

    message = {
        "id": msg_id,
        "from": "pai-pipeline",
        "to": "bot",
        "timestamp": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "type": "workflow-alert",
        "subject": subject,
        "body": body,
        "priority": "high",
        "replyTo": None,
    }

    inbox_path = os.path.join(inbox_dir, filename)
    with open(inbox_path, "w") as f:
        json.dump(message, f, indent=2)
    os.chmod(inbox_path, 0o660)

    # Create marker
    with open(alert["marker_path"], "w") as f:
        f.write(now.strftime("%Y-%m-%dT%H:%M:%SZ"))

    print(f"ALERTED: [{severity}] {alert['id']} -> {filename}")
PYEOF
