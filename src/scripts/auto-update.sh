#!/bin/bash
# OpenClaw auto-update with security audit
# Updates OpenClaw, restarts if version changed, always runs security audit
# Deployed to: ~/scripts/auto-update.sh on VPS
# Cron: 0 4 * * 0 (Sunday 4 AM)
#
# INTERVAL RATIONALE (weekly):
#   - OpenClaw has had real CVEs (CVSS 8.8). Staying on old versions is risky.
#   - But updating too frequently risks instability on a production bot.
#   - Weekly (Sunday 4 AM) balances security freshness vs. stability.
#   - Security audit runs EVERY week even if no update occurred.
#   - Post-update: binding verification runs to catch any regression.
#
# TOKEN COST: Zero for the script itself. If version changes and service restarts,
#   The bot pays the normal initialization token cost once.

set -euo pipefail

LOG="$HOME/.openclaw/logs/update.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

log "=== Auto-update starting ==="

# Record current version
CURRENT_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
log "Current version: $CURRENT_VERSION"

# Stop gateway BEFORE npm update to avoid in-place dist/ overwrite crash (issue #54790)
# npm install -g overwrites modules while gateway is running, causing hash mismatches
log "Stopping gateway for safe update..."
systemctl stop openclaw 2>/dev/null || true
sleep 3

# Update OpenClaw
npm update -g openclaw >> "$LOG" 2>&1 || {
    log "WARNING: npm update failed"
}

# Check new version
NEW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
log "Post-update version: $NEW_VERSION"

# Always restart (gateway was stopped for update)
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    log "Version changed: $CURRENT_VERSION → $NEW_VERSION. Starting service..."
else
    log "No version change. Restarting service..."
fi
systemctl restart openclaw 2>/dev/null || true
sleep 10

# Version changed — run extra verification
if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then

    # Verify binding after restart (critical — updates could regress the binding behavior)
    if [ -x "$HOME/scripts/verify-binding.sh" ]; then
        "$HOME/scripts/verify-binding.sh"
        log "Post-update binding verification complete."
    else
        log "WARNING: verify-binding.sh not found. Manual binding check needed."
        if ss -tlnp 2>/dev/null | grep ':18789' | grep -q '0.0.0.0'; then
            log "CRITICAL: Post-update binding is 0.0.0.0! Stopping."
            systemctl stop openclaw 2>/dev/null || true
        fi
    fi
else
    log "No version change."
fi

# Always run security audit (weekly baseline)
log "Running security audit..."
openclaw security audit --deep >> "$LOG" 2>&1 || {
    log "WARNING: Security audit failed or returned non-zero"
}

log "=== Auto-update complete ==="
