#!/usr/bin/env bash
# pipeline-send: Send a message to bot's inbox (non-blocking)
# Usage: ./send.sh <type> <subject> <body> [priority]
# Types: task, query, notification
# Example: ./send.sh task "Check Lattice EXP" "Report your current EXP level"

set -euo pipefail

PIPELINE_DIR="/home/openclaw/.openclaw/pipeline"
SSH_HOST="vps"

TYPE="${1:?Usage: send.sh <type> <subject> <body> [priority]}"
SUBJECT="${2:?Missing subject}"
BODY="${3:?Missing body}"
PRIORITY="${4:-normal}"

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
ID="${TIMESTAMP}-$(head -c 4 /dev/urandom | xxd -p)"
SLUG=$(echo "$SUBJECT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 30)
FILENAME="${TIMESTAMP}-${TYPE}-${SLUG}.json"

MESSAGE=$(cat <<EOF
{
  "id": "${ID}",
  "from": "local-assistant",
  "to": "bot",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "type": "${TYPE}",
  "subject": "${SUBJECT}",
  "body": "${BODY}",
  "priority": "${PRIORITY}",
  "replyTo": null
}
EOF
)

ssh "$SSH_HOST" "cat > '${PIPELINE_DIR}/inbox/${FILENAME}'" <<< "$MESSAGE"

echo "Sent: ${FILENAME}"
echo "ID: ${ID}"
