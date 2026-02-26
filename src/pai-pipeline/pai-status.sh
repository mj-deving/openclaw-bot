#!/usr/bin/env bash
# pai-status: Dashboard for the PAI cross-agent pipeline
# Runs ON VPS as openclaw user — Gregor calls this directly via shell
#
# Usage:
#   pai-status.sh           Full status overview
#   pai-status.sh --json    Machine-readable JSON output

set -euo pipefail

PIPELINE_DIR="/var/lib/pai-pipeline"

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

TASKS_COUNT=$(find "${PIPELINE_DIR}/tasks" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
RESULTS_COUNT=$(find "${PIPELINE_DIR}/results" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
ACK_COUNT=$(find "${PIPELINE_DIR}/ack" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)

if $JSON_MODE; then
    python3 - "$PIPELINE_DIR" << 'PYEOF'
import json, sys, os, glob

pipeline_dir = sys.argv[1]

def read_tasks(subdir):
    items = []
    pattern = os.path.join(pipeline_dir, subdir, "*.json")
    for path in sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True):
        try:
            with open(path) as f:
                data = json.load(f)
            items.append({
                "id": data.get("taskId", data.get("id", os.path.splitext(os.path.basename(path))[0])),
                "timestamp": data.get("timestamp"),
                "status": data.get("status", "pending" if subdir == "tasks" else "completed"),
                "priority": data.get("priority", "normal"),
                "summary": data.get("summary", data.get("result", data.get("prompt", "")))[:80]
            })
        except (json.JSONDecodeError, IOError):
            items.append({"id": os.path.basename(path), "error": "unreadable"})
    return items

status = {
    "tasks_pending": read_tasks("tasks"),
    "results_ready": read_tasks("results"),
    "acknowledged": len(glob.glob(os.path.join(pipeline_dir, "ack", "*.json"))),
}

print(json.dumps(status, indent=2))
PYEOF
    exit 0
fi

echo "=== PAI Pipeline Status ==="
echo ""
echo "  Tasks pending:    ${TASKS_COUNT}"
echo "  Results ready:    ${RESULTS_COUNT}"
echo "  Acknowledged:     ${ACK_COUNT}"

if [[ "$TASKS_COUNT" -gt 0 ]]; then
    echo ""
    echo "--- Pending Tasks ---"
    for f in $(ls -1t "${PIPELINE_DIR}/tasks/"*.json 2>/dev/null | head -5); do
        python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    t = json.load(f)
task_id = t.get('taskId', t.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0]))
priority = t.get('priority', 'normal')
prompt = t.get('prompt', '?')
if len(prompt) > 60:
    prompt = prompt[:57] + '...'
print(f\"  [{priority}] {task_id}  {prompt}\")
" "$f"
    done
    if [[ "$TASKS_COUNT" -gt 5 ]]; then
        echo "  ... and $((TASKS_COUNT - 5)) more"
    fi
fi

if [[ "$RESULTS_COUNT" -gt 0 ]]; then
    echo ""
    echo "--- Results Ready ---"
    for f in $(ls -1t "${PIPELINE_DIR}/results/"*.json 2>/dev/null | head -5); do
        python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    r = json.load(f)
task_id = r.get('taskId', r.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0]))
status = r.get('status', '?')
summary = r.get('summary', r.get('result', '(no summary)'))
if len(summary) > 60:
    summary = summary[:57] + '...'
print(f\"  [{status}] {task_id}  {summary}\")
" "$f"
    done
    if [[ "$RESULTS_COUNT" -gt 5 ]]; then
        echo "  ... and $((RESULTS_COUNT - 5)) more"
    fi
fi

echo ""
echo "Commands:"
echo "  pai-submit.sh <prompt>       Submit a task to Isidore Cloud"
echo "  pai-result.sh <task-id>      Read a specific result"
echo "  pai-result.sh --latest       Read the most recent result"
