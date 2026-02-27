#!/usr/bin/env bash
# pai-escalation-submit: Process files in escalate/ and submit to PAI pipeline
# Triggered by systemd path unit when files appear in escalate/
#
# Reads each JSON file, extracts body and priority, calls pai-submit.sh,
# then moves the original to ack/. Atomic and idempotent.

set -euo pipefail

ESCALATE_DIR="${HOME}/.openclaw/pipeline/escalate"
ACK_DIR="${HOME}/.openclaw/pipeline/ack"
LOG_DIR="${HOME}/.openclaw/logs"
LOG_FILE="${LOG_DIR}/pai-escalation.log"
PAI_SUBMIT="${HOME}/scripts/pai-submit.sh"

export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/scripts"

log() {
    mkdir -p "$LOG_DIR"
    echo "$(date -Iseconds): $1" >> "$LOG_FILE"
}

# Process all .json files in escalate/
shopt -s nullglob
files=("$ESCALATE_DIR"/*.json)

if [ ${#files[@]} -eq 0 ]; then
    exit 0
fi

for f in "${files[@]}"; do
    fname=$(basename "$f")
    log "Processing: $fname"

    # Extract fields using python3 (safe JSON parsing)
    body=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print(d.get('body', d.get('subject', '')))
" "$f" 2>/dev/null) || {
        log "ERROR: Failed to parse $fname, moving to ack"
        mv "$f" "$ACK_DIR/$fname"
        continue
    }

    priority=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print(d.get('priority', 'normal'))
" "$f" 2>/dev/null) || priority="normal"

    project=$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print(d.get('project', 'openclaw-bot'))
" "$f" 2>/dev/null) || project="openclaw-bot"

    if [ -z "$body" ]; then
        log "ERROR: Empty body in $fname, moving to ack"
        mv "$f" "$ACK_DIR/$fname"
        continue
    fi

    # Submit to PAI pipeline
    log "Escalating: $fname (priority=$priority, project=$project)"
    if "$PAI_SUBMIT" "$body" --project "$project" --priority "$priority" 2>>"$LOG_FILE"; then
        log "SUCCESS: $fname escalated to PAI pipeline"
    else
        log "ERROR: pai-submit.sh failed for $fname (exit $?)"
    fi

    # Always move to ack after attempt
    mv "$f" "$ACK_DIR/$fname"
    log "Moved to ack: $fname"
done
