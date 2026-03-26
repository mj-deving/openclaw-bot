#!/bin/bash
# Lossless-Claw (LCM) plugin health check
# Checks: installed version vs latest, DB size, open security issues
# Deployed to: ~/scripts/lcm-check.sh on VPS
# Cron: 0 5 * * 0 (Sunday 5 AM, after auto-update at 4 AM and doctor-fix at 4:30)
#
# TOKEN COST: Zero. Uses npm registry + GitHub API only (no LLM calls).

set -euo pipefail

LOG="$HOME/.openclaw/logs/lcm-check.log"
LCM_DB="$HOME/.openclaw/lcm.db"
GITHUB_REPO="martian-engineering/lossless-claw"
NPM_PACKAGE="@martian-engineering/lossless-claw"

mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

log "=== LCM health check starting ==="

# --- Version check ---
# LCM is installed via `openclaw plugins install`, not npm global.
# Read version from the plugin's openclaw.json install record.
INSTALLED=$(python3 -c "
import json, sys
try:
    with open('$HOME/.openclaw/openclaw.json') as f:
        c = json.load(f)
    v = c.get('plugins',{}).get('installs',{}).get('lossless-claw',{}).get('resolvedVersion','not-installed')
    print(v)
except: print('not-installed')
" 2>/dev/null)
LATEST=$(npm view "$NPM_PACKAGE" version 2>/dev/null || echo "unknown")

log "Installed: $INSTALLED | Latest: $LATEST"

if [ "$INSTALLED" = "not-installed" ]; then
    log "WARNING: LCM plugin not registered in openclaw.json"
elif [ "$INSTALLED" != "$LATEST" ] && [ "$LATEST" != "unknown" ]; then
    log "UPDATE AVAILABLE: $INSTALLED -> $LATEST"
else
    log "Version is current"
fi

# --- DB size check ---
if [ -f "$LCM_DB" ]; then
    DB_SIZE=$(du -sh "$LCM_DB" | cut -f1)
    DB_BYTES=$(stat -c%s "$LCM_DB")
    log "Database: $DB_SIZE ($DB_BYTES bytes)"

    # Warn if DB exceeds 500MB
    if [ "$DB_BYTES" -gt 524288000 ]; then
        log "WARNING: LCM database exceeds 500MB — consider cleanup"
    fi
else
    log "Database: not found at $LCM_DB"
fi

# --- Plugin loaded check ---
PLUGIN_STATUS=$(openclaw plugins list 2>/dev/null | grep -i "lossless\|lcm" || echo "not-found")
if echo "$PLUGIN_STATUS" | grep -qi "loaded"; then
    log "Plugin status: loaded"
elif echo "$PLUGIN_STATUS" | grep -qi "disabled"; then
    log "WARNING: Plugin is installed but disabled"
else
    log "WARNING: Plugin not found in plugins list"
fi

# --- Security issues check (GitHub API, no auth needed for public repos) ---
SECURITY_ISSUES=$(curl -sL --max-time 10 \
    "https://api.github.com/repos/$GITHUB_REPO/issues?labels=security&state=open" 2>/dev/null)

if [ -n "$SECURITY_ISSUES" ] && echo "$SECURITY_ISSUES" | python3 -c "import sys,json; issues=json.load(sys.stdin); exit(0 if isinstance(issues, list) else 1)" 2>/dev/null; then
    ISSUE_COUNT=$(echo "$SECURITY_ISSUES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    log "Open security issues: $ISSUE_COUNT"

    if [ "$ISSUE_COUNT" -gt 0 ]; then
        echo "$SECURITY_ISSUES" | python3 -c "
import sys, json
issues = json.load(sys.stdin)
for i in issues:
    print(f'  #{i[\"number\"]}: {i[\"title\"]}')
" >> "$LOG"
    fi
else
    log "Security check: GitHub API unavailable or rate-limited"
fi

# --- Latest release info ---
RELEASE_INFO=$(curl -sL --max-time 10 \
    "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null)

if [ -n "$RELEASE_INFO" ]; then
    RELEASE_TAG=$(echo "$RELEASE_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name', 'unknown'))" 2>/dev/null || echo "unknown")
    RELEASE_DATE=$(echo "$RELEASE_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('published_at', 'unknown')[:10])" 2>/dev/null || echo "unknown")
    log "Latest release: $RELEASE_TAG ($RELEASE_DATE)"
fi

log "=== LCM health check complete ==="
