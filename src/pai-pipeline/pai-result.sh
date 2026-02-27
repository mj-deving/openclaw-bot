#!/usr/bin/env bash
# pai-result: Read task results from the PAI pipeline
# Runs ON VPS as openclaw user — Gregor calls this directly via shell
#
# Usage:
#   pai-result.sh                  List all pending results
#   pai-result.sh <task-id>        Read specific result
#   pai-result.sh <task-id> --ack  Read and acknowledge (move to ack/)
#   pai-result.sh --latest         Read the most recent result
#   pai-result.sh --wait <id>      Poll until result appears (5s interval, 10min max)

set -euo pipefail

PIPELINE_DIR="/var/lib/pai-pipeline"
RESULTS_DIR="${PIPELINE_DIR}/results"
ACK_DIR="${PIPELINE_DIR}/ack"

TASK_ID=""
ACK=false
LATEST=false
WAIT=false
WAIT_TIMEOUT=600  # 10 minutes

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ack)     ACK=true; shift ;;
        --latest)  LATEST=true; shift ;;
        --wait)    WAIT=true; TASK_ID="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: pai-result.sh [task-id] [options]"
            echo ""
            echo "Commands:"
            echo "  (no args)          List all pending results"
            echo "  <task-id>          Read specific result"
            echo "  --latest           Read the most recent result"
            echo "  --wait <task-id>   Poll until result appears (5s interval)"
            echo ""
            echo "Options:"
            echo "  --ack              Acknowledge after reading (move to ack/)"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            TASK_ID="$1"; shift ;;
    esac
done

# --- Wait mode: poll for result ---
if $WAIT; then
    if [[ -z "$TASK_ID" ]]; then
        echo "Error: --wait requires a task ID" >&2
        exit 1
    fi

    ELAPSED=0
    echo "Waiting for result: ${TASK_ID}..."
    while [[ $ELAPSED -lt $WAIT_TIMEOUT ]]; do
        if [[ -f "${RESULTS_DIR}/${TASK_ID}.json" ]]; then
            echo ""
            echo "=== Result Ready ==="
            python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    r = json.load(f)
task_id = r.get('taskId', r.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0]))
print(f\"Task:    {task_id}\")
print(f\"Status:  {r.get('status', 'unknown')}\")
print(f\"Time:    {r.get('timestamp', 'unknown')}\")
if r.get('token_usage'):
    u = r['token_usage']
    print(f\"Tokens:  {u.get('input', 0)} in / {u.get('output', 0)} out\")
if r.get('session_id'):
    print(f\"Session: {r['session_id']}\")
print()
print('--- Summary ---')
print(r.get('summary', r.get('result', '(no summary)')))
if r.get('artifacts'):
    print()
    print('--- Artifacts ---')
    for a in r['artifacts']:
        print(f'  {a}')
if r.get('error'):
    print()
    print('--- Error ---')
    print(r['error'])
" "${RESULTS_DIR}/${TASK_ID}.json"
            exit 0
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        # Progress dot every 30 seconds
        if [[ $((ELAPSED % 30)) -eq 0 ]]; then
            echo "  ... ${ELAPSED}s elapsed"
        fi
    done

    echo "Timeout: no result after ${WAIT_TIMEOUT}s" >&2
    exit 1
fi

# --- Latest mode ---
if $LATEST; then
    LATEST_FILE=$(ls -1t "${RESULTS_DIR}/"*.json 2>/dev/null | head -1 || true)
    if [[ -z "$LATEST_FILE" ]]; then
        echo "No results available."
        exit 0
    fi
    TASK_ID=$(basename "$LATEST_FILE" .json)
fi

# --- List mode (no task ID) ---
if [[ -z "$TASK_ID" ]]; then
    FILES=$(ls -1t "${RESULTS_DIR}/"*.json 2>/dev/null || true)
    if [[ -z "$FILES" ]]; then
        echo "No pending results."
        exit 0
    fi

    echo "=== Pending Results ==="
    echo ""
    while IFS= read -r filepath; do
        python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    r = json.load(f)
task_id = r.get('taskId', r.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0]))
status = r.get('status', '?')
summary = r.get('summary', r.get('result', '(no summary)'))
if len(summary) > 80:
    summary = summary[:77] + '...'
print(f\"  {task_id}  [{status}]  {summary}\")
" "$filepath"
    done <<< "$FILES"
    echo ""
    echo "Total: $(echo "$FILES" | wc -l) result(s)"
    echo "Use: pai-result.sh <task-id> to read full result"
    exit 0
fi

# --- Read specific result ---
RESULT_FILE="${RESULTS_DIR}/${TASK_ID}.json"

if [[ ! -f "$RESULT_FILE" ]]; then
    # Prefix fallback: find results whose filename starts with the given ID
    PREFIX_MATCHES=()
    while IFS= read -r -d '' match; do
        PREFIX_MATCHES+=("$match")
    done < <(find "$RESULTS_DIR" -maxdepth 1 -name "${TASK_ID}*.json" -print0 2>/dev/null | sort -z)

    if [[ ${#PREFIX_MATCHES[@]} -eq 1 ]]; then
        RESULT_FILE="${PREFIX_MATCHES[0]}"
        TASK_ID=$(basename "$RESULT_FILE" .json)
        echo "(Exact match not found — using prefix match: ${TASK_ID})"
        echo ""
    elif [[ ${#PREFIX_MATCHES[@]} -gt 1 ]]; then
        echo "No exact match for '${TASK_ID}', but found ${#PREFIX_MATCHES[@]} prefix matches:" >&2
        for m in "${PREFIX_MATCHES[@]}"; do
            echo "  $(basename "$m" .json)" >&2
        done
        echo "Specify the full task ID." >&2
        exit 1
    else
        echo "No result found for task: ${TASK_ID}" >&2
        echo "Task may still be processing. Use: pai-result.sh --wait ${TASK_ID}" >&2
        exit 1
    fi
fi

python3 -c "
import json, sys, os
with open(sys.argv[1]) as f:
    r = json.load(f)
task_id = r.get('taskId', r.get('id', os.path.splitext(os.path.basename(sys.argv[1]))[0]))
print(f\"Task:    {task_id}\")
print(f\"Status:  {r.get('status', 'unknown')}\")
print(f\"Time:    {r.get('timestamp', 'unknown')}\")
if r.get('token_usage'):
    u = r['token_usage']
    print(f\"Tokens:  {u.get('input', 0)} in / {u.get('output', 0)} out\")
if r.get('session_id'):
    print(f\"Session: {r['session_id']}  (use --session to resume)\")
print()
print('--- Summary ---')
print(r.get('summary', r.get('result', '(no summary)')))
if r.get('artifacts'):
    print()
    print('--- Artifacts ---')
    for a in r['artifacts']:
        print(f'  {a}')
if r.get('error'):
    print()
    print('--- Error ---')
    print(r['error'])
" "$RESULT_FILE"

# --- Acknowledge if requested ---
if $ACK; then
    mv "$RESULT_FILE" "${ACK_DIR}/$(basename "$RESULT_FILE")"
    echo ""
    echo "(Acknowledged — moved to ack/)"
fi
