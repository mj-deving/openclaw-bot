#!/bin/bash
# OpenClaw gateway health check with conservative restart
# Catches zombie states where process is "running" but gateway is unresponsive
# Deployed to: ~/scripts/health-check.sh on VPS
# Cron: */10 * * * * (every 10 minutes)
#
# INTERVAL RATIONALE (10 minutes):
#   - systemd Restart=on-failure already catches crashes INSTANTLY (RestartSec=10)
#   - This script catches a DIFFERENT failure: process alive but gateway unresponsive (zombie)
#   - Zombie states are rare — 10 min detection is fast enough
#   - CONSERVATIVE RESTART: requires 3 CONSECUTIVE failures before restart (= 30 min window)
#     Why? Every restart costs initialization tokens (system prompt, memory warmup).
#     With the bot already using high token volume, we avoid unnecessary restart churn.
#   - A single transient /health failure (network hiccup, momentary load) does NOT trigger restart.
#
# TOKEN COST: Zero. Pure system commands only. The restart itself costs init tokens,
#   but the 3-consecutive-failure gate minimizes false-positive restarts.

set -euo pipefail

LOG="$HOME/.openclaw/logs/health-check.log"
STATE_DIR="$HOME/.openclaw/state"
FAIL_COUNT_FILE="$STATE_DIR/health-fail-count"
RESTART_THRESHOLD=3
HEALTH_URL="http://127.0.0.1:18789/health"

mkdir -p "$(dirname "$LOG")" "$STATE_DIR"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

get_fail_count() {
    if [ -f "$FAIL_COUNT_FILE" ]; then
        cat "$FAIL_COUNT_FILE"
    else
        echo 0
    fi
}

set_fail_count() {
    echo "$1" > "$FAIL_COUNT_FILE"
}

# Check 1: Is the systemd service active?
if ! systemctl is-active --quiet openclaw 2>/dev/null; then
    log "Service not active. Starting openclaw..."
    systemctl start openclaw 2>/dev/null || true
    set_fail_count 0
    log "Service start attempted."
    exit 0
fi

# Check 2: Does the gateway respond?
# Use short timeout (5s) to avoid hanging. Accept any HTTP response as "alive".
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "000" ]; then
    # No response at all — connection refused or timeout
    FAILS=$(get_fail_count)
    FAILS=$((FAILS + 1))
    set_fail_count "$FAILS"
    log "Health check failed (no response). Consecutive failures: $FAILS/$RESTART_THRESHOLD"

    if [ "$FAILS" -ge "$RESTART_THRESHOLD" ]; then
        log "RESTART: $FAILS consecutive health failures. Restarting openclaw..."
        systemctl restart openclaw 2>/dev/null || true
        set_fail_count 0
        sleep 5
        # Verify binding after restart
        if ss -tlnp 2>/dev/null | grep -q '0\.0\.0\.0:18789'; then
            log "CRITICAL: Post-restart binding is 0.0.0.0! Stopping."
            systemctl stop openclaw 2>/dev/null || true
        else
            log "Post-restart binding verified OK (loopback)."
        fi
    fi
else
    # Got an HTTP response — gateway is alive (even non-200 means process is responding)
    PREV_FAILS=$(get_fail_count)
    if [ "$PREV_FAILS" -gt 0 ]; then
        log "Health check recovered after $PREV_FAILS failure(s). Resetting counter."
    fi
    set_fail_count 0
fi
