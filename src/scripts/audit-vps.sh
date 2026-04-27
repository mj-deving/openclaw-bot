#!/usr/bin/env bash
# audit-vps.sh — client-side read-only audit of Gregor on the VPS
#
# WHY THIS EXISTS:
#   On 2026-04-27 a multi-agent LLM audit issued parallel SSH probes and
#   triggered fail2ban on the VPS, locking us out for ~15 min. This script
#   is the resilient single-shot replacement: ONE SSH ControlMaster session,
#   sequential probes through that single channel, conservative timeouts.
#
# WHAT IT CHECKS (read-only, no state mutation):
#   - SSH reachability (with banner-timeout aware diagnostics)
#   - openclaw / ollama / clawmetry / defense-proxy systemd state
#   - Memory DB size + table row counts + last-write timestamp
#   - Defense plugin install state
#   - ClawKeeper presence + audit score (if installed)
#   - Cron list
#   - Config provider/model/embeddings (drift check)
#   - Last 24h journalctl error count
#
# USAGE:
#   src/scripts/audit-vps.sh                    # human-readable report
#   src/scripts/audit-vps.sh --json             # machine-readable JSON
#   src/scripts/audit-vps.sh --quick            # subset: services + memory only
#
# EXIT CODES:
#   0 — audit completed (any verdict)
#   1 — SSH unreachable (banner timeout / connection refused / fail2ban)
#   2 — usage error

set -euo pipefail

SSH_HOST="${SSH_HOST:-vps}"
SSH_TIMEOUT=20
SSH_OPTS=(
    -o "ConnectTimeout=${SSH_TIMEOUT}"
    -o "ServerAliveInterval=10"
    -o "ServerAliveCountMax=3"
    -o "ConnectionAttempts=1"
    -o "BatchMode=yes"
)

MODE="full"
OUTPUT="text"
for arg in "$@"; do
    case "$arg" in
        --json)  OUTPUT="json" ;;
        --quick) MODE="quick" ;;
        --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# --- Step 1: reachability gate (ONE probe, fail fast) ---
reachability_check() {
    # nc doesn't read ~/.ssh/config aliases — resolve the real hostname:port first
    local target port
    target=$(ssh -G "${SSH_HOST}" 2>/dev/null | awk '/^hostname / {print $2}')
    port=$(ssh -G "${SSH_HOST}" 2>/dev/null | awk '/^port / {print $2}')
    target="${target:-$SSH_HOST}"
    port="${port:-22}"

    # TCP-level check first — distinguishes "host down" from "SSH refusing"
    if ! nc -vz -w 15 "${target}" "${port}" >/dev/null 2>&1; then
        echo "FATAL: TCP/${port} unreachable on ${target}" >&2
        return 1
    fi
    # SSH-level check — single attempt, will fail fast if banner times out
    if ! ssh "${SSH_OPTS[@]}" "${SSH_HOST}" 'echo ok' >/dev/null 2>&1; then
        echo "FATAL: SSH banner exchange failed (likely fail2ban lockout or sshd overload)" >&2
        echo "  → wait 10-15 min for ban to expire, or unban from VPS console:" >&2
        echo "      sudo fail2ban-client status sshd" >&2
        echo "      sudo fail2ban-client unban <your-ip>" >&2
        return 1
    fi
    return 0
}

if ! reachability_check; then
    if [[ "$OUTPUT" == "json" ]]; then
        printf '{"verdict":"unreachable","reason":"ssh_banner_or_tcp_failure"}\n'
    fi
    exit 1
fi

# --- Step 2: open ONE SSH ControlMaster session for all probes ---
CONTROL_PATH="/tmp/audit-vps-$$.sock"
trap 'ssh -O exit -o "ControlPath=${CONTROL_PATH}" "${SSH_HOST}" 2>/dev/null || true; rm -f "${CONTROL_PATH}"' EXIT

ssh "${SSH_OPTS[@]}" \
    -o "ControlMaster=yes" \
    -o "ControlPath=${CONTROL_PATH}" \
    -o "ControlPersist=60" \
    -fN "${SSH_HOST}"

run() {
    # Run a remote command through the persistent connection.
    ssh -o "ControlPath=${CONTROL_PATH}" "${SSH_HOST}" "$@"
}

# --- Step 3: sequential probes (single SSH channel, no fail2ban risk) ---

# Service health
svc_openclaw=$(run 'sudo systemctl is-active openclaw 2>/dev/null || echo unknown')
svc_ollama=$(run 'systemctl --user is-active ollama 2>/dev/null || echo unknown')
svc_clawmetry=$(run 'systemctl --user is-active clawmetry 2>/dev/null || echo unknown')
svc_defense=$(run 'sudo systemctl is-active defense-proxy 2>/dev/null || echo absent')
gateway_uptime=$(run 'sudo systemctl show openclaw --property=ActiveEnterTimestamp --value 2>/dev/null || echo unknown')

# Memory DB
mem_size=$(run 'du -sh ~/.openclaw/memory/main.sqlite 2>/dev/null | awk "{print \$1}" || echo absent')

if [[ "$MODE" != "quick" ]]; then
    # Use a single python3 invocation for all sqlite probing (avoids multiple SSH hops)
    mem_stats=$(run 'python3 - <<PYEOF 2>/dev/null || echo "{\"error\":\"db_read_failed\"}"
import sqlite3, json, os
db = os.path.expanduser("~/.openclaw/memory/main.sqlite")
out = {}
try:
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type=\"table\" ORDER BY name")
    tables = [r[0] for r in cur.fetchall()]
    out["tables"] = tables
    counts = {}
    for t in tables:
        try:
            cur.execute(f"SELECT COUNT(*) FROM \"{t}\"")
            counts[t] = cur.fetchone()[0]
        except Exception as e:
            counts[t] = f"err:{e}"
    out["row_counts"] = counts
    # Try common timestamp columns to find last activity
    last = None
    for t in tables:
        for col in ("updated_at", "created_at", "ts", "timestamp"):
            try:
                cur.execute(f"SELECT MAX({col}) FROM \"{t}\"")
                v = cur.fetchone()[0]
                if v and (last is None or str(v) > str(last)):
                    last = f"{t}.{col}={v}"
            except Exception:
                pass
    out["last_activity"] = last
    con.close()
except Exception as e:
    out["error"] = str(e)
print(json.dumps(out))
PYEOF
')

    # Defense system
    def_skill=$(run 'ls -d ~/.openclaw/workspace/skills/security-defense 2>/dev/null && echo installed || echo absent' | tail -1)
    def_extensions=$(run 'ls ~/.openclaw/extensions/ 2>/dev/null | tr "\n" "," || echo none')

    # ClawKeeper
    if [[ "$def_extensions" == *clawkeeper* ]]; then
        ck_score=$(run 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"; openclaw clawkeeper audit --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get(\"score\",\"?\"))" 2>/dev/null || echo unavailable')
    else
        ck_score="not-installed"
    fi

    # Crons
    cron_list=$(run 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"; openclaw cron list 2>/dev/null | head -20' || echo "unavailable")

    # Config drift
    cfg_summary=$(run 'python3 -c "
import json,os,sys
p = os.path.expanduser(\"~/.openclaw/openclaw.json\")
try:
    c = json.load(open(p))
    out = {
      \"agents.defaults.model\": c.get(\"agents\",{}).get(\"defaults\",{}).get(\"model\"),
      \"memory.provider\": c.get(\"memory\",{}).get(\"provider\"),
      \"memory.model\": c.get(\"memory\",{}).get(\"model\"),
      \"compaction.provider\": c.get(\"compaction\",{}).get(\"provider\"),
      \"compaction.model\": c.get(\"compaction\",{}).get(\"model\"),
      \"channels.telegram.allowFrom\": (c.get(\"channels\",{}).get(\"telegram\",{}) or {}).get(\"allowFrom\"),
    }
    print(json.dumps(out))
except Exception as e:
    print(json.dumps({\"error\":str(e)}))
" 2>/dev/null')

    # Errors last 24h
    err_count=$(run 'sudo journalctl -u openclaw --since "24 hours ago" --no-pager 2>/dev/null | grep -ciE "error|warn|fail" || echo 0')
fi

# --- Step 4: render output ---
if [[ "$OUTPUT" == "json" ]]; then
    python3 -c "
import json, sys
out = {
  'verdict': 'reached',
  'services': {
    'openclaw': '''$svc_openclaw'''.strip(),
    'ollama': '''$svc_ollama'''.strip(),
    'clawmetry': '''$svc_clawmetry'''.strip(),
    'defense_proxy': '''$svc_defense'''.strip(),
    'gateway_started': '''$gateway_uptime'''.strip(),
  },
  'memory_size': '''$mem_size'''.strip(),
}
$([ "$MODE" != "quick" ] && cat <<EXTRA
out['memory_db'] = json.loads('''$mem_stats''')
out['defense'] = {'skill': '''$def_skill'''.strip(), 'extensions': '''$def_extensions'''.strip().rstrip(',')}
out['clawkeeper_score'] = '''$ck_score'''.strip()
out['cron_list'] = '''$cron_list'''.strip()
out['config'] = json.loads('''$cfg_summary''')
out['errors_24h'] = int('''$err_count'''.strip() or 0)
EXTRA
)
print(json.dumps(out, indent=2, default=str))
"
else
    cat <<EOF
═══ Gregor VPS Audit ═══════════════════════════════════
Generated: $(date -Iseconds)
Mode:      $MODE

── Services ────────────────────────────────────────────
  openclaw      : $svc_openclaw  (started: $gateway_uptime)
  ollama        : $svc_ollama
  clawmetry     : $svc_clawmetry
  defense-proxy : $svc_defense

── Memory ──────────────────────────────────────────────
  DB size: $mem_size
EOF

    if [[ "$MODE" != "quick" ]]; then
        cat <<EOF
  DB stats:
$(echo "$mem_stats" | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || echo "    (parse failed)")

── Defense System ──────────────────────────────────────
  security-defense skill : $def_skill
  extensions/            : $def_extensions
  ClawKeeper score       : $ck_score

── Crons ───────────────────────────────────────────────
$(echo "$cron_list" | sed 's/^/  /')

── Config (drift check) ────────────────────────────────
$(echo "$cfg_summary" | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  (parse failed)")

── Errors (last 24h) ───────────────────────────────────
  count: $err_count
EOF
    fi
    echo "════════════════════════════════════════════════════════"
fi
