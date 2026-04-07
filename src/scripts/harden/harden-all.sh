#!/usr/bin/env bash
# harden-all.sh — Run all hardening phases in order.
# Usage: ./harden-all.sh [--yes]
#   --yes  Skip all confirmation prompts (unattended mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse args
export AUTO_YES="false"
for arg in "$@"; do
    case "$arg" in
        --yes|-y) export AUTO_YES="true" ;;
        --help|-h)
            echo "Usage: harden-all.sh [--yes]"
            echo ""
            echo "Runs all OpenClaw hardening phases (7-14 + AtlasForge)."
            echo "Each phase is idempotent — safe to re-run."
            echo ""
            echo "Options:"
            echo "  --yes, -y   Skip confirmation prompts (unattended mode)"
            echo ""
            echo "Individual phases:"
            echo "  01-security.sh      Phase 7:  Tool permissions, exec security"
            echo "  02-identity.sh      Phase 8:  Bot identity (AGENTS.md)"
            echo "  03-memory.sh        Phase 9:  Memory, embeddings, PARA"
            echo "  04-monitoring.sh    Phase 10: Backups, health checks"
            echo "  05-streaming.sh     Phase 7+: Anti-duplicate streaming"
            echo "  06-logging.sh       Phase 7+: Log redaction"
            echo "  11-atlasforge.sh    AtlasForge meta-learning patterns"
            exit 0
            ;;
    esac
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         OpenClaw Post-Install Hardening          ║"
echo "║                                                  ║"
echo "║  Phases 7-14 + AtlasForge meta-learning          ║"
echo "║  Idempotent — safe to re-run                     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if [[ "$AUTO_YES" == "true" ]]; then
    echo "  Running in unattended mode (--yes)"
    echo ""
fi

# Run phases in order
PHASES=(
    "01-security.sh"
    "02-identity.sh"
    "03-memory.sh"
    "04-monitoring.sh"
    "05-streaming.sh"
    "06-logging.sh"
    "11-atlasforge.sh"
)

failed=0
for phase in "${PHASES[@]}"; do
    phase_script="${SCRIPT_DIR}/${phase}"
    if [[ -f "$phase_script" ]]; then
        bash "$phase_script" || {
            echo -e "\033[0;31m  [✗] ${phase} failed\033[0m"
            ((failed++))
        }
    else
        echo -e "\033[1;33m  [!] ${phase} not found, skipping\033[0m"
    fi
done

echo ""
echo "════════════════════════════════════════════════════"
if ((failed == 0)); then
    echo -e "  \033[0;32mAll phases complete.\033[0m"
else
    echo -e "  \033[0;31m${failed} phase(s) had errors.\033[0m"
fi
echo ""
echo "  Next steps:"
echo "    1. Restart the gateway: sudo systemctl restart <service-name>"
echo "    2. Send a test message on Telegram"
echo "    3. Run: openclaw doctor"
echo ""
