#!/bin/bash
# setup.sh — One-command OpenClaw (Gregor) installer for Ubuntu 24.04 VPS
#
# Takes a fresh Ubuntu 22.04+ server and gets an OpenClaw Telegram bot running.
# 13 idempotent steps: prerequisites, hardening, Node.js, OpenClaw, config, systemd.
#
# Usage:
#   sudo bash setup.sh                                                        # Interactive
#   OPENCLAW_TELEGRAM_TOKEN="..." sudo -E bash setup.sh --non-interactive     # Automated
#   sudo bash setup.sh --dry-run                                              # Preview
#   sudo bash setup.sh --help
#
# Security: Secrets via env vars or read -s prompts — NEVER via CLI flags.
#   All output logged to /var/log/openclaw-setup.log with secrets redacted.
set -euo pipefail

readonly SETUP_VERSION="1.0.0" USER_NAME="openclaw" TOTAL=13
readonly USER_HOME="/home/${USER_NAME}" OC_DIR="/home/${USER_NAME}/.openclaw"
readonly NPM_GLOBAL="/home/${USER_NAME}/.npm-global"
readonly LOG_FILE="/var/log/openclaw-setup.log" UNIT="/etc/systemd/system/openclaw.service"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;34m'
BOLD='\033[1m' NC='\033[0m'

DRY_RUN=false NON_INTERACTIVE=false RECONCILE=false SSH_KEY=""
TELEGRAM_TOKEN="${OPENCLAW_TELEGRAM_TOKEN:-}"
PROVIDER="${OPENCLAW_PROVIDER:-}"
API_KEY="${OPENCLAW_API_KEY:-}"
declare -a SECRETS_TO_REDACT=()

# --- Helpers ----------------------------------------------------------------
step()  { echo "" ; echo -e "${BOLD}[Step ${1}/${TOTAL}] ${2}${NC}" ; echo "--------------------------------------------"; }
info()  { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
skip()  { echo -e "  ${YELLOW}[SKIP]${NC}  $1"; }
err()   { echo -e "  ${RED}[ERROR]${NC} $1"; }
dry()   { echo -e "  ${BLUE}[DRY]${NC}   Would: $1"; }
die()   { err "$1"; exit 1; }
as_oc() { su - "$USER_NAME" -c "$1"; }

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(while IFS= read -r line; do
        local out="$line"
        for s in "${SECRETS_TO_REDACT[@]:-}"; do
            [[ -n "$s" && ${#s} -gt 4 ]] && out="${out//$s/***REDACTED***}" || true
        done
        echo "$out" >> "$LOG_FILE"; echo "$out"
    done) 2>&1
}

# --- Argument parsing -------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)         DRY_RUN=true; shift ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --reconcile)       RECONCILE=true; shift ;;
            --ssh-key)         [[ $# -lt 2 ]] && die "--ssh-key requires a value"; SSH_KEY="$2"; shift 2 ;;
            --help|-h)         show_help; exit 0 ;;
            *)                 die "Unknown option: $1 (try --help)" ;;
        esac
    done
}

show_help() { cat <<'EOF'
setup.sh — One-command OpenClaw (Gregor) installer

Usage:
  sudo bash setup.sh                       Interactive (prompts for secrets)
  sudo bash setup.sh --dry-run             Preview all steps
  sudo bash setup.sh --non-interactive     Use env vars for secrets
  sudo bash setup.sh --reconcile           Validate/fix drifted state (steps 4/5/11)
  sudo bash setup.sh --help                This message

Flags:
  --ssh-key "key"    SSH public key for the openclaw user (not a secret)

Env vars (--non-interactive):
  OPENCLAW_TELEGRAM_TOKEN   Bot token from @BotFather
  OPENCLAW_PROVIDER         anthropic | openrouter | openai
  OPENCLAW_API_KEY          Provider API key
EOF
}

prompt_secrets() {
    $NON_INTERACTIVE && return
    echo ""; echo -e "${BOLD}Secret Configuration${NC} (hidden input, never logged)"; echo ""
    if [[ -z "$TELEGRAM_TOKEN" ]]; then
        echo -n "  Telegram bot token (from @BotFather, Enter to skip): "; read -rs TELEGRAM_TOKEN; echo ""
    fi
    if [[ -z "$PROVIDER" ]]; then
        echo -n "  LLM provider (anthropic/openrouter/openai, Enter=anthropic): "; read -r PROVIDER
        PROVIDER="${PROVIDER:-anthropic}"
    fi
    if [[ -z "$API_KEY" ]]; then
        echo -n "  API key for ${PROVIDER} (Enter to skip, use OAuth later): "; read -rs API_KEY; echo ""
    fi
}

register_secrets() {
    [[ -n "$TELEGRAM_TOKEN" ]] && SECRETS_TO_REDACT+=("$TELEGRAM_TOKEN") || true
    [[ -n "$API_KEY" ]]        && SECRETS_TO_REDACT+=("$API_KEY")        || true
}

# --- Step 1: Prerequisites --------------------------------------------------
step_01() {
    step 1 "Validating prerequisites"
    [[ $EUID -ne 0 ]] && die "Must run as root (use: sudo bash setup.sh)"
    ok "Running as root"
    [[ ! -f /etc/os-release ]] && die "Cannot detect OS"
    # Read only what we need (sourcing os-release sets many globals)
    local ID VERSION_ID
    ID=$(. /etc/os-release && echo "$ID")
    VERSION_ID=$(. /etc/os-release && echo "$VERSION_ID")
    [[ "$ID" != "ubuntu" ]] && die "Requires Ubuntu (detected: ${ID})"
    local major; major=$(echo "$VERSION_ID" | cut -d. -f1)
    (( major < 22 )) && die "Ubuntu 22.04+ required (detected: ${VERSION_ID})"
    ok "Ubuntu ${VERSION_ID}"
    ping -c1 -W3 1.1.1.1 &>/dev/null || die "No internet connectivity"
    ok "Internet OK"
}

# --- Step 2: System update --------------------------------------------------
step_02() {
    step 2 "System update"
    if $DRY_RUN; then dry "apt update && apt upgrade -y"; return; fi
    info "Updating packages..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    ok "System updated"
}

# --- Step 3: Create user ----------------------------------------------------
step_03() {
    step 3 "Creating openclaw user"
    if id "$USER_NAME" &>/dev/null; then ok "User '${USER_NAME}' exists"; return; fi
    if $DRY_RUN; then dry "useradd -m -s /bin/bash ${USER_NAME}"; return; fi
    useradd -m -s /bin/bash "$USER_NAME"
    ok "Created user '${USER_NAME}'"
}

# --- Step 4: SSH key ---------------------------------------------------------
step_04() {
    step 4 "SSH key setup"
    if [[ -z "$SSH_KEY" ]]; then skip "No --ssh-key provided"; return; fi
    local auth="${USER_HOME}/.ssh/authorized_keys"
    if [[ -f "$auth" ]] && grep -qF "$SSH_KEY" "$auth" && ! $RECONCILE; then
        ok "SSH key already present"; return
    fi
    if $DRY_RUN; then dry "Add key to ${auth}"; return; fi
    mkdir -p "${USER_HOME}/.ssh"
    if [[ ! -f "$auth" ]] || ! grep -qF "$SSH_KEY" "$auth"; then
        echo "$SSH_KEY" >> "$auth"
    fi
    chmod 700 "${USER_HOME}/.ssh"; chmod 600 "$auth"
    chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.ssh"
    ok "SSH key added"
}

# --- Step 5: Firewall -------------------------------------------------------
step_05() {
    step 5 "Firewall (ufw)"
    if ufw status 2>/dev/null | grep -q "Status: active" && ! $RECONCILE; then
        ok "ufw already active"; return
    fi
    if $DRY_RUN; then dry "ufw deny incoming, allow outgoing, allow ssh"; return; fi
    command -v ufw &>/dev/null || apt-get install -y -qq ufw
    ufw default deny incoming; ufw default allow outgoing; ufw allow ssh
    echo "y" | ufw enable
    ok "Firewall configured"
}

# --- Step 6: Unattended upgrades --------------------------------------------
step_06() {
    step 6 "Unattended security updates"
    if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'; then
        ok "unattended-upgrades installed"; return
    fi
    if $DRY_RUN; then dry "apt install unattended-upgrades"; return; fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
    ok "Unattended upgrades enabled"
}

# --- Step 7: Node.js 22.x ---------------------------------------------------
step_07() {
    step 7 "Installing Node.js 22.x"
    if command -v node &>/dev/null; then
        local v; v=$(node --version | sed 's/v//' | cut -d. -f1)
        if (( v >= 22 )); then ok "Node.js $(node --version) installed"; return; fi
        info "Node $(node --version) too old, upgrading..."
    fi
    if $DRY_RUN; then dry "Install Node.js 22.x via NodeSource"; return; fi
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    apt-get install -y -qq nodejs
    ok "Node.js $(node --version) installed"
}

# --- Step 8: Install OpenClaw -----------------------------------------------
step_08() {
    step 8 "Installing OpenClaw"
    if [[ -x "${NPM_GLOBAL}/bin/openclaw" ]]; then
        local v; v=$(as_oc "export PATH=${NPM_GLOBAL}/bin:\$PATH && openclaw --version" 2>/dev/null || echo "?")
        ok "OpenClaw ${v} installed"; return
    fi
    if $DRY_RUN; then dry "npm install -g openclaw as ${USER_NAME}"; return; fi
    as_oc "mkdir -p ${NPM_GLOBAL} && npm config set prefix ${NPM_GLOBAL}"
    as_oc "grep -q 'npm-global/bin' ~/.bashrc 2>/dev/null || echo 'export PATH=\$HOME/.npm-global/bin:\$HOME/.local/bin:\$PATH' >> ~/.bashrc"
    info "Installing OpenClaw (may take a minute)..."
    as_oc "export PATH=${NPM_GLOBAL}/bin:\$PATH && npm install -g openclaw" 2>&1 | tail -3
    local v; v=$(as_oc "export PATH=${NPM_GLOBAL}/bin:\$PATH && openclaw --version" 2>/dev/null || echo "?")
    ok "OpenClaw ${v} installed"
}

# --- Step 9: Config template (python3 JSON) ----------------------------------
step_09() {
    step 9 "Deploying config template"
    local cfg="${OC_DIR}/openclaw.json"
    if [[ -f "$cfg" ]]; then skip "Config exists at ${cfg} (not overwriting)"; return; fi
    if $DRY_RUN; then dry "Generate ${cfg} via python3"; return; fi
    as_oc "mkdir -p ${OC_DIR}"
    # Project convention: python3 for ALL JSON generation (never heredoc)
    _SETUP_TELEGRAM="$TELEGRAM_TOKEN" _SETUP_PROVIDER="${PROVIDER:-anthropic}" \
    _SETUP_API_KEY="$API_KEY" python3 -c "
import json, os
cfg = {
    'server': {'port': 18789, 'host': '127.0.0.1'},
    'agents': {'defaults': {
        'contextPruning': {'mode': 'cache-ttl', 'ttl': '2h', 'keepLastAssistants': 8},
        'compaction': {'mode': 'safeguard', 'memoryFlush': {
            'enabled': True,
            'prompt': 'Write any lasting notes to memory/daily/YYYY-MM-DD.md (use today s date); reply with NO_REPLY if nothing to store.'}},
        'blockStreamingDefault': 'off', 'maxConcurrent': 4}},
    'tools': {'profile': 'full', 'alsoAllow': ['cron'], 'deny': ['gateway', 'nodes'],
              'exec': {'security': 'full'}},
    'plugins': {'enabled': True, 'slots': {'memory': 'memory-core'},
                'entries': {'telegram': {'enabled': True}, 'memory-core': {'enabled': True}}},
    'gateway': {'port': 18789, 'mode': 'local', 'bind': 'loopback'},
    'discovery': {'mdns': {'mode': 'off'}}
}
t = os.environ.get('_SETUP_TELEGRAM', '')
if t:
    cfg['channels'] = {'telegram': {'enabled': True, 'botToken': t, 'dmPolicy': 'pairing',
        'groupPolicy': 'allowlist', 'groups': {}, 'streamMode': 'off', 'blockStreaming': False}}
    cfg['messages'] = {'ackReactionScope': 'group-mentions'}
    cfg['session'] = {'dmScope': 'per-channel-peer'}
print(json.dumps(cfg, indent=2))
" > /tmp/_oc_setup_cfg.json || die "python3 config generation failed"
    mv /tmp/_oc_setup_cfg.json "$cfg"
    chown "${USER_NAME}:${USER_NAME}" "$cfg"; chmod 600 "$cfg"
    ok "Config deployed to ${cfg}"
    [[ -z "$TELEGRAM_TOKEN" ]] && info "Add Telegram token later in ${cfg}" || true
    [[ -z "$API_KEY" ]] && info "Configure auth: openclaw models auth setup-token --provider ${PROVIDER:-anthropic}" || true
}

# --- Step 10: Telegram channel -----------------------------------------------
step_10() {
    step 10 "Configuring Telegram channel"
    if [[ -z "$TELEGRAM_TOKEN" ]]; then skip "No token — configure later"; return; fi
    local cfg="${OC_DIR}/openclaw.json"
    [[ ! -f "$cfg" ]] && { skip "Config missing — Telegram added when config exists"; return; }
    # Check if token already present
    if python3 -c "
import json,sys
with open('${cfg}') as f: c=json.load(f)
sys.exit(0 if c.get('channels',{}).get('telegram',{}).get('botToken','') else 1)
" 2>/dev/null; then ok "Telegram already configured"; return; fi
    if $DRY_RUN; then dry "Inject Telegram token into config"; return; fi
    _SETUP_TELEGRAM="$TELEGRAM_TOKEN" python3 -c "
import json,os
p='${cfg}'
with open(p) as f: c=json.load(f)
c.setdefault('channels',{})['telegram']={'enabled':True,
    'botToken':os.environ['_SETUP_TELEGRAM'],'dmPolicy':'pairing',
    'groupPolicy':'allowlist','groups':{},'streamMode':'off','blockStreaming':False}
c.setdefault('messages',{})['ackReactionScope']='group-mentions'
c.setdefault('session',{})['dmScope']='per-channel-peer'
with open(p,'w') as f: json.dump(c,f,indent=2)
" || die "Failed to update Telegram config"
    ok "Telegram configured"
}

# --- Step 11: systemd service ------------------------------------------------
step_11() {
    step 11 "Creating systemd service"
    if [[ -f "$UNIT" ]] && ! $RECONCILE; then ok "Unit exists at ${UNIT}"; return; fi
    if $DRY_RUN; then dry "Create ${UNIT} with hardening"; return; fi
    cat > "$UNIT" <<'SVC'
[Unit]
Description=OpenClaw AI Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw/.openclaw
Environment=PATH=/home/openclaw/.npm-global/bin:/home/openclaw/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/openclaw/.npm-global/bin/openclaw
Restart=on-failure
RestartSec=10
StartLimitBurst=5
StartLimitIntervalSec=300

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/openclaw/.openclaw /home/openclaw/scripts
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload; systemctl enable openclaw
    ok "systemd service created and enabled"
}

# --- Step 12: Monitoring (delegates to install.sh) ---------------------------
step_12() {
    step 12 "Deploying monitoring scripts"
    local repo; repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ ! -f "${repo}/install.sh" ]]; then
        skip "install.sh not found — deploy monitoring manually"; return
    fi
    if $DRY_RUN; then
        dry "Run install.sh as ${USER_NAME}"
        as_oc "cd ${repo} && bash install.sh --dry-run" 2>/dev/null || true; return
    fi
    # install.sh MUST run as openclaw (never root) to get correct $HOME
    info "Running install.sh as ${USER_NAME}..."
    as_oc "cd ${repo} && bash install.sh" 2>&1 || err "install.sh had errors (non-fatal)"
    # Logrotate needs root
    local lr_src="${repo}/src/config/logrotate-openclaw"
    if [[ -f "$lr_src" && ! -f /etc/logrotate.d/openclaw ]]; then cp "$lr_src" /etc/logrotate.d/openclaw; fi
    ok "Monitoring deployed"
}

# --- Step 13: Verification + next steps --------------------------------------
step_13() {
    step 13 "Final verification"
    local pass=true
    id "$USER_NAME" &>/dev/null             && ok "User: ${USER_NAME}"          || { err "User missing";       pass=false; }
    command -v node &>/dev/null              && ok "Node: $(node --version)"     || { err "Node.js missing";    pass=false; }
    [[ -x "${NPM_GLOBAL}/bin/openclaw" ]]   && ok "OpenClaw binary present"     || { err "OpenClaw missing";   pass=false; }
    [[ -f "${OC_DIR}/openclaw.json" ]]       && ok "Config present"              || { err "Config missing";     pass=false; }
    [[ -f "$UNIT" ]]                         && ok "systemd unit present"        || { err "Unit missing";       pass=false; }
    ufw status 2>/dev/null | grep -q "active" && ok "Firewall active"           || { err "Firewall inactive";  pass=false; }
    local n=0; for s in backup.sh health-check.sh auto-update.sh verify-binding.sh; do
        [[ -x "${USER_HOME}/scripts/${s}" ]] && ((n++)) || true; done
    if (( n == 4 )); then ok "Monitoring: 4/4 scripts"; else info "Monitoring: ${n}/4 scripts"; fi

    echo ""
    echo "==========================================================="
    $pass && echo -e "  ${GREEN}${BOLD}Setup complete!${NC}" \
          || echo -e "  ${YELLOW}${BOLD}Setup finished with warnings${NC}"
    echo "==========================================================="
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    [[ -z "$TELEGRAM_TOKEN" ]] && echo "  1. Add Telegram token: message @BotFather, add to ${OC_DIR}/openclaw.json" || true
    [[ -z "$API_KEY" ]] && cat <<MSG || true
  2. Configure AI provider (SSH as openclaw):
       export PATH=\$HOME/.npm-global/bin:\$PATH
       openclaw models auth setup-token --provider ${PROVIDER:-anthropic}
MSG
    cat <<MSG
  3. Start the service:
       sudo systemctl start openclaw    # wait 10-15s for init
       sudo systemctl status openclaw
  4. Send your bot a message on Telegram!
  5. Full guide: GUIDE.md

  Log: ${LOG_FILE}
MSG
}

# --- Main --------------------------------------------------------------------
main() {
    parse_args "$@"
    echo ""; echo "==========================================================="
    echo "  OpenClaw (Gregor) VPS Installer v${SETUP_VERSION}"
    $DRY_RUN   && echo "  Mode: DRY RUN"   || true
    $RECONCILE && echo "  Mode: RECONCILE" || true
    echo "==========================================================="

    step_01                         # Validates root + Ubuntu (before logging)
    prompt_secrets; register_secrets
    setup_logging                   # Logging starts here (after secrets registered)

    echo ""; echo "Setup started at $(date -Iseconds)"
    echo "Flags: dry_run=${DRY_RUN} non_interactive=${NON_INTERACTIVE} reconcile=${RECONCILE}"

    step_02; step_03; step_04; step_05; step_06; step_07
    step_08; step_09; step_10; step_11; step_12; step_13
}

main "$@"
