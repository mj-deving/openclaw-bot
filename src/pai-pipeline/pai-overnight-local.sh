#!/usr/bin/env bash
# pai-overnight-local: Local helper for overnight PRD queue
# Runs on LOCAL machine — transfers PRDs to VPS and triggers overnight queue
#
# Usage:
#   pai-overnight-local.sh plan1.md plan2.md [--project P] [--timeout M] [--max-turns N]
#   pai-overnight-local.sh --status [--json]
#   pai-overnight-local.sh --report [--json]
#   pai-overnight-local.sh --cancel
#   pai-overnight-local.sh --resume
#
# Examples:
#   pai-overnight-local.sh ~/.claude/MEMORY/WORK/*/PRD-*.md --project openclaw-bot
#   pai-overnight-local.sh --status
#   pai-overnight-local.sh --report --json

set -euo pipefail

VPS_HOST="vps"
VPS_STAGING="/var/lib/pai-pipeline/overnight/staging"
VPS_SCRIPT="~/scripts/pai-overnight.sh"

# --- Argument parsing ---
MODE="queue"  # queue, status, report, cancel, resume
PRD_FILES=()
PROJECT=""
TIMEOUT=""
MAX_TURNS=""
JSON_FLAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)     MODE="status"; shift ;;
        --report)     MODE="report"; shift ;;
        --cancel)     MODE="cancel"; shift ;;
        --resume)     MODE="resume"; shift ;;
        --project)    PROJECT="$2"; shift 2 ;;
        --timeout)    TIMEOUT="$2"; shift 2 ;;
        --max-turns)  MAX_TURNS="$2"; shift 2 ;;
        --json)       JSON_FLAG="--json"; shift ;;
        --help|-h)
            echo "Usage: pai-overnight-local.sh [PRD files...] [options]"
            echo ""
            echo "Queue mode (default):"
            echo "  pai-overnight-local.sh plan1.md plan2.md [--project P] [--timeout M] [--max-turns N]"
            echo ""
            echo "Proxy commands:"
            echo "  --status [--json]    Show queue progress"
            echo "  --report [--json]    Show morning report"
            echo "  --cancel             Cancel active queue"
            echo "  --resume             Resume failed/stuck item"
            echo ""
            echo "Options:"
            echo "  --project <name>     Project name (default: openclaw-bot)"
            echo "  --timeout <minutes>  Per-task timeout (default: 120)"
            echo "  --max-turns <n>      Per-task max turns (default: 50)"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            PRD_FILES+=("$1")
            shift
            ;;
    esac
done

# --- Proxy commands ---
case "$MODE" in
    status)
        ssh "$VPS_HOST" "$VPS_SCRIPT status $JSON_FLAG"
        exit 0
        ;;
    report)
        ssh "$VPS_HOST" "$VPS_SCRIPT report $JSON_FLAG"
        exit 0
        ;;
    cancel)
        ssh "$VPS_HOST" "$VPS_SCRIPT cancel"
        exit 0
        ;;
    resume)
        ssh "$VPS_HOST" "$VPS_SCRIPT resume"
        exit 0
        ;;
esac

# --- Queue mode: transfer PRDs and trigger init ---
if [[ ${#PRD_FILES[@]} -eq 0 ]]; then
    echo "Error: at least one PRD file is required" >&2
    echo "Usage: pai-overnight-local.sh plan1.md plan2.md [options]" >&2
    exit 1
fi

# Validate PRD files exist locally
for f in "${PRD_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: file not found: $f" >&2
        exit 1
    fi
done

echo "Preparing overnight queue with ${#PRD_FILES[@]} PRD(s)..."

# Clear staging directory on VPS
ssh "$VPS_HOST" "rm -f $VPS_STAGING/*.md"

# Transfer PRD files to VPS staging
scp "${PRD_FILES[@]}" "${VPS_HOST}:${VPS_STAGING}/"
echo "Transferred ${#PRD_FILES[@]} PRD(s) to VPS staging"

# Build init command with options
INIT_OPTS=""
[[ -n "$PROJECT" ]] && INIT_OPTS="$INIT_OPTS --project $PROJECT"
[[ -n "$TIMEOUT" ]] && INIT_OPTS="$INIT_OPTS --timeout $TIMEOUT"
[[ -n "$MAX_TURNS" ]] && INIT_OPTS="$INIT_OPTS --max-turns $MAX_TURNS"

# Trigger init on VPS
echo "Initializing queue..."
ssh "$VPS_HOST" "$VPS_SCRIPT init $INIT_OPTS"

echo ""
echo "Queue started. The advance cron (*/5) will process items sequentially."
echo "Check progress: pai-overnight-local.sh --status"
echo "Morning report: pai-overnight-local.sh --report"
