#!/usr/bin/env python3
"""
cache-stats.py — Parse OpenClaw session transcripts for prompt cache metrics.

Usage:
    # Single session
    python3 cache-stats.py ~/.openclaw/agents/main/sessions/SESSION_ID.jsonl

    # All sessions
    cat ~/.openclaw/agents/main/sessions/*.jsonl | python3 cache-stats.py

    # Via SSH from local machine
    ssh vps 'cat ~/.openclaw/agents/main/sessions/*.jsonl' | python3 cache-stats.py

Each API call in a session transcript stores a usage block at message.usage
with cacheRead and cacheWrite token counts. This script aggregates those
per model and reports cache hit ratios.

What the numbers mean:
    80-95% hit ratio = caching working well (workspace/system prompt reused)
    < 50% hit ratio  = cache prefix breaking (dynamic content in workspace?)
    0% hit ratio     = caching not enabled, or isolated single-turn sessions

See: GUIDE.md Phase 14.6 (Cache-Friendly Architecture)
"""

import sys
import json


def main():
    models = {}
    current_model = "unknown"

    source = open(sys.argv[1]) if len(sys.argv) > 1 else sys.stdin

    for line in source:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)

            if d.get("type") == "model_change":
                current_model = d.get("modelId", "unknown")
                continue

            msg = d.get("message", {})
            usage = msg.get("usage")
            if not usage:
                continue

            model = msg.get("model", current_model)
            if model not in models:
                models[model] = {
                    "input": 0,
                    "output": 0,
                    "cacheRead": 0,
                    "cacheWrite": 0,
                    "cost": 0.0,
                    "calls": 0,
                }

            s = models[model]
            s["input"] += usage.get("input", 0)
            s["output"] += usage.get("output", 0)
            s["cacheRead"] += usage.get("cacheRead", 0)
            s["cacheWrite"] += usage.get("cacheWrite", 0)
            cost = usage.get("cost", {})
            if isinstance(cost, dict):
                s["cost"] += cost.get("total", 0)
            s["calls"] += 1

        except (json.JSONDecodeError, KeyError):
            continue

    if source is not sys.stdin:
        source.close()

    if not models:
        print("No usage data found in input.")
        sys.exit(1)

    # Per-model output
    grand = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "cost": 0.0, "calls": 0}

    for model in sorted(models):
        s = models[model]
        total_in = s["input"] + s["cacheRead"] + s["cacheWrite"]
        ratio = s["cacheRead"] / total_in * 100 if total_in > 0 else 0
        print(
            f"{model:25s}  calls={s['calls']:>4}  "
            f"cache_read={s['cacheRead']:>12,}  "
            f"cache_write={s['cacheWrite']:>10,}  "
            f"hit_ratio={ratio:>5.1f}%  "
            f"cost=${s['cost']:.4f}"
        )
        for k in grand:
            grand[k] += s[k]

    # Totals
    total_in = grand["input"] + grand["cacheRead"] + grand["cacheWrite"]
    ratio = grand["cacheRead"] / total_in * 100 if total_in > 0 else 0

    print(f"\n{'TOTAL':25s}  calls={grand['calls']:>4}  "
          f"cache_read={grand['cacheRead']:>12,}  "
          f"cache_write={grand['cacheWrite']:>10,}  "
          f"hit_ratio={ratio:>5.1f}%  "
          f"cost=${grand['cost']:.4f}")


if __name__ == "__main__":
    main()
