#!/usr/bin/env bash
# Deploy defense proxy to VPS and configure OpenClaw to route through it.
#
# Usage: ./deploy.sh
#
# What it does:
# 1. Checks bun is installed on VPS (installs if missing)
# 2. Copies proxy files to VPS
# 3. Installs systemd service
# 4. Patches openclaw.service with ANTHROPIC_BASE_URL + OPENAI_BASE_URL
# 5. Starts defense-proxy, restarts openclaw gateway
#
# Reversible: ./deploy.sh --rollback removes the env vars and stops the proxy.

set -euo pipefail

SSH_HOST="vps"
REMOTE_DIR="/home/openclaw/.openclaw/workspace/skills/security-defense/proxy"
SERVICE_NAME="defense-proxy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Rollback ──────────────────────────────────────────────────────────

if [[ "${1:-}" == "--rollback" ]]; then
  echo "Rolling back defense proxy..."
  ssh "$SSH_HOST" "sudo systemctl stop ${SERVICE_NAME} 2>/dev/null || true"
  ssh "$SSH_HOST" "sudo systemctl disable ${SERVICE_NAME} 2>/dev/null || true"
  ssh "$SSH_HOST" "sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service"
  # Remove ANTHROPIC_BASE_URL and OPENAI_BASE_URL from openclaw.service
  ssh "$SSH_HOST" "sudo sed -i '/ANTHROPIC_BASE_URL/d; /OPENAI_BASE_URL/d' /etc/systemd/system/openclaw.service"
  ssh "$SSH_HOST" "sudo systemctl daemon-reload"
  ssh "$SSH_HOST" "sudo systemctl restart openclaw"
  echo "Rollback complete. OpenClaw talks directly to APIs again."
  exit 0
fi

# ── Pre-checks ────────────────────────────────────────────────────────

echo "Checking VPS prerequisites..."

# Check bun
if ! ssh "$SSH_HOST" "command -v bun >/dev/null 2>&1"; then
  echo "Installing bun on VPS..."
  ssh "$SSH_HOST" "curl -fsSL https://bun.sh/install | bash"
fi

BUN_VERSION=$(ssh "$SSH_HOST" "~/.bun/bin/bun --version 2>/dev/null || bun --version 2>/dev/null")
echo "Bun version: $BUN_VERSION"

# ── Deploy files ──────────────────────────────────────────────────────

echo "Deploying proxy files..."
ssh "$SSH_HOST" "mkdir -p ${REMOTE_DIR}"
scp "${SCRIPT_DIR}/config.ts" "${SCRIPT_DIR}/server.ts" "${SSH_HOST}:${REMOTE_DIR}/"
echo "Files deployed to ${REMOTE_DIR}/"

# ── Install systemd service ──────────────────────────────────────────

echo "Installing systemd service..."
scp "${SCRIPT_DIR}/defense-proxy.service" "${SSH_HOST}:/tmp/${SERVICE_NAME}.service"
ssh "$SSH_HOST" "sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service"
ssh "$SSH_HOST" "sudo systemctl daemon-reload"
ssh "$SSH_HOST" "sudo systemctl enable ${SERVICE_NAME}"

# ── Patch openclaw.service ────────────────────────────────────────────

echo "Patching openclaw.service with proxy env vars..."

# Add ANTHROPIC_BASE_URL and OPENAI_BASE_URL if not already present
ssh "$SSH_HOST" 'python3 -c "
import re

svc_path = \"/etc/systemd/system/openclaw.service\"
with open(svc_path) as f:
    content = f.read()

changes = False

if \"ANTHROPIC_BASE_URL\" not in content:
    content = content.replace(
        \"ExecStart=\",
        \"Environment=ANTHROPIC_BASE_URL=http://127.0.0.1:18800\nExecStart=\",
        1
    )
    changes = True

if \"OPENAI_BASE_URL\" not in content:
    content = content.replace(
        \"ExecStart=\",
        \"Environment=OPENAI_BASE_URL=http://127.0.0.1:18800\nExecStart=\",
        1
    )
    changes = True

if changes:
    with open(svc_path, \"w\") as f:
        f.write(content)
    print(\"Patched: added ANTHROPIC_BASE_URL and OPENAI_BASE_URL\")
else:
    print(\"Already patched\")
" 2>&1' || {
  echo "WARNING: Could not patch openclaw.service automatically."
  echo "Manually add these lines to /etc/systemd/system/openclaw.service [Service] section:"
  echo "  Environment=ANTHROPIC_BASE_URL=http://127.0.0.1:18800"
  echo "  Environment=OPENAI_BASE_URL=http://127.0.0.1:18800"
}

# ── Start services ────────────────────────────────────────────────────

echo "Starting defense proxy..."
ssh "$SSH_HOST" "sudo systemctl daemon-reload"
ssh "$SSH_HOST" "sudo systemctl start ${SERVICE_NAME}"

# Verify proxy is running
sleep 2
if ssh "$SSH_HOST" "curl -sf http://127.0.0.1:18800/health" > /dev/null 2>&1; then
  echo "Defense proxy is healthy ✓"
else
  echo "WARNING: Defense proxy health check failed. Check logs:"
  echo "  ssh vps 'sudo journalctl -u ${SERVICE_NAME} -n 20'"
  exit 1
fi

echo "Restarting OpenClaw gateway..."
ssh "$SSH_HOST" "sudo systemctl restart openclaw"
sleep 5

echo ""
echo "═══════════════════════════════════════════════════"
echo "Defense proxy deployed and active."
echo ""
echo "  Proxy:    127.0.0.1:18800"
echo "  Health:   curl http://127.0.0.1:18800/health"
echo "  Logs:     sudo journalctl -u ${SERVICE_NAME} -f"
echo "  Rollback: $0 --rollback"
echo "═══════════════════════════════════════════════════"
