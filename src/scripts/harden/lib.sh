#!/usr/bin/env bash
# lib.sh — Shared utilities for OpenClaw hardening scripts
# Sourced by each phase script. Never run directly.

set -euo pipefail

# ── Colors ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── State file ──────────────────────────────────────────
OPENCLAW_DIR="${HOME}/.openclaw"
HARDEN_STATE="${OPENCLAW_DIR}/.harden-state.json"
OPENCLAW_CONFIG="${OPENCLAW_DIR}/openclaw.json"

# ── Detect OpenClaw binary ──────────────────────────────
export PATH="${HOME}/.npm-global/bin:${PATH}"
if ! command -v openclaw &>/dev/null; then
    echo -e "${RED}Error: openclaw not found in PATH${NC}"
    echo "Install OpenClaw first (GUIDE.md Phase 2)"
    exit 1
fi

# ── Logging ─────────────────────────────────────────────
log_header() {
    local phase="$1" title="$2"
    echo ""
    echo -e "${BOLD}═══ OpenClaw Hardening: ${title} (Phase ${phase}) ═══${NC}"
    echo ""
}

log_done() {
    echo -e "  ${GREEN}[✓]${NC} $1"
}

log_skip() {
    echo -e "  ${DIM}[–]${NC} Already done: $1"
}

log_todo() {
    echo -e "  ${BLUE}[ ]${NC} $1"
}

log_warn() {
    echo -e "  ${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "  ${RED}[✗]${NC} $1"
}

log_info() {
    echo -e "  ${CYAN}[i]${NC} $1"
}

# ── State management ────────────────────────────────────
# Each phase marks steps as complete in .harden-state.json
# Format: { "phase.step": "2026-04-07T12:00:00Z" }

ensure_state_file() {
    if [[ ! -f "$HARDEN_STATE" ]]; then
        echo '{}' > "$HARDEN_STATE"
    fi
}

is_step_done() {
    local step="$1"
    ensure_state_file
    python3 -c "
import json, sys
d = json.load(open('${HARDEN_STATE}'))
sys.exit(0 if '${step}' in d else 1)
" 2>/dev/null
}

mark_step_done() {
    local step="$1"
    ensure_state_file
    python3 -c "
import json
from datetime import datetime, timezone
d = json.load(open('${HARDEN_STATE}'))
d['${step}'] = datetime.now(timezone.utc).isoformat()
with open('${HARDEN_STATE}', 'w') as f:
    json.dump(d, f, indent=2)
"
}

# ── Config helpers (python3-based, safe JSON) ───────────

config_get() {
    # Usage: config_get "agents.defaults.model"
    local key_path="$1"
    python3 -c "
import json, sys
c = json.load(open('${OPENCLAW_CONFIG}'))
keys = '${key_path}'.split('.')
val = c
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(1)
print(json.dumps(val) if isinstance(val, (dict, list)) else str(val))
" 2>/dev/null
}

config_set() {
    # Usage: config_set "path.to.key" '{"json": "value"}'
    # Value must be valid JSON (string, number, object, array, bool)
    local key_path="$1"
    local value="$2"
    python3 -c "
import json
c = json.load(open('${OPENCLAW_CONFIG}'))
keys = '${key_path}'.split('.')
parent = c
for k in keys[:-1]:
    if k not in parent or not isinstance(parent[k], dict):
        parent[k] = {}
    parent = parent[k]
parent[keys[-1]] = json.loads('${value}')
with open('${OPENCLAW_CONFIG}', 'w') as f:
    json.dump(c, f, indent=2)
"
}

config_delete() {
    # Usage: config_delete "path.to.key"
    local key_path="$1"
    python3 -c "
import json
c = json.load(open('${OPENCLAW_CONFIG}'))
keys = '${key_path}'.split('.')
parent = c
for k in keys[:-1]:
    if k not in parent:
        exit(0)
    parent = parent[k]
if keys[-1] in parent:
    del parent[keys[-1]]
with open('${OPENCLAW_CONFIG}', 'w') as f:
    json.dump(c, f, indent=2)
"
}

config_has() {
    # Usage: if config_has "channels.telegram.botToken"; then ...
    local key_path="$1"
    config_get "$key_path" &>/dev/null
}

# ── Confirmation ────────────────────────────────────────

confirm() {
    local prompt="${1:-Apply these changes?}"
    if [[ "${AUTO_YES:-}" == "true" ]]; then
        return 0
    fi
    echo ""
    read -rp "  ${prompt} [Y/n] " response
    [[ -z "$response" || "$response" =~ ^[Yy] ]]
}

# ── Summary ─────────────────────────────────────────────

log_summary() {
    local applied="$1" skipped="$2"
    echo ""
    echo -e "${BOLD}  Summary:${NC} ${GREEN}${applied} applied${NC}, ${DIM}${skipped} skipped${NC}"
    echo ""
}
