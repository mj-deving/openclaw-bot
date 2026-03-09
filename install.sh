#!/bin/bash
# openclaw-hardened installer — deploys operational tooling to a VPS
# This does NOT install OpenClaw itself (that's: npm install -g openclaw)
# This deploys: config template, monitoring scripts, cron jobs, logrotate
#
# Usage:
#   ./install.sh              # Deploy everything
#   ./install.sh --dry-run    # Preview without changing anything
#
# Safety:
#   - Never overwrites existing files (skips with warning)
#   - No secrets — config template has placeholders
#   - Idempotent — safe to re-run

set -euo pipefail

# --- Config ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
SCRIPTS_DIR="$HOME/scripts"
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Parse args ---
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: ./install.sh [--dry-run]"
            echo ""
            echo "Deploys openclaw-hardened operational tooling to the current user's environment."
            echo ""
            echo "Options:"
            echo "  --dry-run    Preview actions without making changes"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: ./install.sh [--dry-run]"
            exit 1
            ;;
    esac
done

# --- Helpers ---
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

deployed=0
skipped=0
errors=0

# Copy file if destination doesn't exist
deploy_file() {
    local src="$1"
    local dst="$2"
    local desc="$3"

    if [[ -f "$dst" ]]; then
        warn "$desc — already exists at $dst"
        ((skipped++))
        return
    fi

    if $DRY_RUN; then
        info "[DRY RUN] Would deploy: $src → $dst"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        success "Deployed $desc → $dst"
    fi
    ((deployed++))
}

# Copy and make executable
deploy_script() {
    local src="$1"
    local dst="$2"
    local desc="$3"

    if [[ -f "$dst" ]]; then
        warn "$desc — already exists at $dst"
        ((skipped++))
        return
    fi

    if $DRY_RUN; then
        info "[DRY RUN] Would deploy: $src → $dst (executable)"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        chmod +x "$dst"
        success "Deployed $desc → $dst"
    fi
    ((deployed++))
}

# Add cron job if not already present
deploy_cron() {
    local schedule="$1"
    local command="$2"
    local desc="$3"

    # Check if this command is already in crontab
    if crontab -l 2>/dev/null | grep -qF "$command"; then
        warn "Cron: $desc — already scheduled"
        ((skipped++))
        return
    fi

    if $DRY_RUN; then
        info "[DRY RUN] Would add cron: $schedule $command ($desc)"
    else
        (crontab -l 2>/dev/null; echo "$schedule $command # $desc") | crontab -
        success "Cron: $desc ($schedule)"
    fi
    ((deployed++))
}

# --- Preflight checks ---
echo ""
echo "════════════════════════════════════════════════════════"
echo "  openclaw-hardened installer"
if $DRY_RUN; then
    echo "  Mode: DRY RUN (no changes will be made)"
fi
echo "════════════════════════════════════════════════════════"
echo ""

# Check OpenClaw is installed
if command -v openclaw &>/dev/null; then
    OC_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
    success "OpenClaw found: $OC_VERSION"
else
    error "OpenClaw not found. Install it first: npm install -g openclaw"
    exit 1
fi

# Check systemd
if command -v systemctl &>/dev/null; then
    success "systemd available"
else
    warn "systemd not found — cron jobs will still be set up, but service management won't work"
fi

echo ""

# --- 1. Config template ---
info "Step 1/4: Config template"
deploy_file \
    "$REPO_DIR/src/config/openclaw.json.example" \
    "$OPENCLAW_DIR/openclaw.json" \
    "Config template"
echo ""

# --- 2. Monitoring scripts ---
info "Step 2/4: Monitoring scripts"
deploy_script "$REPO_DIR/src/scripts/backup.sh"         "$SCRIPTS_DIR/backup.sh"         "Backup script"
deploy_script "$REPO_DIR/src/scripts/health-check.sh"    "$SCRIPTS_DIR/health-check.sh"    "Health check script"
deploy_script "$REPO_DIR/src/scripts/auto-update.sh"     "$SCRIPTS_DIR/auto-update.sh"     "Auto-update script"
deploy_script "$REPO_DIR/src/scripts/verify-binding.sh"  "$SCRIPTS_DIR/verify-binding.sh"  "Binding verification script"
deploy_script "$REPO_DIR/src/scripts/ops-playbook.sh"    "$SCRIPTS_DIR/ops-playbook.sh"    "Ops playbook diagnostic script"
echo ""

# --- 3. Cron jobs ---
info "Step 3/4: Cron jobs"
deploy_cron "0 3 * * *"    "$SCRIPTS_DIR/backup.sh"         "Daily backup (3 AM)"
deploy_cron "*/5 * * * *"  "$SCRIPTS_DIR/health-check.sh"   "Health check (every 5 min)"
deploy_cron "0 4 * * 0"    "$SCRIPTS_DIR/auto-update.sh"    "Weekly update (Sunday 4 AM)"
deploy_cron "*/5 * * * *"  "$SCRIPTS_DIR/verify-binding.sh" "Binding check (every 5 min)"
echo ""

# --- 4. Logrotate ---
info "Step 4/4: Log rotation"
LOGROTATE_DST="/etc/logrotate.d/openclaw"
if [[ -f "$LOGROTATE_DST" ]]; then
    warn "Logrotate config — already exists at $LOGROTATE_DST"
    ((skipped++))
elif $DRY_RUN; then
    info "[DRY RUN] Would deploy logrotate config → $LOGROTATE_DST (requires sudo)"
    ((deployed++))
else
    if sudo cp "$REPO_DIR/src/config/logrotate-openclaw" "$LOGROTATE_DST" 2>/dev/null; then
        success "Deployed logrotate config → $LOGROTATE_DST"
        ((deployed++))
    else
        warn "Logrotate config — sudo not available, skipping (deploy manually: sudo cp src/config/logrotate-openclaw $LOGROTATE_DST)"
        ((skipped++))
    fi
fi
echo ""

# --- Summary ---
echo "════════════════════════════════════════════════════════"
if $DRY_RUN; then
    echo "  DRY RUN SUMMARY"
else
    echo "  INSTALL SUMMARY"
fi
echo "════════════════════════════════════════════════════════"
echo ""
echo -e "  Deployed:  ${GREEN}${deployed}${NC}"
echo -e "  Skipped:   ${YELLOW}${skipped}${NC} (already exist)"
if (( errors > 0 )); then
    echo -e "  Errors:    ${RED}${errors}${NC}"
fi
echo ""
if ! $DRY_RUN && (( deployed > 0 )); then
    echo "  Next steps:"
    echo "    1. Edit ~/.openclaw/openclaw.json — add your API keys and Telegram token"
    echo "    2. Read GUIDE.md — start at Phase 1"
    echo ""
fi
