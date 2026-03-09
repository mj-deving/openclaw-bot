#!/bin/bash
# OpenClaw gateway health check with self-healing
# Deployed to: ~/scripts/health-check.sh on VPS
# Cron: */5 * * * * (every 5 minutes)
#
# WHAT THIS CATCHES:
#   Tier 1 — Crashed/stopped service (systemd handles instant restarts; this is the fallback)
#   Tier 2 — Zombie gateway (process alive but HTTP unresponsive, 3 consecutive failures)
#   Tier 3 — Silent polling death (Telegram polling stopped, 3 consecutive failures)
#   Tier 4 — Memory leak (VmRSS > 2GB sustained, 3 consecutive checks)
#
# SAFETY:
#   - flock ensures single instance (overlapping cron runs exit immediately)
#   - Exponential backoff prevents restart storms (10/20/40/80/160 min cooldown)
#   - Daily budget caps restarts at 5/24h — beyond that, logs CRITICAL and stops
#   - Calls ops-playbook.sh diagnose --json before every restart for post-mortem context
#   - Atomic state file writes (write .tmp then mv) prevent corruption
#
# TOKEN COST: Zero. Pure system commands only. Restarts cost ~$0.01-0.05 in init tokens,
#   capped at 5/day by daily budget.

set -euo pipefail

# --- Concurrency guard ---
# flock ensures only one instance runs at a time. If another cron fires while
# we're still running, it exits immediately rather than stacking up.
LOCK_FILE="$HOME/.openclaw/state/health-check.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    exit 0  # Another instance is running — silently exit
fi

# --- Config ---
LOG="$HOME/.openclaw/logs/health-check.log"
STATE_DIR="$HOME/.openclaw/state"
HEALTH_URL="http://127.0.0.1:18789/health"
RESTART_THRESHOLD=3          # Consecutive failures before restart
MEMORY_WARN_KB=$((1536*1024))  # 1.5 GB in KB
MEMORY_CRIT_KB=$((2048*1024))  # 2.0 GB in KB
MEMORY_RESTART_THRESHOLD=3   # Consecutive high-RSS checks before restart
POLLING_RESTART_THRESHOLD=3  # Consecutive polling-dead checks before restart
POLLING_WINDOW_MIN=15        # Minutes of silence = polling dead
MAX_DAILY_RESTARTS=5
BACKOFF_CAP=16               # Max backoff multiplier (16 * 10 = 160 min)
BACKOFF_RESET_SECONDS=3600   # 60 min healthy = reset backoff
BASE_COOLDOWN_MIN=10         # Base cooldown in minutes

# State files (auto-created)
FAIL_COUNT_FILE="$STATE_DIR/health-fail-count"
POLLING_FAIL_FILE="$STATE_DIR/polling-fail-count"
MEMORY_WARN_FILE="$STATE_DIR/memory-warn-count"
BACKOFF_LEVEL_FILE="$STATE_DIR/health-backoff-level"
LAST_RESTART_FILE="$STATE_DIR/health-last-restart"
FIRST_OK_FILE="$STATE_DIR/health-first-ok-after-restart"
RESTART_LOG_FILE="$STATE_DIR/health-restart-log"

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
mkdir -p "$(dirname "$LOG")" "$STATE_DIR"

# --- Helpers ---
log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

# Atomic state file write: write to .tmp then mv (prevents partial reads)
state_write() {
    local file="$1" value="$2"
    echo "$value" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

state_read() {
    local file="$1" default="${2:-0}"
    if [ -f "$file" ]; then
        cat "$file"
    else
        echo "$default"
    fi
}

# --- Backoff & Budget ---

get_backoff_level() {
    state_read "$BACKOFF_LEVEL_FILE" 1
}

get_cooldown_minutes() {
    local level
    level=$(get_backoff_level)
    echo $((level * BASE_COOLDOWN_MIN))
}

# Check if we're still in cooldown after last restart
in_cooldown() {
    local last_restart cooldown_min now elapsed_min
    last_restart=$(state_read "$LAST_RESTART_FILE" 0)
    [ "$last_restart" -eq 0 ] && return 1  # No restart yet — not in cooldown
    cooldown_min=$(get_cooldown_minutes)
    now=$(date +%s)
    elapsed_min=$(( (now - last_restart) / 60 ))
    [ "$elapsed_min" -lt "$cooldown_min" ]
}

# Check daily restart budget (max 5 in 24 hours)
daily_restarts_exceeded() {
    [ ! -f "$RESTART_LOG_FILE" ] && return 1
    local count cutoff
    cutoff=$(date -d '24 hours ago' +%s 2>/dev/null || date -v-24H +%s 2>/dev/null || echo 0)
    count=$(awk -v cutoff="$cutoff" -F'|' '$1 >= cutoff { n++ } END { print n+0 }' "$RESTART_LOG_FILE")
    [ "$count" -ge "$MAX_DAILY_RESTARTS" ]
}

# Bump backoff level after a restart (doubles each time, capped at BACKOFF_CAP)
bump_backoff() {
    local level
    level=$(get_backoff_level)
    level=$((level * 2))
    [ "$level" -gt "$BACKOFF_CAP" ] && level=$BACKOFF_CAP
    state_write "$BACKOFF_LEVEL_FILE" "$level"
}

# Check if backoff should reset: 60 min of continuous healthy checks after last restart
maybe_reset_backoff() {
    local last_restart first_ok now
    last_restart=$(state_read "$LAST_RESTART_FILE" 0)
    [ "$last_restart" -eq 0 ] && return  # Never restarted — nothing to reset
    first_ok=$(state_read "$FIRST_OK_FILE" 0)
    [ "$first_ok" -eq 0 ] && return  # No healthy check after restart yet
    now=$(date +%s)
    if [ $((now - first_ok)) -ge "$BACKOFF_RESET_SECONDS" ]; then
        local level
        level=$(get_backoff_level)
        if [ "$level" -gt 1 ]; then
            log "Backoff reset: ${BACKOFF_RESET_SECONDS}s of healthy checks after last restart. Level $level → 1"
            state_write "$BACKOFF_LEVEL_FILE" 1
        fi
    fi
}

# Record a healthy check (for backoff reset tracking)
record_healthy() {
    local last_restart first_ok now
    last_restart=$(state_read "$LAST_RESTART_FILE" 0)
    [ "$last_restart" -eq 0 ] && return  # Never restarted — no tracking needed
    first_ok=$(state_read "$FIRST_OK_FILE" 0)
    now=$(date +%s)
    if [ "$first_ok" -eq 0 ] || [ "$first_ok" -lt "$last_restart" ]; then
        # First healthy check after the most recent restart
        state_write "$FIRST_OK_FILE" "$now"
    fi
    maybe_reset_backoff
}

# --- Restart with safeguards ---
do_restart() {
    local reason="$1"
    local level cooldown

    # Check daily budget
    if daily_restarts_exceeded; then
        log "CRITICAL: Daily restart budget exhausted ($MAX_DAILY_RESTARTS in 24h). NOT restarting. Reason: $reason"
        return 1
    fi

    # Check cooldown
    if in_cooldown; then
        cooldown=$(get_cooldown_minutes)
        log "In cooldown (${cooldown}m). Skipping restart. Reason: $reason"
        return 1
    fi

    level=$(get_backoff_level)

    # Run ops-playbook diagnosis before restart (if available)
    local playbook="$HOME/scripts/ops-playbook.sh"
    if [ -x "$playbook" ]; then
        log "Pre-restart diagnosis (backoff level $level):"
        "$playbook" diagnose --json >> "$LOG" 2>&1 || true
    fi

    log "RESTART: $reason (backoff level $level, cooldown $(get_cooldown_minutes)m)"
    sudo systemctl restart openclaw 2>/dev/null || true

    # Record restart
    local now
    now=$(date +%s)
    state_write "$LAST_RESTART_FILE" "$now"
    state_write "$FIRST_OK_FILE" 0  # Reset healthy tracking
    bump_backoff

    # Append to restart log (for daily-report cron)
    echo "${now}|${reason}|${level}" >> "$RESTART_LOG_FILE"

    sleep 5

    # Verify binding after restart (security check)
    if ss -tlnp 2>/dev/null | grep -q '0\.0\.0\.0:18789'; then
        log "CRITICAL: Post-restart binding is 0.0.0.0! Stopping."
        sudo systemctl stop openclaw 2>/dev/null || true
    else
        log "Post-restart binding verified OK (loopback)."
    fi
}

# --- Tier 1: Service status ---
if ! systemctl is-active --quiet openclaw 2>/dev/null; then
    log "Service not active. Starting openclaw..."
    sudo systemctl start openclaw 2>/dev/null || true
    state_write "$FAIL_COUNT_FILE" 0
    log "Service start attempted."
    exit 0
fi

# --- Track overall health for backoff reset ---
ALL_HEALTHY=true

# --- Tier 2: Gateway HTTP response ---
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 5 "$HEALTH_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "000" ]; then
    ALL_HEALTHY=false
    FAILS=$(state_read "$FAIL_COUNT_FILE")
    FAILS=$((FAILS + 1))
    state_write "$FAIL_COUNT_FILE" "$FAILS"
    log "Health check failed (no response). Consecutive failures: $FAILS/$RESTART_THRESHOLD"

    if [ "$FAILS" -ge "$RESTART_THRESHOLD" ]; then
        do_restart "Gateway unresponsive ($FAILS consecutive failures)" || true
        state_write "$FAIL_COUNT_FILE" 0
    fi
else
    PREV_FAILS=$(state_read "$FAIL_COUNT_FILE")
    if [ "$PREV_FAILS" -gt 0 ]; then
        log "Health check recovered after $PREV_FAILS failure(s). Resetting counter."
    fi
    state_write "$FAIL_COUNT_FILE" 0
fi

# --- Tier 3: Polling liveness ---
# Only check if rotating-heartbeat cron exists (prevents false positives on quiet bots).
# If no heartbeat cron is registered, the bot may be legitimately idle — skip this check.
HEARTBEAT_EXISTS=false
if command -v openclaw &>/dev/null; then
    if openclaw cron list 2>/dev/null | grep -qi "heartbeat"; then
        HEARTBEAT_EXISTS=true
    fi
fi

if [ "$HEARTBEAT_EXISTS" = "true" ]; then
    # Check journal for Telegram polling activity in the last POLLING_WINDOW_MIN minutes
    POLLING_ACTIVE=false
    if journalctl -u openclaw --since "${POLLING_WINDOW_MIN} minutes ago" --no-pager 2>/dev/null \
        | grep -qiE "(telegram.*poll|getUpdates|inbound message)"; then
        POLLING_ACTIVE=true
    fi

    if [ "$POLLING_ACTIVE" = "false" ]; then
        # Check if heartbeat cron actually fired recently — if not, result is inconclusive
        HEARTBEAT_RECENT=false
        if journalctl -u openclaw --since "${POLLING_WINDOW_MIN} minutes ago" --no-pager 2>/dev/null \
            | grep -qi "heartbeat\|cron.*rotating"; then
            HEARTBEAT_RECENT=true
        fi

        if [ "$HEARTBEAT_RECENT" = "true" ]; then
            # Heartbeat fired but no polling activity — genuine silence
            ALL_HEALTHY=false
            POLL_FAILS=$(state_read "$POLLING_FAIL_FILE")
            POLL_FAILS=$((POLL_FAILS + 1))
            state_write "$POLLING_FAIL_FILE" "$POLL_FAILS"
            log "Polling silent for ${POLLING_WINDOW_MIN}m (heartbeat active). Consecutive: $POLL_FAILS/$POLLING_RESTART_THRESHOLD"

            if [ "$POLL_FAILS" -ge "$POLLING_RESTART_THRESHOLD" ]; then
                do_restart "Silent polling death ($POLL_FAILS consecutive checks, ${POLLING_WINDOW_MIN}m window)" || true
                state_write "$POLLING_FAIL_FILE" 0
            fi
        else
            # Heartbeat hasn't fired recently — inconclusive, don't count as failure
            log "Polling check inconclusive (heartbeat cron not recent). Skipping."
        fi
    else
        PREV_POLL_FAILS=$(state_read "$POLLING_FAIL_FILE")
        if [ "$PREV_POLL_FAILS" -gt 0 ]; then
            log "Polling recovered after $PREV_POLL_FAILS silent check(s)."
        fi
        state_write "$POLLING_FAIL_FILE" 0
    fi
fi

# --- Tier 4: Memory monitoring ---
# Read VmRSS from /proc for the openclaw service's main PID. Zero-cost.
PID=$(systemctl show -p MainPID --value openclaw 2>/dev/null || echo 0)
if [ "$PID" -gt 0 ] && [ -f "/proc/$PID/status" ]; then
    # VmRSS is in kB
    RSS_KB=$(awk '/^VmRSS:/ { print $2 }' "/proc/$PID/status" 2>/dev/null || echo 0)

    if [ "$RSS_KB" -ge "$MEMORY_CRIT_KB" ]; then
        ALL_HEALTHY=false
        MEM_WARNS=$(state_read "$MEMORY_WARN_FILE")
        MEM_WARNS=$((MEM_WARNS + 1))
        state_write "$MEMORY_WARN_FILE" "$MEM_WARNS"
        log "Memory CRITICAL: VmRSS=${RSS_KB}kB (>${MEMORY_CRIT_KB}kB). Consecutive: $MEM_WARNS/$MEMORY_RESTART_THRESHOLD"

        if [ "$MEM_WARNS" -ge "$MEMORY_RESTART_THRESHOLD" ]; then
            do_restart "Memory leak (VmRSS=${RSS_KB}kB, $MEM_WARNS consecutive critical checks)" || true
            state_write "$MEMORY_WARN_FILE" 0
        fi
    elif [ "$RSS_KB" -ge "$MEMORY_WARN_KB" ]; then
        log "Memory WARNING: VmRSS=${RSS_KB}kB (>${MEMORY_WARN_KB}kB). Monitoring."
        # Don't count warnings toward restart threshold — only critical does
    else
        PREV_MEM_WARNS=$(state_read "$MEMORY_WARN_FILE")
        if [ "$PREV_MEM_WARNS" -gt 0 ]; then
            log "Memory recovered (VmRSS=${RSS_KB}kB). Resetting counter."
        fi
        state_write "$MEMORY_WARN_FILE" 0
    fi
fi

# --- Backoff reset tracking ---
if [ "$ALL_HEALTHY" = "true" ]; then
    record_healthy
fi
