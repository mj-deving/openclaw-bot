#!/usr/bin/env bash
# audit.sh: Pull daily reports and delegation info from VPS
# Usage: ./audit.sh <mode> [args]
# Modes:
#   --today              Show today's report
#   --yesterday          Show yesterday's report
#   --date YYYY-MM-DD    Show report for specific date
#   --week               List last 7 report filenames
#   --delegations        Show pending delegations (pipeline outbox + recent reports)
#   --all                List all report filenames

set -euo pipefail

SSH_HOST="vps"
REPORTS_DIR="/home/openclaw/.openclaw/reports"
PIPELINE_DIR="/home/openclaw/.openclaw/pipeline"

usage() {
    echo "Usage: $0 <mode> [args]"
    echo "  --today              Today's report"
    echo "  --yesterday          Yesterday's report"
    echo "  --date YYYY-MM-DD    Report for specific date"
    echo "  --week               Last 7 report filenames"
    echo "  --delegations        Pending delegations"
    echo "  --all                All report filenames"
    exit 1
}

[ $# -lt 1 ] && usage

case "$1" in
    --today)
        DATE=$(date +%Y-%m-%d)
        FILE="${REPORTS_DIR}/${DATE}.md"
        ssh "$SSH_HOST" "cat '$FILE' 2>/dev/null || echo 'No report for $DATE'"
        ;;
    --yesterday)
        DATE=$(date -d yesterday +%Y-%m-%d)
        FILE="${REPORTS_DIR}/${DATE}.md"
        ssh "$SSH_HOST" "cat '$FILE' 2>/dev/null || echo 'No report for $DATE'"
        ;;
    --date)
        [ $# -lt 2 ] && { echo "Error: --date requires YYYY-MM-DD argument"; exit 1; }
        DATE="$2"
        # Validate date format
        if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            echo "Error: Date must be YYYY-MM-DD format"
            exit 1
        fi
        FILE="${REPORTS_DIR}/${DATE}.md"
        ssh "$SSH_HOST" "cat '$FILE' 2>/dev/null || echo 'No report for $DATE'"
        ;;
    --week)
        echo "Reports from last 7 days:"
        ssh "$SSH_HOST" "ls -1t '$REPORTS_DIR'/*.md 2>/dev/null | head -7 || echo '  (none)'"
        ;;
    --delegations)
        echo "=== Pipeline Outbox (pending delegations) ==="
        ssh "$SSH_HOST" "for f in '$PIPELINE_DIR'/outbox/*.json; do [ -f \"\$f\" ] && cat \"\$f\" && echo; done 2>/dev/null || echo '  (none)'"
        echo ""
        echo "=== Delegation sections from recent reports ==="
        ssh "$SSH_HOST" "for f in \$(ls -1t '$REPORTS_DIR'/*.md 2>/dev/null | head -7); do echo \"--- \$(basename \$f) ---\"; sed -n '/^## Delegation/,/^## /p' \"\$f\" 2>/dev/null | head -20; echo; done 2>/dev/null || echo '  (none)'"
        ;;
    --all)
        echo "All reports:"
        ssh "$SSH_HOST" "ls -1t '$REPORTS_DIR'/*.md 2>/dev/null || echo '  (none)'"
        ;;
    *)
        usage
        ;;
esac
