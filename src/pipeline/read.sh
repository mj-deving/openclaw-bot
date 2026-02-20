#!/usr/bin/env bash
# pipeline-read: Read messages from bot's outbox
# Usage: ./read.sh [--peek] [--clear]
# --peek: just list messages without reading
# --clear: move read messages to ack/ after displaying

set -euo pipefail

PIPELINE_DIR="/home/openclaw/.openclaw/pipeline"
SSH_HOST="vps"

MODE="read"
[[ "${1:-}" == "--peek" ]] && MODE="peek"
[[ "${1:-}" == "--clear" ]] && MODE="clear"

# List outbox
FILES=$(ssh "$SSH_HOST" "ls -1 '${PIPELINE_DIR}/outbox/' 2>/dev/null | grep '.json$'" || true)

if [[ -z "$FILES" ]]; then
    echo "No messages from bot."
    exit 0
fi

echo "=== Messages from Bot ==="
echo ""

while IFS= read -r file; do
    if [[ "$MODE" == "peek" ]]; then
        echo "  - $file"
    else
        echo "--- ${file} ---"
        ssh "$SSH_HOST" "cat '${PIPELINE_DIR}/outbox/${file}'"
        echo ""

        if [[ "$MODE" == "clear" ]]; then
            ssh "$SSH_HOST" "mv '${PIPELINE_DIR}/outbox/${file}' '${PIPELINE_DIR}/ack/${file}'"
            echo "  (moved to ack/)"
        fi
    fi
done <<< "$FILES"

echo ""
echo "Total: $(echo "$FILES" | wc -l) message(s)"
