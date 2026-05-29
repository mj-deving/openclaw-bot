# VPS Gotchas

Operational footguns observed on Gregor's VPS. Promoted out of `CLAUDE.md` on 2026-05-08 to keep that file lean.

- Gateway service name is `openclaw` (not `openclaw-gateway`).
- If the gateway is listening but `systemctl restart openclaw` reports the unit disabled/inactive, Gregor is running from a stale/manual process. Adopt it back into systemd with `sudo openclaw-gateway-adopt-systemd`, then `systemctl restart openclaw` works via the scoped Polkit rule.
- `openclaw config dump` is NOT JSON — read `~/.openclaw/openclaw.json` directly; use `openclaw config validate` to confirm syntax.
- `openclaw config set` can introduce malformed keys — verify with `openclaw models list` after.
- OpenAI Codex OAuth must be done locally then SCP'd — headless VPS callback fails.
- `ReadOnlyPaths` for `openclaw.json` causes EBUSY restart loops — keep out of hardening drop-ins.
- Fresh installs need `mkdir -p ~/.openclaw/credentials` before gateway start.
- PEP 668 on Ubuntu 24.04: use `pipx` for Python CLI tools, not `pip --user`.
- **Compaction config canonical form** (per [docs.openclaw.ai/concepts/compaction](https://docs.openclaw.ai/concepts/compaction)): use ONLY `agents.defaults.compaction.model` with a triple-prefixed string (`openrouter/openai/gpt-4.1-mini`, `openrouter/anthropic/claude-haiku-4-5`, `ollama/llama3.1:8b`). **Do NOT also set `compaction.provider`** — that key is for *custom compaction-provider plugin IDs* and forces `mode: safeguard` automatically. Pairing `provider: openrouter` with a slash-prefixed `model` makes OpenClaw resolve provider from the model string's first segment, ignoring the explicit `provider` → "No API key found for provider X" failures.
- **OAuth providers cannot do compaction** — Codex OAuth (`openai-codex/...`) is unreliable across separate process invocations (per OpenAI's own Codex CLI docs). Compaction must use API-key-based auth (OpenRouter is the easy default). Chat can use OAuth; compaction cannot.
- **`agents.defaults.workspace` must be a stable path** — never `/tmp/...`. /tmp is wiped on reboot AND toolkit test runners (e.g., omniweb-toolkit) recreate scaffolded workspaces under `/tmp/<toolkit>-test/...` with FRESH default `BOOTSTRAP.md` + bare `IDENTITY.md`. On gateway restart the bot reloads from the templates and runs the bootstrap dialogue ("Hey. I just came online. Who am I?"). Memory writes silently fall back to default — the canary is `openclaw memory status` showing `Issues: memory directory missing (...)`. Treat as RED.
