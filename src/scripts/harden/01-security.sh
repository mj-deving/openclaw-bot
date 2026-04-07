#!/usr/bin/env bash
# 01-security.sh — Phase 7: OpenClaw Security Hardening
# Tool permissions, exec security, error handling, mDNS, gateway auth.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "7" "Security Hardening"

applied=0
skipped=0

# ── Tool profile ────────────────────────────────────────
STEP="security.tool_profile"
if is_step_done "$STEP"; then
    log_skip "tool profile = full"
    ((skipped++))
else
    log_todo "Setting tool profile to 'full'"
    log_info "Grants read/write/edit/memory/web tools. Dangerous tools gated by deny list."
    if confirm; then
        config_set "tools.profile" '"full"'
        mark_step_done "$STEP"
        log_done "tool profile = full"
        ((applied++))
    fi
fi

# ── Tool deny list ──────────────────────────────────────
STEP="security.tool_deny"
if is_step_done "$STEP"; then
    log_skip "tool deny list configured"
    ((skipped++))
else
    log_todo "Setting tool deny list: gateway, nodes, sessions_spawn, sessions_send"
    log_info "Prevents bot from reconfiguring itself, spawning rogue sessions."
    if confirm; then
        config_set "tools.deny" '["gateway", "nodes", "sessions_spawn", "sessions_send"]'
        mark_step_done "$STEP"
        log_done "tool deny list set"
        ((applied++))
    fi
fi

# ── Tool allow list ─────────────────────────────────────
STEP="security.tool_allow"
if is_step_done "$STEP"; then
    log_skip "tool allow list configured"
    ((skipped++))
else
    log_todo "Setting tool allow: cron"
    log_info "Explicitly allows cron tool for autonomous scheduling."
    if confirm; then
        config_set "tools.allow" '["cron"]'
        mark_step_done "$STEP"
        log_done "tool allow = [cron]"
        ((applied++))
    fi
fi

# ── Exec security ──────────────────────────────────────
STEP="security.exec"
if is_step_done "$STEP"; then
    log_skip "exec.security = full"
    ((skipped++))
else
    log_todo "Setting exec.security to 'full', ask to 'off'"
    log_info "Shell commands require full security context. No interactive ask prompts."
    if confirm; then
        config_set "tools.exec" '{"security": "full", "ask": "off"}'
        mark_step_done "$STEP"
        log_done "exec.security = full, ask = off"
        ((applied++))
    fi
fi

# ── Elevated tools ──────────────────────────────────────
STEP="security.elevated"
if is_step_done "$STEP"; then
    log_skip "elevated tools disabled"
    ((skipped++))
else
    log_todo "Disabling elevated tools"
    log_info "Prevents privilege escalation via tool system."
    if confirm; then
        config_set "tools.elevated" '{"enabled": false}'
        mark_step_done "$STEP"
        log_done "elevated tools disabled"
        ((applied++))
    fi
fi

# ── Error policy ────────────────────────────────────────
STEP="security.error_policy"
if is_step_done "$STEP"; then
    log_skip "error policy configured"
    ((skipped++))
else
    log_todo "Setting Telegram errorPolicy to 'once' with 30s cooldown"
    log_info "Prevents error spam. Bot reports first error, then silences for 30s."
    if confirm; then
        config_set "channels.telegram.errorPolicy" '"once"'
        config_set "channels.telegram.errorCooldownMs" '30000'
        mark_step_done "$STEP"
        log_done "errorPolicy = once, cooldown = 30s"
        ((applied++))
    fi
fi

# ── mDNS off ───────────────────────────────────────────
STEP="security.mdns"
if is_step_done "$STEP"; then
    log_skip "mDNS disabled"
    ((skipped++))
else
    log_todo "Disabling mDNS/Bonjour discovery"
    log_info "Prevents network reconnaissance of your bot instance."
    if confirm; then
        config_set "discovery.mdns" '{"mode": "off"}'
        mark_step_done "$STEP"
        log_done "mDNS = off"
        ((applied++))
    fi
fi

# ── Gateway auth ───────────────────────────────────────
STEP="security.gateway_auth"
if is_step_done "$STEP"; then
    log_skip "gateway auth + rate limiting configured"
    ((skipped++))
else
    log_todo "Configuring gateway auth with rate limiting"
    log_info "Token auth + 10 attempts/60s window + 5min lockout."
    if confirm; then
        config_set "gateway.bind" '"loopback"'
        config_set "gateway.mode" '"local"'
        config_set "gateway.controlUi.dangerouslyDisableDeviceAuth" 'false'
        config_set "gateway.auth.mode" '"token"'
        config_set "gateway.auth.rateLimit" '{"maxAttempts": 10, "windowMs": 60000, "lockoutMs": 300000, "exemptLoopback": true}'
        config_set "gateway.tailscale" '{"mode": "off"}'
        mark_step_done "$STEP"
        log_done "gateway: loopback, token auth, rate limited"
        ((applied++))
    fi
fi

# ── Config command disabled ─────────────────────────────
STEP="security.config_command"
if is_step_done "$STEP"; then
    log_skip "config command disabled in chat"
    ((skipped++))
else
    log_todo "Disabling /config command in chat"
    log_info "Prevents bot from being reconfigured via Telegram messages."
    if confirm; then
        config_set "commands.config" 'false'
        mark_step_done "$STEP"
        log_done "commands.config = false"
        ((applied++))
    fi
fi

# ── Plugins.allow removal ───────────────────────────────
STEP="security.plugins_allow"
if is_step_done "$STEP"; then
    log_skip "plugins.allow whitelist removed"
    ((skipped++))
else
    if config_has "plugins.allow"; then
        log_todo "Removing plugins.allow (acts as whitelist in v2026.4.5, blocks Telegram)"
        log_warn "plugins.allow blocks bundled plugins from loading. Removing it."
        if confirm; then
            config_delete "plugins.allow"
            mark_step_done "$STEP"
            log_done "plugins.allow removed — all bundled plugins can load"
            ((applied++))
        fi
    else
        mark_step_done "$STEP"
        log_skip "plugins.allow not present (good)"
        ((skipped++))
    fi
fi

log_summary "$applied" "$skipped"

if ((applied > 0)); then
    log_warn "Restart the gateway to apply: sudo systemctl restart <service-name>"
fi
