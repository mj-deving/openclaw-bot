#!/usr/bin/env bash
# 02-identity.sh — Phase 8: Bot Identity & Behavior
# Deploys AGENTS.md to workspace from template or custom file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "8" "Bot Identity & Behavior"

applied=0
skipped=0

WORKSPACE="${OPENCLAW_DIR}/workspace"
AGENTS_FILE="${WORKSPACE}/AGENTS.md"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# ── Ensure workspace exists ─────────────────────────────
if [[ ! -d "$WORKSPACE" ]]; then
    mkdir -p "$WORKSPACE"
    log_done "Created workspace directory"
fi

# ── AGENTS.md ───────────────────────────────────────────
STEP="identity.agents_md"
if is_step_done "$STEP"; then
    log_skip "AGENTS.md deployed"
    skipped=$((skipped + 1))
elif [[ -f "$AGENTS_FILE" ]]; then
    log_skip "AGENTS.md already exists at ${AGENTS_FILE}"
    mark_step_done "$STEP"
    skipped=$((skipped + 1))
else
    log_todo "Deploy AGENTS.md to workspace"
    echo ""
    echo -e "  ${CYAN}Available templates:${NC}"
    echo -e "    ${BOLD}1)${NC} default     — Minimal identity (name + boundaries)"
    echo -e "    ${BOLD}2)${NC} assistant   — Conversational assistant persona"
    echo -e "    ${BOLD}3)${NC} custom      — Provide your own file path"
    echo ""

    if [[ "${AUTO_YES:-}" == "true" ]]; then
        choice="1"
    else
        read -rp "  Choose template [1/2/3]: " choice
    fi

    case "${choice}" in
        1)
            template="${TEMPLATE_DIR}/agents-default.md"
            ;;
        2)
            template="${TEMPLATE_DIR}/agents-assistant.md"
            ;;
        3)
            read -rp "  Path to AGENTS.md: " template
            if [[ ! -f "$template" ]]; then
                log_error "File not found: $template"
                exit 1
            fi
            ;;
        *)
            log_warn "Invalid choice, using default template"
            template="${TEMPLATE_DIR}/agents-default.md"
            ;;
    esac

    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        log_info "Run from the repo: src/scripts/harden/02-identity.sh"
        exit 1
    fi

    # Prompt for bot name
    if [[ "${AUTO_YES:-}" == "true" ]]; then
        bot_name="Assistant"
    else
        read -rp "  Bot name (e.g., Gregor, Dismas): " bot_name
        bot_name="${bot_name:-Assistant}"
    fi

    # Deploy template with name substitution
    sed "s/{{BOT_NAME}}/${bot_name}/g" "$template" > "$AGENTS_FILE"
    mark_step_done "$STEP"
    log_done "AGENTS.md deployed (template: $(basename "$template"), name: ${bot_name})"
    applied=$((applied + 1))
fi

# ── Session scope ───────────────────────────────────────
STEP="identity.session_scope"
if is_step_done "$STEP"; then
    log_skip "session scope configured"
    skipped=$((skipped + 1))
else
    log_todo "Setting session scope to per-channel-peer"
    log_info "Each Telegram user gets their own conversation thread."
    if confirm; then
        config_set "session.dmScope" '"per-channel-peer"'
        mark_step_done "$STEP"
        log_done "dmScope = per-channel-peer"
        applied=$((applied + 1))
    fi
fi

# ── Native commands ─────────────────────────────────────
STEP="identity.commands"
if is_step_done "$STEP"; then
    log_skip "native commands configured"
    skipped=$((skipped + 1))
else
    log_todo "Enabling native commands and skills in chat"
    if confirm; then
        config_set "commands.native" '"auto"'
        config_set "commands.nativeSkills" '"auto"'
        mark_step_done "$STEP"
        log_done "native commands = auto, skills = auto"
        applied=$((applied + 1))
    fi
fi

log_summary "$applied" "$skipped"

if [ "$applied" -gt 0 ]; then
    log_warn "Restart the gateway to apply: sudo systemctl restart <service-name>"
fi
