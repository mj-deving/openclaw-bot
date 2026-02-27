#!/usr/bin/env bash
# pai-submit: Submit a task to Isidore Cloud via the shared PAI pipeline
# Runs ON VPS as openclaw user — Gregor calls this directly via shell
#
# Usage:
#   pai-submit.sh <prompt>
#   pai-submit.sh <prompt> --project <name> --priority <high|normal|low>
#   pai-submit.sh <prompt> --type <request|orchestrate>
#   pai-submit.sh <prompt> --session <id> --timeout <minutes> --max-turns <n>
#   pai-submit.sh <prompt> --mode sync    (default: async)
#   pai-submit.sh <prompt> --context-file <path>  (attach file content as context)
#
# Examples:
#   pai-submit.sh "Review backup.sh for edge cases"
#   pai-submit.sh "Refactor the auth module" --project openclaw-bot --priority high
#   pai-submit.sh "Decompose and run PRD" --type orchestrate --project openclaw-bot
#   pai-submit.sh "Continue the refactor" --session abc-123 --timeout 60

set -euo pipefail

PIPELINE_DIR="/var/lib/pai-pipeline"
TASKS_DIR="${PIPELINE_DIR}/tasks"

# --- Argument parsing ---
PROMPT=""
PROJECT=""
PRIORITY="normal"
TASK_TYPE="request"
MODE="async"
SESSION_ID=""
TIMEOUT_MINUTES=30
MAX_TURNS=10
CONTEXT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)    PROJECT="$2"; shift 2 ;;
        --priority)   PRIORITY="$2"; shift 2 ;;
        --type)
            if [[ "$2" != "request" && "$2" != "orchestrate" ]]; then
                echo "Error: --type must be 'request' or 'orchestrate'" >&2
                exit 1
            fi
            TASK_TYPE="$2"; shift 2 ;;
        --mode)       MODE="$2"; shift 2 ;;
        --session)    SESSION_ID="$2"; shift 2 ;;
        --timeout)    TIMEOUT_MINUTES="$2"; shift 2 ;;
        --max-turns)  MAX_TURNS="$2"; shift 2 ;;
        --context-file) CONTEXT_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: pai-submit.sh <prompt> [options]"
            echo ""
            echo "Options:"
            echo "  --project <name>       Project name for context"
            echo "  --priority <level>     high, normal (default), or low"
            echo "  --type <type>          request (default) or orchestrate"
            echo "  --mode <mode>          async (default) or sync"
            echo "  --session <id>         Resume an existing Isidore session"
            echo "  --timeout <minutes>    Max execution time (default: 30)"
            echo "  --max-turns <n>        Max agent turns (default: 10)"
            echo "  --context-file <path>  Attach file content as context"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$PROMPT" ]]; then
                PROMPT="$1"
            else
                PROMPT="${PROMPT} $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$PROMPT" ]]; then
    echo "Error: prompt is required" >&2
    echo "Usage: pai-submit.sh <prompt> [options]" >&2
    exit 1
fi

# --- Read context file if provided ---
CONTEXT_CONTENT=""
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        echo "Error: context file not found: $CONTEXT_FILE" >&2
        exit 1
    fi
    CONTEXT_CONTENT=$(cat "$CONTEXT_FILE")
fi

# --- Generate task file using python3 for safe JSON escaping ---
python3 - "$TASKS_DIR" "$PROMPT" "$PROJECT" "$PRIORITY" "$TASK_TYPE" "$MODE" "$SESSION_ID" \
    "$TIMEOUT_MINUTES" "$MAX_TURNS" "$CONTEXT_FILE" "$CONTEXT_CONTENT" << 'PYEOF'
import sys, json, os
from datetime import datetime, timezone

tasks_dir = sys.argv[1]
prompt = sys.argv[2]
project = sys.argv[3] or None
priority = sys.argv[4]
task_type = sys.argv[5]
mode = sys.argv[6]
session_id = sys.argv[7] or None
timeout_minutes = int(sys.argv[8])
max_turns = int(sys.argv[9])
context_file = sys.argv[10] or None
context_content = sys.argv[11] or None

now = datetime.now(timezone.utc)
timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
date_slug = now.strftime("%Y%m%d-%H%M%S")

# Generate short random suffix for uniqueness
import hashlib
rand_suffix = hashlib.sha256(os.urandom(8)).hexdigest()[:8]
task_id = f"{date_slug}-{rand_suffix}"
filename = f"{task_id}.json"

# Build context object
context = {}
if context_file:
    context["file"] = context_file
if context_content:
    context["file_content"] = context_content

task = {
    "id": task_id,
    "from": "gregor",
    "to": "isidore-cloud",
    "timestamp": timestamp,
    "type": task_type,
    "priority": priority,
    "mode": mode,
    "project": project,
    "session_id": session_id,
    "prompt": prompt,
    "context": context,
    "constraints": {
        "max_turns": max_turns,
        "timeout_minutes": timeout_minutes
    }
}

path = os.path.join(tasks_dir, filename)
with open(path, "w") as f:
    json.dump(task, f, indent=2)

# Ensure group-readable/writable (setgid handles group ownership)
os.chmod(path, 0o660)

print(f"Task submitted: {task_id}")
print(f"File: {path}")
print(f"Type: {task_type} | Priority: {priority} | Mode: {mode} | Timeout: {timeout_minutes}m")
if project:
    print(f"Project: {project}")
if session_id:
    print(f"Resume session: {session_id}")
PYEOF
