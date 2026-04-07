#!/usr/bin/env bash
# 05-streaming.sh — Anti-duplicate streaming config
# Disables streaming to prevent duplicate messages (known OpenClaw issue).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "7+" "Streaming & Message Config"

applied=0
skipped=0

# ── Streaming off ───────────────────────────────────────
STEP="streaming.telegram"
if is_step_done "$STEP"; then
    log_skip "Telegram streaming = off"
    ((skipped++))
else
    log_todo "Setting Telegram streaming to 'off'"
    log_info "Prevents duplicate messages from draft streaming and block chunking."
    log_info "Uses v2026.4.5 format: streaming=\"off\" (not legacy streamMode)."
    if confirm; then
        config_set "channels.telegram.streaming" '"off"'
        # Clean up any legacy keys
        config_delete "channels.telegram.streamMode" 2>/dev/null || true
        config_delete "channels.telegram.blockStreaming" 2>/dev/null || true
        mark_step_done "$STEP"
        log_done "Telegram streaming = off (legacy keys cleaned)"
        ((applied++))
    fi
fi

# ── Ack reaction scope ──────────────────────────────────
STEP="streaming.ack_scope"
if is_step_done "$STEP"; then
    log_skip "ack reaction scope configured"
    ((skipped++))
else
    log_todo "Setting ack reaction scope to group-mentions"
    log_info "Bot only reacts to messages that @mention it in groups."
    if confirm; then
        config_set "messages.ackReactionScope" '"group-mentions"'
        mark_step_done "$STEP"
        log_done "ackReactionScope = group-mentions"
        ((applied++))
    fi
fi

log_summary "$applied" "$skipped"
