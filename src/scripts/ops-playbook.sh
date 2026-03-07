#!/bin/bash
# OpenClaw Ops Playbook — diagnostic, root-cause, and auto-fix for the Gregor deployment
# Deployed to: ~/scripts/ops-playbook.sh on VPS
#
# Usage: ops-playbook.sh [check|diagnose|fix] [--json]
# Exit codes: 0=healthy  1=unhealthy(fixable)  2=unhealthy(needs human)  3=script error
#
# Token cost: Near-zero. Only `openclaw doctor` and `config validate` touch the bot.

set -euo pipefail
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"

# --- Config ------------------------------------------------------------------
HEALTH_URL="http://127.0.0.1:18789/health"
DB_PATH="$HOME/.openclaw/memory/main.sqlite"
OC_DIR="$HOME/.openclaw"
CURL_TIMEOUT=5
MEM_WARN_MB=1536; MEM_CRIT_MB=2048   # 1.5G warn, 2G critical
DISK_WARN_PCT=90; DB_WARN_MB=500
POLL_WINDOW=15                         # minutes
RESTART_STORM=5

# --- Globals -----------------------------------------------------------------
MODE="check"; JSON_OUT=false; STATUS="healthy"
CHECKS_JSON="[]"; TS=$(date -Iseconds)
RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'; BLD='\033[1m'; NC='\033[0m'

for arg in "$@"; do
  case "$arg" in
    check) MODE="check";; diagnose) MODE="diagnose";; fix) MODE="fix";;
    --json) JSON_OUT=true;;
    -h|--help) echo "Usage: $(basename "$0") [check|diagnose|fix] [--json]"; exit 0;;
    *) echo "Unknown: $arg" >&2; exit 3;;
  esac
done

# --- Helpers -----------------------------------------------------------------

# emit NAME STATUS MESSAGE [DIAGNOSIS]
# Single call that records JSON, prints human output, and escalates overall status.
emit() {
  local n="$1" s="$2" m="$3" d="${4:-}"
  case "$s" in
    critical) STATUS="critical";;
    warning)  [[ "$STATUS" != "critical" ]] && STATUS="warning";;
  esac
  CHECKS_JSON=$(python3 -c "
import json,sys
c=json.loads(sys.argv[1]); e={'name':sys.argv[2],'status':sys.argv[3],'message':sys.argv[4]}
if sys.argv[5]: e['diagnosis']=sys.argv[5]
c.append(e); print(json.dumps(c))
" "$CHECKS_JSON" "$n" "$s" "$m" "$d")
  $JSON_OUT && return
  local col="$GRN" icon="OK"
  case "$s" in warning) col="$YEL"; icon="WARN";; critical) col="$RED"; icon="CRIT";; esac
  printf "  %-22s [${col}%-4s${NC}]  %s\n" "$n" "$icon" "$m"
  [[ -n "$d" && "$MODE" != "check" ]] && echo -e "    ${YEL}-> ${d}${NC}"
}

fix_msg() { $JSON_OUT || echo -e "    ${BLD}FIX: $1${NC}"; }
has_cli() { command -v openclaw &>/dev/null; }
get_pid() { systemctl show -p MainPID --value openclaw 2>/dev/null || echo "0"; }

# --- 12 Diagnostic Checks ---------------------------------------------------

# 1. Service status
check_service() {
  if systemctl is-active --quiet openclaw 2>/dev/null; then
    emit service_status ok "Service active"; return 0; fi
  local st; st=$(systemctl show -p ActiveState --value openclaw 2>/dev/null || echo "unknown")
  emit service_status critical "Not active ($st)" "ActiveState=$st. Service is not running."
  if [[ "$MODE" == "fix" ]]; then
    fix_msg "Starting openclaw..."; systemctl start openclaw 2>/dev/null || true; sleep 3
    systemctl is-active --quiet openclaw 2>/dev/null && fix_msg "Started." || fix_msg "Failed. Needs human."
  fi; return 1
}

# 2. Process health — zombie/stuck detection via /proc
check_process() {
  local pid; pid=$(get_pid)
  if [[ "$pid" == "0" || -z "$pid" ]]; then
    emit process_health warning "No PID (service may be stopped)"; return 1; fi
  if [[ ! -d "/proc/$pid" ]]; then
    emit process_health critical "PID $pid missing from /proc"; return 1; fi
  local st thr
  st=$(awk '/^State:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "?")
  thr=$(awk '/^Threads:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "?")
  if [[ "$st" == "Z" ]]; then
    emit process_health critical "Zombie (PID $pid)" "State=Z. Needs restart or kill."; return 1; fi
  emit process_health ok "PID=$pid state=$st threads=$thr"
}

# 3. Gateway HTTP health endpoint
check_gateway() {
  local code; code=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" "$HEALTH_URL" 2>/dev/null) || true
  if [[ "$code" == "000" || -z "$code" ]]; then
    emit gateway_http critical "No response (${CURL_TIMEOUT}s timeout)" \
      "Gateway unresponsive. Could be crashed or in 10-15s startup window."
    if [[ "$MODE" == "fix" ]] && systemctl is-active --quiet openclaw 2>/dev/null; then
      fix_msg "Restarting openclaw..."; systemctl restart openclaw 2>/dev/null || true; sleep 12
    fi; return 1
  fi
  emit gateway_http ok "HTTP $code"
}

# 4. Binding — must be 127.0.0.1, never 0.0.0.0 (security-critical)
check_binding() {
  # ss peer column always shows 0.0.0.0:* for listeners — we match LOCAL address only
  if ss -tlnp 2>/dev/null | grep -q '0\.0\.0\.0:18789'; then
    emit binding critical "BOUND TO 0.0.0.0" "AI agent + API keys exposed to network."
    [[ "$MODE" == "fix" ]] && { fix_msg "STOPPING service immediately."; systemctl stop openclaw 2>/dev/null || true; }
    return 1
  fi
  emit binding ok "Loopback only (127.0.0.1)"
}

# 5. Memory usage — VmRSS from /proc (no external tools)
check_memory() {
  local pid; pid=$(get_pid)
  if [[ "$pid" == "0" || ! -f "/proc/$pid/status" ]]; then
    emit memory_usage warning "Cannot read (no PID)"; return 0; fi
  local kb; kb=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "0")
  local mb=$((kb / 1024))
  if   [[ $mb -ge $MEM_CRIT_MB ]]; then
    emit memory_usage critical "${mb}MB RSS" "Exceeds ${MEM_CRIT_MB}MB. Possible memory leak."; return 1
  elif [[ $mb -ge $MEM_WARN_MB ]]; then
    emit memory_usage warning "${mb}MB RSS" "Approaching critical. Monitor trend."; return 0
  fi
  emit memory_usage ok "${mb}MB RSS"
}

# 6. Disk space on the openclaw partition
check_disk() {
  local pct; pct=$(df "$OC_DIR" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5);print $5}')
  if [[ -z "$pct" ]]; then emit disk_space warning "Could not read df"; return 0; fi
  if [[ $pct -ge $DISK_WARN_PCT ]]; then
    emit disk_space critical "${pct}% used" "Risk of write failures at >${DISK_WARN_PCT}%."; return 1; fi
  emit disk_space ok "${pct}% used"
}

# 7. Journal error count (last hour, priority=err)
check_logs() {
  local n; n=$(journalctl -u openclaw --since "1 hour ago" -p err --no-pager -q 2>/dev/null | wc -l || echo 0)
  if   [[ $n -gt 20 ]]; then
    emit log_errors critical "$n errors/hr" "Run journalctl -u openclaw -p err."; return 1
  elif [[ $n -gt 5 ]]; then
    emit log_errors warning "$n errors/hr" "Elevated but not critical."
  else emit log_errors ok "$n errors/hr"; fi
}

# 8. Polling liveness — catches silent polling death (#7526)
#    Skip if no heartbeat cron (avoids false positives on idle bots).
check_polling() {
  if ! has_cli; then emit polling_liveness warning "CLI not in PATH"; return 0; fi
  local hb; hb=$(openclaw cron list 2>/dev/null | grep -ci heartbeat || echo 0)
  if [[ "$hb" == "0" ]]; then emit polling_liveness ok "Skipped (no heartbeat cron)"; return 0; fi
  local act; act=$(journalctl -u openclaw --since "${POLL_WINDOW} min ago" --no-pager -q 2>/dev/null \
    | grep -ciE '(telegram.*poll|getUpdates|inbound message)' || echo 0)
  if [[ "$act" == "0" ]]; then
    emit polling_liveness critical "No activity in ${POLL_WINDOW}min" "Possible silent polling death (#7526)."
    [[ "$MODE" == "fix" ]] && { fix_msg "Restarting to recover polling..."; systemctl restart openclaw 2>/dev/null || true; }
    return 1
  fi
  emit polling_liveness ok "$act events in ${POLL_WINDOW}min"
}

# 9. openclaw doctor (non-destructive self-check)
check_doctor() {
  if ! has_cli; then emit doctor warning "CLI not in PATH"; return 0; fi
  local out; out=$(openclaw doctor --json 2>&1) || true
  if echo "$out" | grep -qi "error\|fail\|issue"; then
    emit doctor warning "Issues found" "Run 'openclaw doctor --json' for details."
    if [[ "$MODE" == "fix" ]]; then
      for i in 1 2 3; do
        fix_msg "openclaw doctor --fix (attempt $i/3)..."; openclaw doctor --fix 2>&1 || true
        local re; re=$(openclaw doctor --json 2>&1) || true
        echo "$re" | grep -qi "error\|fail\|issue" || { fix_msg "Resolved."; break; }
      done
    fi; return 1
  fi
  emit doctor ok "No issues"
}

# 10. Database health — size, WAL mode, integrity (python3, no sqlite3 CLI)
check_database() {
  if [[ ! -f "$DB_PATH" ]]; then emit database warning "DB not found"; return 0; fi
  local r; r=$(python3 -c "
import sqlite3,os,json,sys; p=sys.argv[1]; d={}
d['size_mb']=round(os.path.getsize(p)/1048576,1)
try:
 c=sqlite3.connect(p,timeout=10).cursor()
 c.execute('PRAGMA journal_mode'); d['jm']=c.fetchone()[0]
 c.execute('PRAGMA integrity_check'); d['ic']=c.fetchone()[0]
except Exception as e: d['err']=str(e)
print(json.dumps(d))
" "$DB_PATH" 2>&1) || true
  local sm jm ic er
  sm=$(echo "$r"|python3 -c "import json,sys;print(json.load(sys.stdin).get('size_mb','?'))" 2>/dev/null||echo "?")
  jm=$(echo "$r"|python3 -c "import json,sys;print(json.load(sys.stdin).get('jm','?'))" 2>/dev/null||echo "?")
  ic=$(echo "$r"|python3 -c "import json,sys;print(json.load(sys.stdin).get('ic','?'))" 2>/dev/null||echo "?")
  er=$(echo "$r"|python3 -c "import json,sys;print(json.load(sys.stdin).get('err',''))" 2>/dev/null||echo "")
  if [[ -n "$er" ]]; then emit database critical "DB error" "$er"; return 1; fi
  if [[ "$ic" != "ok" ]]; then
    emit database critical "Integrity: $ic" "PRAGMA integrity_check failed. Possible corruption."; return 1; fi
  local si=${sm%.*}
  if [[ $si -ge $DB_WARN_MB ]]; then
    emit database warning "${sm}MB jm=$jm" ">${DB_WARN_MB}MB. Consider vacuuming."; return 0; fi
  emit database ok "${sm}MB jm=$jm integrity=$ic"
}

# 11. Config validation (never auto-restart on failure — prevents crash loops)
check_config() {
  if ! has_cli; then emit config_validation warning "CLI not in PATH"; return 0; fi
  local out; out=$(openclaw config validate 2>&1) || true
  if echo "$out" | grep -qi "error\|invalid\|fail"; then
    emit config_validation critical "Failed" "Do NOT restart until fixed. $(echo "$out"|head -1)"; return 1; fi
  emit config_validation ok "Valid"
}

# 12. Restart history — detect crash loops via systemd NRestarts counter
check_restarts() {
  local n; n=$(systemctl show -p NRestarts --value openclaw 2>/dev/null || echo 0)
  if [[ $n -ge $RESTART_STORM ]]; then
    emit restart_history warning "$n restarts" "Possible crash loop (threshold=$RESTART_STORM)."; return 0; fi
  emit restart_history ok "$n restarts"
}

# --- Main --------------------------------------------------------------------

$JSON_OUT || { echo -e "\n${BLD}=== OpenClaw Ops Playbook ($MODE) ===${NC}"; echo -e "${BLD}    $(date)${NC}\n"; }

check_service   || true
check_process   || true
check_gateway   || true
check_binding   || true
check_memory    || true
check_disk      || true
check_logs      || true
check_polling   || true
check_doctor    || true
check_database  || true
check_config    || true
check_restarts  || true

# --- Output ------------------------------------------------------------------
if $JSON_OUT; then
  python3 -c "
import json,sys
print(json.dumps({'status':sys.argv[1],'timestamp':sys.argv[2],'mode':sys.argv[3],
  'checks':json.loads(sys.argv[4])},indent=2))
" "$STATUS" "$TS" "$MODE" "$CHECKS_JSON"
else
  echo ""
  case "$STATUS" in
    healthy)  echo -e "  ${GRN}${BLD}OVERALL: HEALTHY${NC}";;
    warning)  echo -e "  ${YEL}${BLD}OVERALL: WARNING${NC}";;
    critical) echo -e "  ${RED}${BLD}OVERALL: CRITICAL${NC}";;
  esac; echo ""
fi

case "$STATUS" in healthy) exit 0;; warning) exit 1;; critical) exit 2;; esac
