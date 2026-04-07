#!/usr/bin/env bash
# 04-monitoring.sh — Phase 10: Backups & Monitoring
# Deploys health-check and backup scripts to ~/scripts/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "10" "Backups & Monitoring"

applied=0
skipped=0

SCRIPTS_DIR="${HOME}/scripts"

# ── Scripts directory ───────────────────────────────────
if [[ ! -d "$SCRIPTS_DIR" ]]; then
    mkdir -p "$SCRIPTS_DIR"
    log_done "Created ~/scripts/ directory"
fi

# ── Health check script ─────────────────────────────────
STEP="monitoring.health_check"
if is_step_done "$STEP"; then
    log_skip "health-check.sh deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy health-check.sh to ~/scripts/"
    log_info "Checks gateway binding, memory DB, disk space, service status."
    if confirm; then
        REPO_SCRIPT="${SCRIPT_DIR}/../../health-check.sh"
        if [[ -f "$REPO_SCRIPT" ]]; then
            cp "$REPO_SCRIPT" "${SCRIPTS_DIR}/health-check.sh"
            chmod +x "${SCRIPTS_DIR}/health-check.sh"
            mark_step_done "$STEP"
            log_done "health-check.sh deployed"
            applied=$((applied + 1))
        else
            log_warn "health-check.sh not found in repo. Skipping."
            log_info "Copy manually from src/scripts/health-check.sh"
            skipped=$((skipped + 1))
        fi
    fi
fi

# ── Backup script ───────────────────────────────────────
STEP="monitoring.backup"
if is_step_done "$STEP"; then
    log_skip "backup.sh deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy backup.sh to ~/scripts/"
    log_info "Backs up openclaw.json, memory DB, workspace, auth profiles."
    if confirm; then
        REPO_SCRIPT="${SCRIPT_DIR}/../../backup.sh"
        if [[ -f "$REPO_SCRIPT" ]]; then
            cp "$REPO_SCRIPT" "${SCRIPTS_DIR}/backup.sh"
            chmod +x "${SCRIPTS_DIR}/backup.sh"
            mark_step_done "$STEP"
            log_done "backup.sh deployed"
            applied=$((applied + 1))
        else
            log_warn "backup.sh not found in repo. Skipping."
            log_info "Copy manually from src/scripts/backup.sh"
            skipped=$((skipped + 1))
        fi
    fi
fi

# ── Auto-update script ──────────────────────────────────
STEP="monitoring.auto_update"
if is_step_done "$STEP"; then
    log_skip "auto-update.sh deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy auto-update.sh to ~/scripts/"
    log_info "Weekly OpenClaw update (stops gateway, npm update, restarts)."
    if confirm; then
        REPO_SCRIPT="${SCRIPT_DIR}/../../auto-update.sh"
        if [[ -f "$REPO_SCRIPT" ]]; then
            cp "$REPO_SCRIPT" "${SCRIPTS_DIR}/auto-update.sh"
            chmod +x "${SCRIPTS_DIR}/auto-update.sh"
            mark_step_done "$STEP"
            log_done "auto-update.sh deployed"
            applied=$((applied + 1))
        else
            log_warn "auto-update.sh not found in repo. Skipping."
            skipped=$((skipped + 1))
        fi
    fi
fi

# ── Web tools ───────────────────────────────────────────
STEP="monitoring.web_tools"
if is_step_done "$STEP"; then
    log_skip "web tools enabled"
    skipped=$((skipped + 1))
else
    log_todo "Enabling web search and fetch tools"
    if confirm; then
        config_set "tools.web" '{"search": {"enabled": true}, "fetch": {"enabled": true}}'
        mark_step_done "$STEP"
        log_done "web search + fetch enabled"
        applied=$((applied + 1))
    fi
fi

log_summary "$applied" "$skipped"
