#!/bin/bash
# Weekly openclaw doctor auto-fix (safe repairs only)
# Deployed to: ~/scripts/doctor-fix.sh on VPS
# Cron: 0 4 * * 0 (Sundays at 04:00, after PARA Weekly at 03:00)
#
# Runs `openclaw doctor --fix --non-interactive` which applies only safe,
# non-destructive repairs: orphan transcript cleanup, legacy key canonicalization,
# stale service file removal.
#
# Config-level warnings (groupPolicy, allowFrom, etc.) are NOT touched by --fix
# and require manual review — surfaced in the daily-report instead.
#
# TOKEN COST: Zero. Doctor is a local CLI command.

set -euo pipefail

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

LOG="$HOME/.openclaw/logs/doctor-fix.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

log "=== Weekly doctor --fix started ==="

# Capture pre-fix state
BEFORE=$(openclaw doctor 2>&1) || true
log "Pre-fix doctor output:"
echo "$BEFORE" >> "$LOG"

# Check for config-level warnings that --fix won't touch (for logging only)
if echo "$BEFORE" | grep -qi "groupPolicy\|allowFrom\|security"; then
    log "NOTE: Config-level warnings present (requires manual review, --fix skips these)"
fi

# Run safe auto-fix
FIX_OUTPUT=$(openclaw doctor --fix --non-interactive 2>&1) || true
log "Fix output:"
echo "$FIX_OUTPUT" >> "$LOG"

# Capture post-fix state
AFTER=$(openclaw doctor 2>&1) || true
log "Post-fix doctor output:"
echo "$AFTER" >> "$LOG"

log "=== Weekly doctor --fix completed ==="
