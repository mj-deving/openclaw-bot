#!/usr/bin/env bash
# 06-logging.sh — Logging & Redaction
# Configures sensitive data redaction in logs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "7+" "Logging & Redaction"

applied=0
skipped=0

# ── Redact sensitive data ───────────────────────────────
STEP="logging.redaction"
if is_step_done "$STEP"; then
    log_skip "log redaction configured"
    ((skipped++))
else
    log_todo "Configuring sensitive data redaction in logs"
    log_info "Redacts Anthropic API keys, OpenAI keys, and Telegram bot tokens from logs."
    if confirm; then
        config_set "logging.redactSensitive" '"tools"'
        config_set "logging.redactPatterns" '["sk-ant-[\\w-]+", "sk-[A-Za-z0-9]{48,}", "\\d{5,}:[A-Za-z0-9_-]+"]'
        mark_step_done "$STEP"
        log_done "log redaction enabled (API keys, bot tokens)"
        ((applied++))
    fi
fi

log_summary "$applied" "$skipped"
