#!/usr/bin/env bash
# pipeline-status: Check pipeline state
# Usage: ./status.sh

set -euo pipefail

PIPELINE_DIR="/home/openclaw/.openclaw/pipeline"
SSH_HOST="vps"

echo "=== Pipeline Status ==="
ssh "$SSH_HOST" "
    INBOX=\$(ls -1 '${PIPELINE_DIR}/inbox/' 2>/dev/null | grep -c '.json\$' || true)
    INBOX=\${INBOX:-0}
    OUTBOX=\$(ls -1 '${PIPELINE_DIR}/outbox/' 2>/dev/null | grep -c '.json\$' || true)
    OUTBOX=\${OUTBOX:-0}
    ACK=\$(ls -1 '${PIPELINE_DIR}/ack/' 2>/dev/null | grep -c '.json\$' || true)
    ACK=\${ACK:-0}
    echo \"  Inbox (pending for Gregor): \${INBOX}\"
    echo \"  Outbox (pending for Isidore): \${OUTBOX}\"
    echo \"  Acknowledged: \${ACK}\"
    echo \"\"
    if [ \"\${INBOX}\" -gt 0 ]; then
        echo \"--- Inbox ---\"
        ls -1t '${PIPELINE_DIR}/inbox/' | grep '.json$' | head -5
    fi
    if [ \"\${OUTBOX}\" -gt 0 ]; then
        echo \"--- Outbox ---\"
        ls -1t '${PIPELINE_DIR}/outbox/' | grep '.json$' | head -5
    fi
"
