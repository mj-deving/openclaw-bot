# Mission Control — Deployment, Auth, and Operations

_Last verified live: 2026-05-05 during Gregor gateway registration._

Authoritative reference for Mission Control (MC) — the web dashboard at `https://missioncontrol.mjdeving.com` that drives boards, agents, and gateways. Cross-references inbox briefings (operational handoffs to live bots) and project memory (`reference_mission-control-deployment.md`).

## What it is

Mission Control is a self-hosted multi-container web app that registers and operates OpenClaw gateways. Front-end is Next.js, backend is FastAPI, async work runs on RQ (Redis Queue), Postgres for state, Caddy for TLS termination and routing.

- **Upstream repo:** `github.com/abhi1693/openclaw-mission-control` (third-party maintainer; not officially OpenClaw — vet PRs and pin versions deliberately).
- **Local checkout (VPS):** `/home/openclaw/.openclaw/workspace/local/openclaw-mission-control/`.
- **Public URL:** `https://missioncontrol.mjdeving.com`.
- **Status today:** registered to Gregor as of 2026-05-05 17:08; gateway record `f576d91e-9ade-4aaf-949c-6f6bc4272aba`; backend device `86ebcd…1ac231` paired; webhook-worker pairing pending-on-demand (see §Device Pairing).

## Architecture

### Container topology (`compose.yml`)

| Service | Image source | Network | Role |
|---|---|---|---|
| `db` | postgres | bridge | persistent state (boards, gateways, agents, sessions, approvals) |
| `redis` | redis | bridge | RQ queue + ephemeral state |
| `backend` | built from repo | bridge | FastAPI app — REST API at `/api/*`, opens WS to gateways for synchronous RPC |
| `frontend` | built from repo | bridge | Next.js — dashboard SPA |
| `webhook-worker` | built from repo | bridge | RQ worker — processes `WEBHOOK_TASK_TYPE` (HTTP webhooks) and `LIFECYCLE_RECONCILE_TASK_TYPE` (opens its own WS to gateway) |
| `gateway-proxy` (compose.caddy.yml) | alpine/socat | host | shims `172.21.0.1:18790` → `127.0.0.1:18789` so Caddy can reach Gregor's gateway |
| `caddy` (compose.caddy.yml) | caddy | bridge | TLS, reverse proxy, websocket pass-through |

### Network chain (verified)

```
client → wss://missioncontrol.mjdeving.com:443/openclaw-gateway
       → Caddy container (handle_path /openclaw-gateway* — strips prefix)
       → 172.21.0.1:18790  (alpine/socat sidecar from compose.caddy.yml, network_mode: host)
       → 127.0.0.1:18789   (Gregor's openclaw native gateway)
```

The `:18790` indirection exists because the Caddy container can't reach the host's `127.0.0.1` — but it CAN reach `172.21.0.1` (the Tailscale-routable host IP). socat bridges the two on the host network namespace.

> **Doctrine clarification (supersedes earlier CLAUDE.md line):** port `18790` is **NOT** "Mission Control's own port" — it is the socat shim that fronts Gregor's `:18789` for Mission Control's reverse-proxied path. The earlier doctrine line was incomplete. The future Dismas bot allocation at `:18790` (Reference/VERTICAL-AGENTS.md) WILL collide with this socat sidecar on bootstrap day; renumber Dismas (e.g., `18791`) before bootstrapping.

### Live Caddyfile (verified correct as-is)

```caddy
missioncontrol.mjdeving.com {
  encode gzip zstd

  handle_path /openclaw-gateway* {
    reverse_proxy 172.21.0.1:18790 {
      header_up -Origin
    }
  }

  @backend path /api/* /health /healthz /openapi.json /docs* /redoc* /metrics*
  reverse_proxy @backend backend:8000

  reverse_proxy frontend:3000
}
```

`header_up -Origin` is defensive — OpenClaw's token-auth (`auth.mode=token`) doesn't validate Origin (the `controlUi.allowedOrigins` allowlist only fires when `dangerouslyDisableDeviceAuth: true`). Caddy v2 `reverse_proxy` handles WebSocket upgrades natively; no extra directives needed unless WS drops are observed (then add `transport http { read_timeout 0; write_timeout 0 }`).

## Authentication

### MC dashboard auth — `AUTH_MODE=local` (current deployment)

The deployment uses local-mode authentication (`backend/app/.env` → `AUTH_MODE=local`). The login screen is literally captioned **"SELF-HOST MODE — Local Authentication — Enter your access token to unlock Mission Control. Token must be at least 50 characters."**

- **Bearer = `LOCAL_AUTH_TOKEN`** env value verbatim. Stored in MC's `.env` only; not derivable from the browser.
- **No JWT, no OAuth, no Clerk** in self-host mode (Clerk is supported as an alternative `AUTH_MODE=clerk` per the codebase, but not in our deployment).
- The browser stores the token after login (likely localStorage) and sends it as `Authorization: Bearer <LOCAL_AUTH_TOKEN>` on every `/api/*` call.
- Server-side validation: `backend/app/core/auth.py:436-447` (`compare_digest` against env, length ≥ 50).
- Endpoint authorization: most write endpoints require `Depends(require_org_admin)` (`backend/app/api/deps.py:121-127`).

### Gateway-connect auth (MC backend → OpenClaw gateway)

Separate from MC dashboard auth. When MC opens a WebSocket to a registered gateway, it authenticates **in-protocol**, NOT at the HTTP upgrade layer. So:

- Anonymous WS upgrade to `wss://missioncontrol.mjdeving.com/openclaw-gateway` returns **HTTP 101 Switching Protocols** — confirms route + listener; auth is NOT yet validated.
- 401/403/426 would indicate HTTP-layer auth (which OpenClaw native gateway does not implement).
- 502/504 = socat or gateway down. 404 = path-strip mis-fired.

**Token wire format — MC sends the gateway token THREE ways simultaneously** (`backend/app/services/openclaw/gateway_rpc.py`):
1. URL query param `?token=…` (`:188-193`)
2. JSON-RPC `connect` frame, `params.auth.token` (`:354-355`)
3. Embedded inside the Ed25519-signed device-pair payload (`device_identity.py:142-167`)

**It is NOT an `Authorization: Bearer` header on the WS upgrade.**

**Required scopes — hardcoded in MC** (`gateway_rpc.py:36-41`):

```
operator.read
operator.admin
operator.approvals
operator.pairing
```

The gateway token used in the gateway record MUST carry all four. MC has no UI to narrow scopes per-user.

**Token storage in MC DB** — plaintext, `models/gateways.py:25` (`AutoString`, no hash). Currently echoed in API responses (`docs/openclaw_gateway_ws.md`: "a future release will redact"). Treat MC's gateways table and API responses as secret material.

## Device Pairing

MC uses Ed25519 device-pairing on top of the gateway token — defense-in-depth so a leaked gateway token alone can't authenticate. Each MC process loads a persistent device key from `~/.openclaw/identity/device.json` (`backend/app/services/openclaw/device_identity.py:99` `load_or_create_device_identity()`). On first connection, the gateway sees an unknown fingerprint and queues a pending pairing request that the gateway operator must approve.

### Critical: MC has TWO independent device identities

The `backend` and `webhook-worker` containers each call `load_or_create_device_identity()` against `Path.home()` resolved INSIDE the container. **`compose.yml` declares only `postgres_data` as a persistent volume — there is NO shared volume mounted at the identity path on either container.** Result:

- Each container generates its own Ed25519 keypair on every fresh start.
- TWO device-pair approvals are required on the OpenClaw gateway side, not one.
- Every `docker compose down && up` regenerates both keypairs and produces 2 fresh pending pairings.

This is **upstream bug `openclaw-bot-2qp`** — fix is to add a shared volume mount at `~/.openclaw/identity/` on both containers in `compose.yml`. Until upstream takes the PR, the on-our-side discipline is **pair-on-demand**.

### Which pair appears when

- **Backend pair** — appears immediately on first gateway-create attempt (the create-record API path triggers a synchronous WS pre-flight).
- **Webhook-worker pair** — appears only when the worker fires a `LIFECYCLE_RECONCILE_TASK_TYPE` job (`backend/app/services/queue_worker.py`). Triggers: any board/agent action in MC enqueues a lifecycle reconcile. The first pending request from the worker may TTL out before manual approve if not caught quickly — the gateway expires unapproved requests after a short window.

### Operator commands (on the gateway side)

```bash
openclaw devices list              # show paired + pending
openclaw devices approve <reqId>   # approve a pending request
openclaw devices reject <reqId>    # reject pending
openclaw devices remove <devId>    # remove a paired entry
openclaw devices revoke <devId>    # revoke a token for a role
openclaw devices clear             # wipe paired devices
openclaw devices rotate            # rotate a device token
```

## Gateway Registration Flow

### API endpoint

`POST /api/v1/gateways` — `backend/app/api/gateways.py:90` (handler `create_gateway`); router prefix at `gateways.py:37` mounted at `backend/app/main.py:539,545`.

- **Auth:** `Authorization: Bearer <LOCAL_AUTH_TOKEN>` + organization-admin (`require_org_admin` at `gateways.py:95`).
- **Pre-flight:** the handler opens a real WebSocket to the gateway URL via `assert_gateway_runtime_compatible` (`backend/app/services/openclaw/admin_service.py:181-208`) BEFORE inserting the DB row. On WS-connect failure → **502** with `"Gateway compatibility check failed: …"` and no record. On version mismatch → **422**. On success → row is committed and `service.ensure_main_agent()` provisions the main agent.
- **Side effect:** auto-creates an MC-provisioned agent (e.g., `mc-gateway-<record-uuid>`) on the gateway side.

### Body schema (`backend/app/schemas/gateways.py:24-38` `GatewayCreate`)

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` | str | ✓ | — | free text |
| `url` | str | ✓ | — | see §URL Shape |
| `workspace_root` | str | ✓ | — | e.g. `/home/openclaw/.openclaw` |
| `allow_insecure_tls` | bool | — | false | leave false (Caddy serves a CA cert) |
| `disable_device_pairing` | bool | — | false | leave false (default device-pair flow) |
| `token` | str \| null | — | null | OpenClaw native gateway token, all 4 operator scopes |

### URL shape — explicit `:443` is mandatory

For path-mode reverse-proxied deployments through Caddy:

```
wss://missioncontrol.mjdeving.com:443/openclaw-gateway
```

The `:443` is **mandatory** even though it's the WSS default. The frontend validator at `frontend/src/lib/gateway-form.ts:14-72` (`validateGatewayUrl` → `hasExplicitPort`) rejects URLs whose `URL.port` is empty — error: `"Gateway URL must include an explicit port."` This applies to scripted POSTs too (the validator is mirrored frontend-only, but staying consistent prevents UI regressions later).

- URL is used **verbatim** by MC's backend WS client (`gateway_rpc.py:183-193,415`) — no `/ws` suffix injected.
- No trailing slash. Trailing-slash semantics differ through Caddy's `handle_path /openclaw-gateway*` matcher.
- OpenClaw native gateway listens at `/` (root) per `docs/openclaw_baseline_config.md:480`.

### Working curl example

```bash
curl -i -X POST 'https://missioncontrol.mjdeving.com/api/v1/gateways' \
  -H 'Authorization: Bearer <LOCAL_AUTH_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Gregor",
    "url": "wss://missioncontrol.mjdeving.com:443/openclaw-gateway",
    "token": "<OPENCLAW_GATEWAY_TOKEN>",
    "workspace_root": "/home/openclaw/.openclaw",
    "allow_insecure_tls": false,
    "disable_device_pairing": false
  }'
```

`<LOCAL_AUTH_TOKEN>` is in MC's `.env`. `<OPENCLAW_GATEWAY_TOKEN>` is the gateway's native operator token (4 scopes minimum).

### Expected outcomes

| HTTP | Meaning | Action |
|---|---|---|
| 200 + `GatewayRead` JSON | record committed AND pre-flight succeeded | done |
| 502 with `"pairing required: device is not approved yet"` | first attempt — device-pair handshake needs approval | run `openclaw devices approve <reqId>` on gateway side, retry |
| 502 with `"missing scope: operator.<X>"` | gateway token doesn't carry that scope | mint new token with all 4 scopes |
| 502 with `"Gateway compatibility check failed: <other>"` | TLS/network/transport issue | check socat + gateway service, smoke-test the route |
| 422 | OpenClaw version mismatch with what MC expects | upgrade gateway or downgrade MC |
| 401 | bad MC bearer | re-read `LOCAL_AUTH_TOKEN` |
| 403 | MC user is not org-admin | grant org-admin |

### Browser-driven alternative

Instead of curl, navigate to `https://missioncontrol.mjdeving.com/gateways/new` and fill the form (keeps `LOCAL_AUTH_TOKEN` in the browser session). Same body, same pre-flight, same outcomes.

## Pre-flight Smoke Tests

```bash
# Confirm both ports are listening
ssh vps 'ss -tnlp | grep 18789; ss -tnlp | grep 18790'

# Confirm Caddy + socat route to the gateway (anonymous handshake)
curl --include --no-buffer \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  -H "Sec-WebSocket-Version: 13" \
  https://missioncontrol.mjdeving.com/openclaw-gateway/
# Expected: HTTP 101 Switching Protocols (route + listener confirmed; auth is in-protocol).
# 502/504 = socat or gateway down. 404 = path-strip mis-fired.
```

## Gateway-side Doctor Findings to Track

After successful registration, `openclaw doctor --non-interactive` typically surfaces:

1. **`heartbeat.directPolicy unset`** on the MC-provisioned agent — explicit value required since MC drives heartbeats over WS, not direct channels. Tracked: `openclaw-bot-7yn`.
2. **Gateway bound to lan** — known and accepted per CLAUDE.md doctrine (MC requires LAN reachability; defense rests on `auth.mode=token` + `controlUi.allowedOrigins` + `trustedProxies`).
3. **Orphan transcript files** under `~/.openclaw/agents/main/sessions` — non-blocking hygiene. Tracked: `openclaw-bot-ab6`.

Discipline before any config edit (per `Reference/KNOWN-BUGS.md` #8): edit → `openclaw config validate` → restart → **read-back** from live `~/.openclaw/openclaw.json` POST-RESTART. Strict-schema auto-restore silently reverts wrong keys.

## Live Operations

### Synchronous probe (audit / debug)

```bash
ssh vps 'openclaw agent --agent main --json --timeout 90 --message "<question>"'
```

Returns reply + `executionTrace` (`winnerProvider`, `winnerModel`, `fallbackUsed`) + `toolSummary.calls/failures`. Use `--agent main` (not `--to <E.164>`) for headless audit. This is the canonical replacement for the retired internal pipeline (`~/.openclaw/pipeline/`, retired 2026-04-28, bead `wi8`).

### Inbox file-drop (durable hand-off)

```bash
scp <briefing>.md vps:/home/openclaw/.openclaw/workspace/inbox/$(date -u +%Y-%m-%d)-<slug>.md

# Reindex Gregor's main agent only (~2 min; full unscoped reindex is ~10 min for 6 agents)
ssh vps 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"; openclaw memory index --agent main'
```

Full convention: `~/.claude/projects/-home-mj-projects-openclaw-bot/memory/reference_gregor-inbox-pipeline.md`.

### Live RPC sequence on a healthy MC↔Gregor pair (verified 2026-05-05)

```
17:07:53  [gateway] device pairing approved device=<fingerprint> role=operator
17:07:53  [ws] ⇄ res ✓ device.pair.approve   83ms
17:08:16  [ws] ⇄ res ✓ sessions.list         50ms
17:08:19  [ws] ⇄ res ✓ agents.create       1217ms
17:08:22  [ws] ⇄ res ✓ agents.update        822ms
17:08:23  [ws] ⇄ res ✓ config.get           689ms
17:08:26  [ws] ⇄ res ✓ config.patch        2690ms
17:08:27  [ws] ⇄ res ✓ agents.files.set       …
17:08:29  [ws] ⇄ res ✓ sessions.patch        61ms
17:08:44  [agents/auth-profiles] inherited auth-profiles from main agent
```

`config.patch` writes to `/home/openclaw/.openclaw/openclaw.json` and may queue a deferred restart (e.g., `channels.defaults` touched → restart deferred until idle). This is normal first-pair bootstrap.

## Known Bugs / Open Items

| Bead | Title | Priority | Notes |
|---|---|---|---|
| `openclaw-bot-7yn` | Set `heartbeat.directPolicy` explicit on `mc-gateway-f576d91e` agent | P2 | Live doctor warning |
| `openclaw-bot-bpt` | Patch `inbox/2026-05-05-mc-gateway-registration.md` with three field corrections | P2 | Briefing accuracy |
| `openclaw-bot-2qp` | MC compose missing shared device-identity volume → re-pair churn | P2 | Upstream bug; PR target |
| `openclaw-bot-ab6` | Clean up 126 orphan transcript files | P3 | Hygiene |

## Cross-references

- **Operator's guide — how to USE Mission Control day-to-day:** [MISSION-CONTROL-OPERATIONS.md](MISSION-CONTROL-OPERATIONS.md) (procedural companion to this architecture-focused doc — dashboard surfaces, common workflows, API quick reference, ops commands, troubleshooting)
- **Inbox briefing (operational handoff to Gregor):** `~/.openclaw/workspace/inbox/2026-05-05-mc-gateway-registration.md` (also at `~/.claude/PAI/MEMORY/WORK/mc-gateway-registration/BRIEFING-FOR-GREGOR.md`).
- **Project memory (operational learnings):** `~/.claude/projects/-home-mj-projects-openclaw-bot/memory/reference_mission-control-deployment.md`, `reference_gregor-inbox-pipeline.md`.
- **CLAUDE.md `Gateway exposure (Mission Control)` line:** see CLAUDE.md "Key Architecture Decisions"; the `port 18790` claim is corrected here (it's the socat shim, not "MC's own port").
- **Vertical agents and port allocation:** `Reference/VERTICAL-AGENTS.md`. **Watch:** Dismas allocated `:18790` will collide with the socat sidecar on bootstrap day; renumber Dismas first.
- **Strict-schema auto-restore discipline:** `Reference/KNOWN-BUGS.md` #8.
- **Threat model crossref:** `Reference/THREAT-MODEL-CROSSREF.md` (Berman ↔ ATLAS).
