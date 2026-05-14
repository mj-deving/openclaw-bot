#!/usr/bin/env bash
# config-invariants.sh — assert load-bearing config invariants on a deployed OpenClaw bot
#
# WHY THIS EXISTS:
#   Bug-class first-class concern. We have suffered three production incidents whose
#   root cause was a config field that was syntactically valid but operationally wrong:
#
#     1. v2026.4.x → v2026.5.x: legacy embeddedHarness.fallback keys → 2000-attempt
#        restart loop (KNOWN-BUGS #12).
#     2. agents.defaults.subagents.model = "openrouter/..." (string) → ALL subagents
#        silently routed to a key-based model regardless of the main agent's OAuth
#        (KNOWN-BUGS #13).
#     3. Codex agent in agents.list[] using "openai/gpt-5.4" (key-based) instead of
#        "openai-codex/gpt-5.4" (OAuth) → silent auth fallback chain on subagent runs.
#
#   This script asserts the invariants that protect against those three. It is read-only
#   (no SSH writes, no config mutation) and exits non-zero on failure so it can be wired
#   into auto-update.sh, audit-vps.sh, and the post-restart canary path.
#
# WHAT IT CHECKS (read-only, single SSH session):
#   I1: agents.defaults.embeddedHarness has no `fallback` field
#       (legacy poison; rejected by v2026.5.x schema; restart-loops the gateway)
#   I2: agents.defaults.subagents.model is the OBJECT form with primary on the OAuth
#       provider and EMPTY fallbacks (no key-based silent fallback for subagents)
#   I3: every agent in agents.list[] using a Codex runtime has model prefixed with
#       "openai-codex/" (not "openai/") so it actually uses OAuth
#   I4: channels.telegram.threadBindings (if present) uses the modern collapsed form —
#       no legacy spawnSubagentSessions/spawnAcpSessions keys
#   I5: if Crabbox plugin is installed AND a Crabbox provider is configured (.crabbox.yaml
#       in workspace or repo), `crabbox doctor --provider <provider>` exits 0. Crabbox
#       doctor is local-only, never billable; an exit-2 here means a Crabbox-routed
#       task would fail at runtime (missing CLI binary, plugin not loaded, provider
#       auth absent, key permission wrong, etc.). Gates the Telegram-routed Crabbox
#       lane per Reference/CRABBOX-HARDENING.md §10 rule #11.
#   I6: agents.defaults.model.fallbacks is EMPTY. Hard fail-closed on the main agent
#       lane. Previous chains (Codex → Sonnet → Haiku → free) caused SILENT
#       DEGRADATION — Marius experienced multi-turn conversations on free-tier models
#       without noticing, with badly degraded responses (tool-use forgotten,
#       filesystem-fishing instead of typed tool calls, e.g. the 2026-05-14 Crabbox
#       smoke). Doctrine: same logic as the I2 subagent fail-closed invariant.
#       Visibility > availability. Bot recovery path when Codex fails: /model slash
#       command in Telegram opens a channel-side keyboard UI (handled by the Telegram
#       plugin pre-LLM, no LLM call required) — operator picks a different model.
#
# USAGE:
#   src/scripts/config-invariants.sh                 # human report, exit 0/1
#   src/scripts/config-invariants.sh --json          # JSON report, exit 0/1
#   src/scripts/config-invariants.sh --host gregor   # override SSH host
#
# EXIT CODES:
#   0 — all invariants hold
#   1 — at least one invariant violated (or SSH/jq failure)
#   2 — usage error

set -euo pipefail

SSH_HOST="${SSH_HOST:-vps}"
SSH_OPTS=(-o "ConnectTimeout=20" -o "BatchMode=yes")
OUTPUT="text"

for arg in "$@"; do
    case "$arg" in
        --json)         OUTPUT="json" ;;
        --host)         shift; SSH_HOST="${1:-$SSH_HOST}" ;;
        --help|-h)      sed -n '2,40p' "$0"; exit 0 ;;
        *)              echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# Pull the live config in one SSH round-trip.
CONFIG_JSON=$(ssh "${SSH_OPTS[@]}" "${SSH_HOST}" \
    "sudo -u openclaw cat /home/openclaw/.openclaw/openclaw.json" 2>/dev/null) || {
    echo "FATAL: could not read config via ssh ${SSH_HOST}" >&2
    exit 1
}

# I5: Crabbox lane gate. Probes whether a Crabbox-routed task would fail at
# runtime. Plugin presence comes from the OpenClaw plugins config; provider
# comes from the openclaw user's workspace .crabbox.yaml or repo-local
# .crabbox.yaml. Then the check splits by provider kind:
#   - brokered  (hetzner, aws, azure, gcp, proxmox, ssh) → `crabbox doctor`
#   - delegated (e2b, modal, daytona, islo, tensorlake)  → doctor does NOT
#     support these at v0.13.0 (silently falls back to hetzner). Instead,
#     verify the expected env-var secret is present in the openclaw service
#     environment (presence only, never value).
# Verified 2026-05-14 against `crabbox doctor --help`: -provider enum is
# hetzner|aws|azure|gcp|proxmox|ssh only.
CRABBOX_PROBE=$(ssh "${SSH_OPTS[@]}" "${SSH_HOST}" '
    set +e
    # sudo strips PATH, so reach OpenClaw + Crabbox via absolute paths.
    if ! sudo -u openclaw /home/openclaw/.npm-global/bin/openclaw plugins inspect crabbox 2>/dev/null | grep -q "^Status: loaded"; then
        echo "{\"applicable\":false,\"reason\":\"plugin not installed or not loaded\"}"
        exit 0
    fi
    PROVIDER=""
    for cfg in /home/openclaw/.openclaw/workspace/.crabbox.yaml \
               /home/openclaw/.openclaw/workspace/.crabbox.yml \
               /home/openclaw/.openclaw/.crabbox.yaml ; do
        if sudo -u openclaw test -r "$cfg"; then
            PROVIDER=$(sudo -u openclaw grep -E "^provider:" "$cfg" | head -1 | sed -E "s/^provider:[[:space:]]*//; s/[[:space:]]*#.*//; s/[\"'\'']*//g")
            [[ -n "$PROVIDER" ]] && break
        fi
    done
    if [[ -z "$PROVIDER" ]]; then
        echo "{\"applicable\":false,\"reason\":\"no provider configured\"}"
        exit 0
    fi
    case "$PROVIDER" in
        hetzner|aws|azure|gcp|proxmox|ssh)
            sudo -u openclaw /home/openclaw/.local/bin/crabbox doctor --provider "$PROVIDER" >/tmp/crabbox-doctor.out 2>&1
            CODE=$?
            TAIL=$(sudo -u openclaw tail -5 /tmp/crabbox-doctor.out | tr -d "\r" | head -c 600 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
            echo "{\"applicable\":true,\"kind\":\"brokered\",\"provider\":\"$PROVIDER\",\"check\":\"doctor\",\"exit\":$CODE,\"tail\":$TAIL}"
            ;;
        e2b)       SECRET_VAR="E2B_API_KEY" ;;&
        modal)     SECRET_VAR="MODAL_TOKEN_ID" ;;&
        daytona)   SECRET_VAR="DAYTONA_API_KEY" ;;&
        islo)      SECRET_VAR="ISLO_API_KEY" ;;&
        tensorlake)SECRET_VAR="TENSORLAKE_API_KEY" ;;&
        e2b|modal|daytona|islo|tensorlake)
            if sudo systemctl show openclaw -p Environment 2>/dev/null | grep -q "$SECRET_VAR="; then
                echo "{\"applicable\":true,\"kind\":\"delegated\",\"provider\":\"$PROVIDER\",\"check\":\"secret_present\",\"secret_var\":\"$SECRET_VAR\",\"exit\":0}"
            else
                echo "{\"applicable\":true,\"kind\":\"delegated\",\"provider\":\"$PROVIDER\",\"check\":\"secret_present\",\"secret_var\":\"$SECRET_VAR\",\"exit\":2,\"reason\":\"$SECRET_VAR not in openclaw service Environment\"}"
            fi
            ;;
        *)
            echo "{\"applicable\":true,\"kind\":\"unknown\",\"provider\":\"$PROVIDER\",\"exit\":2,\"reason\":\"unknown provider for I5 routing\"}"
            ;;
    esac
' 2>/dev/null) || CRABBOX_PROBE='{"applicable":false,"reason":"probe ssh failed"}'

# Run all checks via one jq invocation so the report stays atomic.
REPORT=$(printf '%s' "$CONFIG_JSON" | jq -e --argjson crabbox "$CRABBOX_PROBE" '
{
    invariants: {
        I1_no_legacy_embedded_harness_fallback: (
            (((.agents.defaults.embeddedHarness // {}) | has("fallback")) | not)
            and (([.agents.list[]?.embeddedHarness // {} | has("fallback")] | any) | not)
        ),
        I2_subagent_model_oauth_failclosed: (
            ((.agents.defaults.subagents.model | type) == "object")
            and ((.agents.defaults.subagents.model.primary // "" | startswith("openai-codex/")))
            and (((.agents.defaults.subagents.model.fallbacks // ["nonempty"]) | length) == 0)
        ),
        I3_codex_agents_use_oauth_prefix: (
            [.agents.list[]?
              | select((.agentRuntime.id // "") == "codex" or (.embeddedHarness.runtime // "") == "codex")
              | (.model // "") | startswith("openai-codex/")
            ] | all
        ),
        I4_telegram_thread_modern_form: (
            ((.channels.telegram.threadBindings // null) == null)
            or (
                ((.channels.telegram.threadBindings | has("spawnSubagentSessions")) | not)
                and ((.channels.telegram.threadBindings | has("spawnAcpSessions")) | not)
            )
        ),
        I5_crabbox_doctor_passes: (
            ($crabbox.applicable | not) or ($crabbox.exit == 0)
        ),
        I6_main_agent_fallbacks_empty: (
            ((.agents.defaults.model.fallbacks // ["nonempty"]) | length) == 0
        )
    },
    evidence: {
        defaults_embeddedHarness: .agents.defaults.embeddedHarness,
        defaults_agentRuntime: .agents.defaults.agentRuntime,
        defaults_subagents_model: .agents.defaults.subagents.model,
        defaults_main_model: .agents.defaults.model,
        codex_agents: [
            .agents.list[]?
            | select((.agentRuntime.id // "") == "codex" or (.embeddedHarness.runtime // "") == "codex")
            | {id, agentRuntime, embeddedHarness, model}
        ],
        telegram_threadBindings: .channels.telegram.threadBindings,
        crabbox: $crabbox
    }
}
') || {
    echo "FATAL: jq evaluation failed (config malformed?)" >&2
    exit 1
}

ALL_PASS=$(printf '%s' "$REPORT" | jq '[.invariants[]] | all')

if [[ "$OUTPUT" == "json" ]]; then
    printf '%s\n' "$REPORT" | jq --argjson pass "$ALL_PASS" '. + {ok: $pass}'
    [[ "$ALL_PASS" == "true" ]] && exit 0 || exit 1
fi

# Human-readable report.
echo "=== OpenClaw Config Invariants — ${SSH_HOST} ==="
echo
printf '%s' "$REPORT" | jq -r '
    .invariants
    | to_entries
    | map("  \(if .value then "PASS" else "FAIL" end)  \(.key)")
    | .[]
'
echo

if [[ "$ALL_PASS" == "true" ]]; then
    echo "All invariants hold. Subagent fail-closed routing intact, no legacy schema poison."
    exit 0
fi

echo "VIOLATIONS DETECTED. Evidence:"
printf '%s' "$REPORT" | jq '.evidence'
echo
echo "See Reference/KNOWN-BUGS.md #12, #13 for fix procedures (I1-I4)."
echo "See Reference/CRABBOX-HARDENING.md §10 rule #11 for I5 (Crabbox doctor gate)."
echo "See Reference/FAIL-CLOSED-DOCTRINE.md for I6 (main agent fail-closed)."
exit 1
