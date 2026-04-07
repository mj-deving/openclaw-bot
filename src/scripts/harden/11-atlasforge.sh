#!/usr/bin/env bash
# 11-atlasforge.sh — AtlasForge Meta-Learning Patterns
# Adopts 3 high-value patterns: Claw Score, Failure→Guardrail, Supersede Tracking.
# See Reference/ATLASFORGE-PATTERNS.md for full analysis.
#
# NOTE: These patterns become useful after 1-2 weeks of conversations.
# On a fresh bot with no history, they have nothing to operate on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

log_header "AF" "AtlasForge Meta-Learning Patterns"

applied=0
skipped=0

WORKSPACE="${OPENCLAW_DIR}/workspace"
AGENTS_FILE="${WORKSPACE}/AGENTS.md"
META_DIR="${OPENCLAW_DIR}/memory/meta"

log_warn "These patterns need conversation history to be useful."
log_info "Run this after the bot has been active for 1-2 weeks."
echo ""

# ── Meta directory ──────────────────────────────────────
STEP="atlasforge.meta_dir"
if is_step_done "$STEP"; then
    log_skip "meta directory exists"
    skipped=$((skipped + 1))
else
    mkdir -p "$META_DIR"
    mark_step_done "$STEP"
    log_done "Created memory/meta/ directory"
    applied=$((applied + 1))
fi

# ── Pattern 1: Claw Score (self-audit) ──────────────────
STEP="atlasforge.claw_score"
if is_step_done "$STEP"; then
    log_skip "Claw Score template deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy Claw Score self-audit template"
    log_info "6-dimension self-assessment: memory coherence, task completion,"
    log_info "context accuracy, communication quality, security posture, learning rate."
    log_info "Designed to run as a weekly cron job. Outputs to memory/meta/claw-score.json."
    echo ""
    log_warn "Self-evaluation has known limitations — LLMs tend to over-rate themselves."
    log_info "Treat scores as trend indicators, not absolute measures."

    if confirm; then
        # Deploy the claw score prompt template
        cat > "${META_DIR}/claw-score-prompt.md" << 'PROMPT'
# Claw Score Self-Audit

Evaluate your performance across 6 dimensions. Be honest — over-rating defeats the purpose.
Score each 1-10, then identify ONE specific improvement action per dimension.

## Dimensions

1. **Memory Coherence** — Are your memories consistent? Do any contradict each other?
   Look at: memory/daily/, memory/areas/, recent session recall accuracy.

2. **Task Completion** — Are you finishing what's asked? At what quality?
   Look at: recent conversations, incomplete follow-ups, user corrections.

3. **Context Accuracy** — Is your model of the user and their projects current?
   Look at: AGENTS.md, memory files, do they match what the user actually does?

4. **Communication Quality** — Are responses helpful, clear, appropriately concise?
   Look at: user reactions, corrections, "that's not what I asked" patterns.

5. **Security Posture** — Are guardrails being followed? Any concerning patterns?
   Look at: tool usage, information handling, instruction boundary compliance.

6. **Learning Rate** — Are you improving? Making fewer repeat mistakes?
   Look at: memory/meta/regressions.md, recurring correction patterns.

## Output Format

Write results to memory/meta/claw-score.json:

```json
{
  "date": "YYYY-MM-DD",
  "scores": {
    "memory_coherence": N,
    "task_completion": N,
    "context_accuracy": N,
    "communication_quality": N,
    "security_posture": N,
    "learning_rate": N
  },
  "total": N,
  "actions": [
    "dimension: specific improvement action"
  ],
  "trend": "improving|stable|degrading"
}
```

Compare against previous scores if they exist. Note the trend.
PROMPT
        mark_step_done "$STEP"
        log_done "Claw Score prompt deployed to memory/meta/claw-score-prompt.md"
        applied=$((applied + 1))
    fi
fi

# ── Pattern 2: Failure → Guardrail ──────────────────────
STEP="atlasforge.regressions"
if is_step_done "$STEP"; then
    log_skip "Regressions file deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy failure-to-guardrail regression tracking"
    log_info "Every significant failure becomes a named regression loaded at boot."
    log_info "The bot starts each session knowing its past mistakes."

    if confirm; then
        if [[ ! -f "${META_DIR}/regressions.md" ]]; then
            cat > "${META_DIR}/regressions.md" << 'REGRESSIONS'
# Known Regressions

> Every significant failure gets a named entry here. The bot loads this at session start
> to avoid repeating past mistakes. Format: name, date, what happened, guardrail rule.

<!-- Add regressions as they occur. Example:

## REG-001: Leaked API key in response (2026-03-15)
**What happened:** Bot included an API key from memory in a Telegram response.
**Guardrail:** Never include strings matching `sk-`, `key-`, or `token-` patterns in responses.
**Status:** Active — enforced by L4 redaction layer.

-->

No regressions recorded yet. This file will populate as the bot operates.
REGRESSIONS
        fi

        # Add regression reference to AGENTS.md if it exists
        if [[ -f "$AGENTS_FILE" ]]; then
            if ! grep -q "regressions" "$AGENTS_FILE" 2>/dev/null; then
                cat >> "$AGENTS_FILE" << 'AGENTS_APPEND'

## Known Regressions

Load `memory/meta/regressions.md` at session start. These are past mistakes that must not repeat.
Each regression has a guardrail rule — follow it without exception.
AGENTS_APPEND
                log_done "Added regressions section to AGENTS.md"
            fi
        fi

        mark_step_done "$STEP"
        log_done "Regressions file deployed to memory/meta/regressions.md"
        applied=$((applied + 1))
    fi
fi

# ── Pattern 3: Supersede Tracking ───────────────────────
STEP="atlasforge.supersede"
if is_step_done "$STEP"; then
    log_skip "Supersede tracking prompt deployed"
    skipped=$((skipped + 1))
else
    log_todo "Deploy supersede tracking for memory hygiene"
    log_info "Prevents 'ghost facts' — stale information that was never explicitly removed."
    log_info "Adds to PARA Weekly Synthesis to flag entries superseded by newer information."

    if confirm; then
        cat > "${META_DIR}/supersede-tracking-prompt.md" << 'SUPERSEDE'
# Supersede Tracking — Weekly Hygiene

During weekly memory review, check for superseded facts:

1. **Scan memory/daily/ from the past week** for any facts that UPDATE previous entries.
2. **For each update**, find the original entry and mark it:
   - Add `[SUPERSEDED by YYYY-MM-DD entry]` prefix to the old fact
   - Ensure the new fact has `[SUPERSEDES: brief description of old fact]` tag
3. **Check memory/areas/ and memory/resources/** for stale information:
   - Dates that have passed
   - Versions that have been upgraded
   - Decisions that were reversed
4. **Archive genuinely stale entries** to memory/archive/ with a note on why.

## Output

Append findings to memory/meta/supersede-log.json:

```json
{
  "date": "YYYY-MM-DD",
  "superseded": [
    {"old": "path/to/old", "new": "path/to/new", "reason": "brief"}
  ],
  "archived": [
    {"path": "path/to/stale", "reason": "brief"}
  ],
  "clean": true/false
}
```
SUPERSEDE
        mark_step_done "$STEP"
        log_done "Supersede tracking prompt deployed to memory/meta/"
        applied=$((applied + 1))
    fi
fi

# ── Claw Score cron setup hint ──────────────────────────
echo ""
log_info "To activate Claw Score as a weekly cron, run in chat:"
echo -e "    ${DIM}/cron add \"Claw Score\" weekly Sunday 04:00 \"Run the self-audit in memory/meta/claw-score-prompt.md\"${NC}"
echo ""
log_info "To add supersede tracking to PARA Weekly, update the Weekly Synthesis cron prompt"
log_info "to include: \"Also run memory/meta/supersede-tracking-prompt.md\""

log_summary "$applied" "$skipped"
