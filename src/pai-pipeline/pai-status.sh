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
REVERSE_TASKS_COUNT=$(find "${PIPELINE_DIR}/reverse-tasks" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
REVERSE_RESULTS_COUNT=$(find "${PIPELINE_DIR}/reverse-results" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
REVERSE_ACK_COUNT=$(find "${PIPELINE_DIR}/reverse-ack" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
WORKFLOWS_DIR="${PIPELINE_DIR}/workflows"

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

# Read workflow files
workflows = []
wf_dir = os.path.join(pipeline_dir, "workflows")
if os.path.isdir(wf_dir):
    for path in sorted(glob.glob(os.path.join(wf_dir, "*.json")), key=os.path.getmtime, reverse=True):
        try:
            with open(path) as f:
                wf = json.load(f)
            steps = wf.get("steps", [])
            completed = sum(1 for s in steps if s.get("status") == "completed")
            workflows.append({
                "id": wf.get("id", os.path.splitext(os.path.basename(path))[0]),
                "description": wf.get("description", ""),
                "status": wf.get("status", "unknown"),
                "steps_total": len(steps),
                "steps_completed": completed,
                "updatedAt": wf.get("updatedAt"),
            })
        except (json.JSONDecodeError, IOError):
            workflows.append({"id": os.path.basename(path), "error": "unreadable"})

status = {
    "tasks_pending": read_tasks("tasks"),
    "results_ready": read_tasks("results"),
    "acknowledged": len(glob.glob(os.path.join(pipeline_dir, "ack", "*.json"))),
    "workflows": workflows,
    "reverse_pipeline": {
        "tasks_pending": len(glob.glob(os.path.join(pipeline_dir, "reverse-tasks", "*.json"))),
        "results_ready": len(glob.glob(os.path.join(pipeline_dir, "reverse-results", "*.json"))),
        "acknowledged": len(glob.glob(os.path.join(pipeline_dir, "reverse-ack", "*.json"))),
    },
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

# --- Active Workflows ---
if [[ -d "$WORKFLOWS_DIR" ]]; then
    WF_FILES=$(find "$WORKFLOWS_DIR" -maxdepth 1 -name '*.json' 2>/dev/null)
    if [[ -n "$WF_FILES" ]]; then
        echo ""
        echo "--- Active Workflows ---"
        for f in $(ls -1t "$WORKFLOWS_DIR"/*.json 2>/dev/null | head -5); do
            python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    wf = json.load(f)
wf_id = wf.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0])
desc = wf.get('description', '')
if len(desc) > 40:
    desc = desc[:37] + '...'
wf_status = wf.get('status', 'unknown')
steps = wf.get('steps', [])
completed = sum(1 for s in steps if s.get('status') == 'completed')
total = len(steps)
print(f'  [{wf_status}] {wf_id}  \"{desc}\" ({completed}/{total} steps done)')
for s in steps:
    sid = s.get('id', '?')
    ss = s.get('status', '?')
    assignee = s.get('assignee', '?')
    mark = 'v' if ss == 'completed' else 'x' if ss == 'failed' else 'o'
    sdesc = s.get('description', sid)
    if len(sdesc) > 40:
        sdesc = sdesc[:37] + '...'
    print(f'    {mark} {sid}: {sdesc} ({assignee}, {ss})')
" "$f"
        done
    fi
fi

# --- Reverse Pipeline ---
echo ""
echo "--- Reverse Pipeline ---"
echo "  Reverse-tasks pending:  ${REVERSE_TASKS_COUNT}"
echo "  Reverse-results ready:  ${REVERSE_RESULTS_COUNT}"
echo "  Reverse-acknowledged:   ${REVERSE_ACK_COUNT}"

echo ""
echo "Commands:"
echo "  pai-submit.sh <prompt>       Submit a task to Isidore Cloud"
echo "  pai-submit.sh ... --type orchestrate  Submit orchestrated workflow"
echo "  pai-result.sh <task-id>      Read a specific result"
echo "  pai-result.sh --latest       Read the most recent result"
echo "  pai-workflow-status.sh       Check workflow progress"
