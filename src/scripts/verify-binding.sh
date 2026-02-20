#!/bin/bash
# OpenClaw gateway binding verification
# Detects silent fallback from 127.0.0.1 → 0.0.0.0 (known bug: src/gateway/net.ts:256-261)
# Deployed to: ~/scripts/verify-binding.sh on VPS
# Cron: */5 * * * * (every 5 minutes)
#
# INTERVAL RATIONALE (5 minutes):
#   - This script costs nothing to run (~1ms, pure ss + grep)
#   - The threat is CRITICAL: silent exposure of full AI agent + API keys to internet
#   - ufw blocks port 18789 externally (defense-in-depth), but binding check is the primary gate
#   - 5 minutes = max exposure window. Acceptable given ufw as secondary barrier.
#   - Could run every 1 min but 5 min keeps cron logs cleaner with no security difference.
#
# TOKEN COST: Zero. Pure system commands only.

set -euo pipefail

LOG="$HOME/.openclaw/logs/binding-check.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

# Check if gateway is even running — if not, nothing to verify
if ! systemctl is-active --quiet openclaw 2>/dev/null; then
    exit 0
fi

# Check binding — CRITICAL: must be 127.0.0.1, never 0.0.0.0
# NOTE: ss output has both local and peer address columns. The peer column always shows
# 0.0.0.0:* for listening sockets, which is normal. We must check specifically for
# 0.0.0.0:18789 as the LOCAL address (meaning gateway bound to all interfaces).
if ss -tlnp 2>/dev/null | grep -q '0\.0\.0\.0:18789'; then
    log "CRITICAL: Gateway bound to 0.0.0.0:18789! Stopping service immediately."
    systemctl stop openclaw 2>/dev/null || true
    log "Service stopped. Manual investigation required before restart."
    # Future: add alerting here (webhook, email, Telegram API direct curl)
    exit 1
fi
