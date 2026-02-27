#!/usr/bin/env bash
# pai-reverse-handler: Process reverse-tasks from Isidore Cloud via OpenClaw gateway
# Triggered by pai-reverse-watcher.py when files appear in reverse-tasks/
#
# Reads each JSON file, extracts prompt and metadata, calls `openclaw agent`
# to process the task, writes result to reverse-results/, then moves
# original to reverse-ack/. Atomic and idempotent.
#
# Usage:
#   pai-reverse-handler.sh           Process all pending reverse-tasks
#   pai-reverse-handler.sh --dry-run Show what would be processed (no execution)

set -euo pipefail

REVERSE_TASKS_DIR="/var/lib/pai-pipeline/reverse-tasks"
REVERSE_RESULTS_DIR="/var/lib/pai-pipeline/reverse-results"
REVERSE_ACK_DIR="/var/lib/pai-pipeline/reverse-ack"
LOG_DIR="${HOME}/.openclaw/logs"
LOG_FILE="${LOG_DIR}/pai-reverse.log"
AGENT_TIMEOUT=120

export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/scripts"

# --- Argument parsing ---
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Iseconds): $1" >> "$LOG_FILE"
}

# Process all .json files in reverse-tasks/
shopt -s nullglob
files=("$REVERSE_TASKS_DIR"/*.json)

if [ ${#files[@]} -eq 0 ]; then
    exit 0
fi

for f in "${files[@]}"; do
    fname=$(basename "$f")
    task_id=$(basename "$f" .json)
    log "Processing reverse-task: $fname"

    # Extract fields using python3 (safe JSON parsing)
    task_data=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print(json.dumps({
    'id': d.get('id', ''),
    'prompt': d.get('prompt', ''),
    'priority': d.get('priority', 'normal'),
    'from': d.get('from', 'unknown'),
    'context': d.get('context', {})
}))
" "$f" 2>/dev/null) || {
        log "ERROR: Failed to parse $fname, moving to reverse-ack"
        mv "$f" "$REVERSE_ACK_DIR/$fname"
        continue
    }

    prompt=$(echo "$task_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['prompt'])")
    priority=$(echo "$task_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['priority'])")

    if [ -z "$prompt" ]; then
        log "ERROR: Empty prompt in $fname, moving to reverse-ack"
        # Write error result
        python3 -c "
import json, sys
result = {
    'id': f'result-{sys.argv[1]}',
    'taskId': sys.argv[1],
    'from': 'gregor',
    'to': 'isidore_cloud',
    'status': 'error',
    'error': 'Empty prompt in reverse-task',
    'timestamp': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()
}
with open(sys.argv[2], 'w') as fh:
    json.dump(result, fh, indent=2)
" "$task_id" "$REVERSE_RESULTS_DIR/$fname"
        mv "$f" "$REVERSE_ACK_DIR/$fname"
        continue
    fi

    if $DRY_RUN; then
        log "DRY RUN: Would process $fname (priority=$priority)"
        echo "  WOULD PROCESS: $fname"
        echo "    Prompt: ${prompt:0:80}..."
        continue
    fi

    # Execute via OpenClaw gateway (isolated session per task)
    session_id="reverse-${task_id}"
    log "Executing reverse-task: $fname (priority=$priority, session=$session_id)"
    agent_output=""
    agent_exit=0

    agent_output=$(openclaw agent \
        --local \
        --session-id "$session_id" \
        --message "$prompt" \
        --json \
        --timeout "$AGENT_TIMEOUT" \
        2>>"$LOG_FILE") || agent_exit=$?

    if [ $agent_exit -eq 0 ] && [ -n "$agent_output" ]; then
        # Write structured result
        python3 -c "
import json, sys, os
from datetime import datetime, timezone

task_id = sys.argv[1]
agent_json = sys.argv[2]
result_path = sys.argv[3]
task_file = sys.argv[4]

# Parse agent output (openclaw agent --json format)
try:
    agent_data = json.loads(agent_json)
    # Extract response text from openclaw payloads structure
    payloads = (agent_data.get('result') or {}).get('payloads', [])
    if payloads:
        summary = '\n'.join(p.get('text', '') for p in payloads if p.get('text'))
    else:
        summary = agent_data.get('summary', agent_json[:500])
    meta = (agent_data.get('result') or {}).get('meta', {}).get('agentMeta', {})
    usage = meta.get('usage', {})
    session_id = meta.get('sessionId', agent_data.get('session_id'))
except (json.JSONDecodeError, TypeError):
    summary = agent_json[:500]
    usage = {}
    session_id = None

# Read original task for context
with open(task_file) as fh:
    original = json.load(fh)

result = {
    'id': f'result-{task_id}',
    'taskId': task_id,
    'from': 'gregor',
    'to': original.get('from', 'isidore_cloud'),
    'status': 'completed',
    'result': summary,
    'usage': usage,
    'session_id': session_id,
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'context': original.get('context', {})
}
with open(result_path, 'w') as fh:
    json.dump(result, fh, indent=2)
os.chmod(result_path, 0o660)
" "$task_id" "$agent_output" "$REVERSE_RESULTS_DIR/$fname" "$f"

        log "SUCCESS: $fname completed, result written to reverse-results/"
    else
        # Write error result
        python3 -c "
import json, sys, os
from datetime import datetime, timezone

task_id = sys.argv[1]
exit_code = sys.argv[2]
output = sys.argv[3] if len(sys.argv) > 3 else ''
result_path = sys.argv[4]
task_file = sys.argv[5]

with open(task_file) as fh:
    original = json.load(fh)

result = {
    'id': f'result-{task_id}',
    'taskId': task_id,
    'from': 'gregor',
    'to': original.get('from', 'isidore_cloud'),
    'status': 'error',
    'error': f'openclaw agent exited with code {exit_code}',
    'result': output[:500] if output else None,
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'context': original.get('context', {})
}
with open(result_path, 'w') as fh:
    json.dump(result, fh, indent=2)
os.chmod(result_path, 0o660)
" "$task_id" "$agent_exit" "${agent_output:-}" "$REVERSE_RESULTS_DIR/$fname" "$f"

        log "ERROR: $fname failed (exit $agent_exit), error result written"
    fi

    # Always move to reverse-ack after attempt
    mv "$f" "$REVERSE_ACK_DIR/$fname"
    log "Moved to reverse-ack: $fname"
done

if $DRY_RUN; then
    echo ""
    echo "Dry run complete. No tasks executed."
fi
