#!/usr/bin/env bash
# pai-workflow-status: Query workflow status from the PAI pipeline
# Runs ON VPS as openclaw user — Gregor calls this directly via shell
#
# Usage:
#   pai-workflow-status.sh                    List all active workflows
#   pai-workflow-status.sh <workflow-id>      Show specific workflow detail
#   pai-workflow-status.sh --stale            Find workflows with no progress in >1h
#   pai-workflow-status.sh --json             Machine-readable output (combinable with above)
#
# Examples:
#   pai-workflow-status.sh
#   pai-workflow-status.sh wf-abc123
#   pai-workflow-status.sh --stale --json

set -euo pipefail

WORKFLOWS_DIR="/var/lib/pai-pipeline/workflows"
STALE_THRESHOLD_SECONDS=3600  # 1 hour

# --- Argument parsing ---
WORKFLOW_ID=""
STALE_ONLY=false
JSON_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stale)  STALE_ONLY=true; shift ;;
        --json)   JSON_MODE=true; shift ;;
        --help|-h)
            echo "Usage: pai-workflow-status.sh [workflow-id] [--stale] [--json]"
            echo ""
            echo "Options:"
            echo "  <workflow-id>  Show specific workflow detail"
            echo "  --stale        Find workflows with no progress in >1 hour"
            echo "  --json         Machine-readable JSON output"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            WORKFLOW_ID="$1"; shift ;;
    esac
done

# Check workflows directory exists
if [[ ! -d "$WORKFLOWS_DIR" ]]; then
    if $JSON_MODE; then
        echo '{"workflows": [], "message": "No workflows directory found"}'
    else
        echo "No workflows directory found at ${WORKFLOWS_DIR}"
    fi
    exit 0
fi

python3 - "$WORKFLOWS_DIR" "$WORKFLOW_ID" "$STALE_ONLY" "$JSON_MODE" "$STALE_THRESHOLD_SECONDS" << 'PYEOF'
import json, sys, os, glob
from datetime import datetime, timezone

wf_dir = sys.argv[1]
workflow_id = sys.argv[2] or None
stale_only = sys.argv[3] == "True"
json_mode = sys.argv[4] == "True"
stale_threshold = int(sys.argv[5])

now = datetime.now(timezone.utc)

def parse_time(ts):
    """Parse ISO timestamp, return datetime or None."""
    if not ts:
        return None
    try:
        # Handle both Z and +00:00 formats
        ts = ts.replace("Z", "+00:00")
        return datetime.fromisoformat(ts)
    except (ValueError, TypeError):
        return None

def is_stale(wf):
    """Check if workflow has no progress in >threshold seconds."""
    if wf.get("status") != "active":
        return False
    updated = parse_time(wf.get("updatedAt"))
    if not updated:
        return True  # No timestamp = assume stale
    age_seconds = (now - updated).total_seconds()
    return age_seconds > stale_threshold

def format_workflow(wf, filepath):
    """Build structured workflow info dict."""
    wf_id = wf.get("id", os.path.splitext(os.path.basename(filepath))[0])
    steps = wf.get("steps", [])
    completed = sum(1 for s in steps if s.get("status") == "completed")
    failed = sum(1 for s in steps if s.get("status") == "failed")
    in_progress = sum(1 for s in steps if s.get("status") == "in_progress")
    pending = sum(1 for s in steps if s.get("status") == "pending")
    updated = parse_time(wf.get("updatedAt"))
    age_str = ""
    if updated:
        age_seconds = (now - updated).total_seconds()
        if age_seconds < 60:
            age_str = f"{int(age_seconds)}s ago"
        elif age_seconds < 3600:
            age_str = f"{int(age_seconds/60)}m ago"
        else:
            age_str = f"{age_seconds/3600:.1f}h ago"

    return {
        "id": wf_id,
        "description": wf.get("description", ""),
        "status": wf.get("status", "unknown"),
        "updatedAt": wf.get("updatedAt"),
        "age": age_str,
        "stale": is_stale(wf),
        "steps_total": len(steps),
        "steps_completed": completed,
        "steps_failed": failed,
        "steps_in_progress": in_progress,
        "steps_pending": pending,
        "steps": [
            {
                "id": s.get("id", "?"),
                "description": s.get("description", ""),
                "assignee": s.get("assignee", "?"),
                "status": s.get("status", "?"),
            }
            for s in steps
        ],
    }

# Load all workflow files
workflows = []
for path in sorted(glob.glob(os.path.join(wf_dir, "*.json")), key=os.path.getmtime, reverse=True):
    try:
        with open(path) as f:
            wf = json.load(f)
        info = format_workflow(wf, path)

        # Filter by specific ID if requested
        if workflow_id and info["id"] != workflow_id:
            continue

        # Filter by stale if requested
        if stale_only and not info["stale"]:
            continue

        workflows.append(info)
    except (json.JSONDecodeError, IOError) as e:
        workflows.append({"id": os.path.basename(path), "error": str(e)})

# Output
if json_mode:
    print(json.dumps({"workflows": workflows}, indent=2))
else:
    if not workflows:
        if workflow_id:
            print(f"No workflow found with ID: {workflow_id}")
        elif stale_only:
            print("No stale workflows found.")
        else:
            print("No workflows found.")
        sys.exit(0)

    for wf in workflows:
        if "error" in wf:
            print(f"  [error] {wf['id']}: {wf['error']}")
            continue
        stale_tag = " [STALE]" if wf["stale"] else ""
        desc = wf["description"]
        if len(desc) > 50:
            desc = desc[:47] + "..."
        print(f"  [{wf['status']}]{stale_tag} {wf['id']}  \"{desc}\"")
        print(f"    Progress: {wf['steps_completed']}/{wf['steps_total']} done"
              f" | {wf['steps_in_progress']} active | {wf['steps_failed']} failed"
              f" | Updated: {wf['age']}")
        for s in wf["steps"]:
            mark = "v" if s["status"] == "completed" else "x" if s["status"] == "failed" else ">" if s["status"] == "in_progress" else "o"
            sdesc = s["description"] or s["id"]
            if len(sdesc) > 45:
                sdesc = sdesc[:42] + "..."
            print(f"    {mark} {s['id']}: {sdesc} ({s['assignee']}, {s['status']})")
        print()
PYEOF
