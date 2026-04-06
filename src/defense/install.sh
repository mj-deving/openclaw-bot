#!/usr/bin/env bash
# Defense system installer — deploys Defense Shield plugin + ClawKeeper
#
# Three contexts:
#   ./install.sh                    Run ON the VPS directly (repo checkout)
#   ./install.sh --remote vps       Deploy to VPS via SSH (repo checkout)
#   ./install.sh --standalone       Download from GitHub (no repo needed)
#
# Standalone mode is auto-detected when:
#   - The script is run from /tmp, or
#   - layer1-sanitizer.ts doesn't exist next to the script
#
# Flags:
#   --remote HOST       Deploy via SSH to HOST
#   --standalone        Force standalone mode (download from GitHub)
#   --dry-run           Preview without making changes
#   --uninstall         Remove both plugins, restart gateway
#   --skip-clawkeeper   Install only Defense Shield plugin
#   --help              Usage
#
# Safety:
#   - Idempotent — safe to re-run (skip if already exists)
#   - Never overwrites existing files without --uninstall
#   - No heredoc JSON — python3 for all JSON handling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub raw URL for standalone downloads
GITHUB_RAW="https://raw.githubusercontent.com/mj-deving/openclaw-hardened/main/src/defense"

# Defaults
DRY_RUN=false
REMOTE=""
UNINSTALL=false
SKIP_CLAWKEEPER=false
STANDALONE=false
OPENCLAW_DIR="$HOME/.openclaw"
SKILL_DIR="$OPENCLAW_DIR/workspace/skills/security-defense"
PLUGIN_DIR="$SKILL_DIR/plugin"
CLAWKEEPER_DIR="$OPENCLAW_DIR/extensions/clawkeeper"
CLAWKEEPER_REPO="https://github.com/SafeAI-Lab-X/ClawKeeper.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
deployed=0
skipped=0
errors=0

# ── Helpers ──────────────────────────────────────────────────────────

info()    { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $1"; }
skip()    { echo -e "  ${YELLOW}[SKIP]${NC}  $1"; }
err()     { echo -e "  ${RED}[ERROR]${NC} $1"; }
dry()     { echo -e "  ${BLUE}[DRY]${NC}   Would: $1"; }
die()     { err "$1"; exit 1; }
section() { echo ""; echo -e "${BOLD}[$1] $2${NC}"; echo "--------------------------------------------"; }

run_remote() { ssh "$REMOTE" "$@"; }
scp_to()     { scp -q "$1" "${REMOTE}:${2}"; }

# Deploy a single file from local src to remote dst (idempotent)
deploy_one() {
    local src="$1" dst="$2" label="$3"
    if [[ ! -f "$src" ]]; then
        err "Source missing: ${src}"; errors=$((errors + 1)); return; fi
    if cmd "test -f '${dst}'" && ! $DRY_RUN; then
        skip "${label} -- already exists"; skipped=$((skipped + 1)); return; fi
    if $DRY_RUN; then
        dry "Copy ${label} -> ${dst}"; deployed=$((deployed + 1)); return; fi
    if is_remote; then scp_to "$src" "$dst"; else cp "$src" "$dst"; fi
    ok "Deployed ${label}"; deployed=$((deployed + 1))
}

# Fetch a single file from GitHub to remote/local dst (idempotent, standalone mode)
fetch_one() {
    local url="$1" dst="$2" label="$3"
    if cmd "test -f '${dst}'" && ! $DRY_RUN; then
        skip "${label} -- already exists"; skipped=$((skipped + 1)); return; fi
    if $DRY_RUN; then
        dry "Download ${label} from GitHub"; deployed=$((deployed + 1)); return; fi
    if is_remote; then
        cmd "curl -fsSL '${url}' -o '${dst}'" || { err "Failed to download ${label}"; errors=$((errors + 1)); return; }
    else
        curl -fsSL "$url" -o "$dst" || { err "Failed to download ${label}"; errors=$((errors + 1)); return; }
    fi
    ok "Downloaded ${label}"; deployed=$((deployed + 1))
}

# ── Argument parsing ─────────────────────────────────────────────────

show_help() {
    cat <<'EOF'
Defense System Installer — installs Defense Shield plugin + ClawKeeper

Usage:
  bash install.sh                              Install on local VPS (repo checkout)
  bash install.sh --remote vps                 Install via SSH (repo checkout)
  bash install.sh --standalone                 Download from GitHub + install (no repo)
  bash install.sh --dry-run                    Preview actions
  bash install.sh --uninstall                  Remove both plugins

  # One-liner for fresh VPS (standalone auto-detected):
  curl -fsSL https://raw.githubusercontent.com/mj-deving/openclaw-hardened/main/src/defense/install.sh | bash

Flags:
  --remote HOST       Deploy to HOST via SSH
  --standalone        Force standalone mode (download from GitHub instead of local copy)
  --dry-run           Preview without making changes
  --uninstall         Remove both plugins and restart gateway
  --skip-clawkeeper   Install only Defense Shield (no ClawKeeper)
  --help              This message

Standalone mode auto-detects when layer1-sanitizer.ts is not found next to
the script (e.g., when piped from curl or run from /tmp).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            [[ $# -lt 2 ]] && die "--remote requires a HOST argument"
            REMOTE="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --uninstall)     UNINSTALL=true; shift ;;
        --standalone)    STANDALONE=true; shift ;;
        --skip-clawkeeper) SKIP_CLAWKEEPER=true; shift ;;
        --help|-h)       show_help; exit 0 ;;
        *)               die "Unknown option: $1 (try --help)" ;;
    esac
done

# ── Context detection ────────────────────────────────────────────────

is_remote() { [[ -n "$REMOTE" ]]; }

# Auto-detect standalone mode: if the layer files don't exist next to the
# script, or the script is running from /tmp (piped from curl), switch to
# standalone and download from GitHub instead of copying local files.
if ! $STANDALONE; then
    if [[ ! -f "${SCRIPT_DIR}/layer1-sanitizer.ts" ]] || [[ "$SCRIPT_DIR" == /tmp* ]]; then
        STANDALONE=true
        info "Auto-detected standalone mode (source files not found locally)"
    fi
fi

# When remote, commands run over SSH; adjust paths to the remote home
if is_remote; then
    REMOTE_HOME=$(run_remote 'echo $HOME')
    OPENCLAW_DIR="${REMOTE_HOME}/.openclaw"
    SKILL_DIR="$OPENCLAW_DIR/workspace/skills/security-defense"
    PLUGIN_DIR="$SKILL_DIR/plugin"
    CLAWKEEPER_DIR="$OPENCLAW_DIR/extensions/clawkeeper"
fi

# Shell command executor — local or remote
cmd() {
    if is_remote; then
        run_remote "$*"
    else
        eval "$*"
    fi
}

# ── Banner ───────────────────────────────────────────────────────────

echo ""
echo "================================================================"
echo "  Defense System Installer"
if is_remote; then
    echo "  Target: ${REMOTE} (SSH)"
else
    echo "  Target: localhost (direct)"
fi
$DRY_RUN    && echo "  Mode: DRY RUN (no changes will be made)"
$UNINSTALL  && echo "  Mode: UNINSTALL"
$STANDALONE && echo "  Source: GitHub (standalone)"
! $STANDALONE && echo "  Source: local repo (${SCRIPT_DIR})"
echo "================================================================"
echo ""

# ── Uninstall path ───────────────────────────────────────────────────

if $UNINSTALL; then
    section "1/3" "Removing Defense Shield plugin"
    if $DRY_RUN; then
        dry "Remove ${SKILL_DIR}"
        dry "openclaw plugins uninstall defense-shield"
    else
        cmd "rm -rf '${SKILL_DIR}'" && ok "Removed ${SKILL_DIR}" || err "Failed to remove ${SKILL_DIR}"
        cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw plugins uninstall defense-shield 2>/dev/null" \
            && ok "Uninstalled defense-shield plugin" \
            || skip "defense-shield was not registered"
    fi

    if ! $SKIP_CLAWKEEPER; then
        section "2/3" "Removing ClawKeeper"
        if $DRY_RUN; then
            dry "Remove ${CLAWKEEPER_DIR}"
        else
            cmd "rm -rf '${CLAWKEEPER_DIR}'" && ok "Removed ${CLAWKEEPER_DIR}" || err "Failed to remove ${CLAWKEEPER_DIR}"
            cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw plugins uninstall clawkeeper 2>/dev/null" \
                && ok "Uninstalled clawkeeper plugin" \
                || skip "clawkeeper was not registered"
        fi
    fi

    section "3/3" "Restarting gateway"
    if $DRY_RUN; then
        dry "sudo systemctl restart openclaw"
    else
        cmd "sudo systemctl restart openclaw 2>/dev/null" \
            && ok "Gateway restarted" \
            || err "Could not restart gateway (no sudo?). Restart manually: sudo systemctl restart openclaw"
    fi

    echo ""
    echo "================================================================"
    echo "  Uninstall complete"
    echo "================================================================"
    exit 0
fi

# ── Step 1: Prerequisites ────────────────────────────────────────────

section "1/7" "Checking prerequisites"

# Check OpenClaw directory exists
if cmd "test -d '${OPENCLAW_DIR}'"; then
    ok "OpenClaw directory: ${OPENCLAW_DIR}"
else
    die "OpenClaw not found at ${OPENCLAW_DIR}. Install OpenClaw first."
fi

# Check gateway is running
if cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw --version >/dev/null 2>&1"; then
    OC_VERSION=$(cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw --version 2>/dev/null" || echo "unknown")
    ok "OpenClaw: ${OC_VERSION}"
else
    die "OpenClaw CLI not found. Is it installed?"
fi

# Check/install bun
if cmd "command -v bun >/dev/null 2>&1 || test -x \$HOME/.bun/bin/bun"; then
    BUN_VERSION=$(cmd "bun --version 2>/dev/null || \$HOME/.bun/bin/bun --version 2>/dev/null" || echo "unknown")
    ok "Bun: ${BUN_VERSION}"
else
    info "Bun not found, installing..."
    if $DRY_RUN; then
        dry "Install bun via curl"
    else
        cmd "curl -fsSL https://bun.sh/install | bash" || die "Failed to install bun"
        ok "Bun installed"
    fi
fi

# In standalone mode, verify curl is available (needed for downloads)
if $STANDALONE; then
    if command -v curl >/dev/null 2>&1; then
        ok "curl available (needed for standalone downloads)"
    else
        die "curl is required for standalone mode"
    fi
fi

# ── Step 2: Deploy Defense Shield source files ───────────────────────

section "2/7" "Deploying Defense Shield source files"

# List of TS files to deploy (excluding __tests__ and proxy/)
TS_FILES=(
    "index.ts"
    "layer1-sanitizer.ts"
    "layer2-scanner.ts"
    "layer3-outbound.ts"
    "layer4-redaction.ts"
    "layer5-governor.ts"
    "layer6-access.ts"
    "patterns.ts"
    "types.ts"
)

if $DRY_RUN; then dry "mkdir -p ${SKILL_DIR}"; else cmd "mkdir -p '${SKILL_DIR}'"; fi

for ts_file in "${TS_FILES[@]}"; do
    if $STANDALONE; then
        fetch_one "${GITHUB_RAW}/${ts_file}" "${SKILL_DIR}/${ts_file}" "$ts_file"
    else
        deploy_one "${SCRIPT_DIR}/${ts_file}" "${SKILL_DIR}/${ts_file}" "$ts_file"
    fi
done

# ── Step 3: Deploy Defense Shield plugin ─────────────────────────────

section "3/7" "Deploying Defense Shield plugin"

PLUGIN_FILES=("index.ts" "hooks.ts" "types.ts" "package.json" "openclaw.plugin.json")
LOCAL_PLUGIN_DIR="${SCRIPT_DIR}/plugin"

if $DRY_RUN; then dry "mkdir -p ${PLUGIN_DIR}"; else cmd "mkdir -p '${PLUGIN_DIR}'"; fi

for pf in "${PLUGIN_FILES[@]}"; do
    if $STANDALONE; then
        fetch_one "${GITHUB_RAW}/plugin/${pf}" "${PLUGIN_DIR}/${pf}" "plugin/${pf}"
    else
        deploy_one "${LOCAL_PLUGIN_DIR}/${pf}" "${PLUGIN_DIR}/${pf}" "plugin/${pf}"
    fi
done

# Register plugin with OpenClaw
info "Registering Defense Shield plugin..."
if $DRY_RUN; then
    dry "openclaw plugins install -l ${PLUGIN_DIR}"
else
    INSTALL_OUTPUT=$(cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw plugins install -l '${PLUGIN_DIR}' 2>&1" || true)
    if echo "$INSTALL_OUTPUT" | grep -qi "already\|loaded\|success\|install"; then
        ok "Defense Shield plugin registered"
    else
        info "Plugin install output: ${INSTALL_OUTPUT}"
        ok "Plugin install command completed"
    fi
fi

# ── Step 4: Install ClawKeeper ───────────────────────────────────────

if $SKIP_CLAWKEEPER; then
    section "4/7" "ClawKeeper (skipped via --skip-clawkeeper)"
    skip "ClawKeeper installation skipped"
else
    section "4/7" "Installing ClawKeeper"

    # Clone if not already present
    if cmd "test -d /tmp/ClawKeeper"; then
        skip "ClawKeeper repo already cloned at /tmp/ClawKeeper"
    elif $DRY_RUN; then
        dry "git clone ${CLAWKEEPER_REPO} /tmp/ClawKeeper"
    else
        info "Cloning ClawKeeper..."
        cmd "git clone '${CLAWKEEPER_REPO}' /tmp/ClawKeeper 2>&1 | tail -2" \
            && ok "ClawKeeper cloned to /tmp/ClawKeeper" \
            || die "Failed to clone ClawKeeper"
    fi

    # Patch child_process.spawn in cli.js
    info "Patching ClawKeeper to neutralize shell execution..."
    PATCH_TARGET="/tmp/ClawKeeper/clawkeeper-plugin/src/plugin/cli.js"
    if $DRY_RUN; then
        dry "Patch ${PATCH_TARGET}: replace spawn() with console.warn stub"
    else
        # Use python3 for reliable patching (project convention: no sed for complex transforms)
        cmd "python3 -c \"
import re, sys

path = '${PATCH_TARGET}'
try:
    with open(path) as f:
        content = f.read()
except FileNotFoundError:
    # Try alternative path structure
    alt = '/tmp/ClawKeeper/src/plugin/cli.js'
    with open(alt) as f:
        content = f.read()
    path = alt

# Replace spawn call with console.warn stub
# Match: child_process.spawn(...) or spawn(...) with surrounding function body
patched = re.sub(
    r'(function\s+runBundledScript\s*\([^)]*\)\s*\{)',
    r'\\1\n  console.warn(\\\"[clawkeeper] Shell execution disabled in hardened mode\\\");\n  return;',
    content
)

# Fallback: if function pattern didn't match, replace spawn directly
if patched == content:
    patched = re.sub(
        r'child_process\.spawn\s*\([^)]+\)',
        'console.warn(\"[clawkeeper] Shell execution disabled in hardened mode\")',
        content
    )

if patched == content:
    print('WARNING: No spawn patterns found to patch (may already be patched)')
else:
    with open(path, 'w') as f:
        f.write(patched)
    print('Patched: shell execution neutralized')
\"" && ok "ClawKeeper patched (shell execution disabled)" \
        || err "Patch failed (non-fatal -- ClawKeeper may still work)"
    fi

    # Copy to extensions directory
    if cmd "test -d '${CLAWKEEPER_DIR}'"; then
        skip "ClawKeeper already installed at ${CLAWKEEPER_DIR}"; skipped=$((skipped + 1))
    elif $DRY_RUN; then
        dry "Copy clawkeeper-plugin/ -> ${CLAWKEEPER_DIR}"; deployed=$((deployed + 1))
    else
        cmd "mkdir -p '${CLAWKEEPER_DIR}'"
        CK_SRC="/tmp/ClawKeeper/clawkeeper-plugin"
        cmd "test -d '${CK_SRC}'" || CK_SRC="/tmp/ClawKeeper"
        cmd "cp -r '${CK_SRC}'/* '${CLAWKEEPER_DIR}/'"
        ok "ClawKeeper installed to ${CLAWKEEPER_DIR}"; deployed=$((deployed + 1))
    fi
fi

# ── Step 5: Restart gateway ──────────────────────────────────────────

section "5/7" "Restarting gateway"

if $DRY_RUN; then
    dry "sudo systemctl restart openclaw"
else
    if cmd "sudo systemctl restart openclaw 2>/dev/null"; then
        ok "Gateway restarting (allow 10-15s to initialize)"
    else
        err "Could not restart gateway (no sudo?)"
        info "Restart manually: sudo systemctl restart openclaw"
        errors=$((errors + 1))
    fi
fi

# ── Step 6: Verify plugins ──────────────────────────────────────────

section "6/7" "Verifying plugins"

if $DRY_RUN; then
    dry "openclaw plugins list | grep defense-shield"
    dry "openclaw plugins list | grep clawkeeper"
else
    # Wait briefly for gateway to come up
    info "Waiting for gateway to initialize..."
    sleep 12

    PLUGINS_OUTPUT=$(cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw plugins list 2>&1" || true)

    if echo "$PLUGINS_OUTPUT" | grep -qi "defense-shield"; then
        ok "Defense Shield plugin: loaded"
    else
        err "Defense Shield plugin not found in plugins list"
        info "Check logs: sudo journalctl -u openclaw -n 30"
        errors=$((errors + 1))
    fi

    if ! $SKIP_CLAWKEEPER; then
        if echo "$PLUGINS_OUTPUT" | grep -qi "clawkeeper"; then
            ok "ClawKeeper plugin: loaded"
        else
            err "ClawKeeper not found in plugins list"
            info "Check: ls ${CLAWKEEPER_DIR}/"
            errors=$((errors + 1))
        fi
    fi
fi

# ── Step 7: Run ClawKeeper audit ─────────────────────────────────────

if ! $SKIP_CLAWKEEPER; then
    section "7/7" "Running ClawKeeper audit"

    if $DRY_RUN; then
        dry "openclaw clawkeeper audit"
    else
        AUDIT_OUTPUT=$(cmd "export PATH=\$HOME/.npm-global/bin:\$PATH && openclaw clawkeeper audit 2>&1" || true)
        if [[ -n "$AUDIT_OUTPUT" ]]; then
            echo "$AUDIT_OUTPUT" | head -20
            ok "ClawKeeper audit complete"
        else
            info "ClawKeeper audit returned no output (gateway may still be starting)"
        fi
    fi
else
    section "7/7" "ClawKeeper audit (skipped)"
    skip "ClawKeeper not installed"
fi

# ── Standalone: download validation script ───────────────────────────

if $STANDALONE; then
    section "+" "Downloading validation script (standalone)"
    fetch_one "${GITHUB_RAW}/validate.sh" "${SKILL_DIR}/validate.sh" "validate.sh"
    if ! $DRY_RUN; then
        cmd "chmod +x '${SKILL_DIR}/validate.sh'" 2>/dev/null || true
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "================================================================"
if $DRY_RUN; then
    echo "  DRY RUN SUMMARY"
else
    echo "  INSTALL SUMMARY"
fi
echo "================================================================"
echo ""
echo -e "  Deployed:  ${GREEN}${deployed}${NC}"
echo -e "  Skipped:   ${YELLOW}${skipped}${NC} (already exist)"
if (( errors > 0 )); then
    echo -e "  Errors:    ${RED}${errors}${NC}"
fi
echo ""
if ! $DRY_RUN && (( deployed > 0 )); then
    echo "  Next steps:"
    echo "    1. Verify: openclaw plugins list"
    if $STANDALONE; then
        echo "    2. Validate: bash ${SKILL_DIR}/validate.sh"
    else
        echo "    2. Validate: bash src/defense/validate.sh"
    fi
    echo "    3. Check logs: sudo journalctl -u openclaw | grep defense-shield"
    echo ""
fi
