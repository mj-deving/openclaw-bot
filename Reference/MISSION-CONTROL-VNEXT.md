# Mission Control vNext

**Status:** Gregor cockpit design and reference implementation; fleet-ready abstractions still in progress.
**Date:** 2026-05-25.
**Primary reference:** `ValueCell-ai/ClawX`, as an architecture pattern only. Do not add an Electron dependency.

This doc defines the next OpenClaw control plane: a VPS/web cockpit that starts with one excellent Gregor-class gateway view, then grows into a private fleet registry and orchestration layer.

## Deployment Requirements

Tracked docs describe shape and checks only; concrete hostnames, internal ports, filesystem paths, token locations, rollout state, and rollback files belong in private operator notes.

- Runtime: small Bun web service managed by systemd.
- App path: local checkout path on the OpenClaw host.
- Listener: private host bridge, reverse-proxied by Caddy.
- Auth: operator token from a root/operator-managed env file.
- Existing operator-side routes stay preserved during cutover.
- Rollback material stays private on the host.

Minimum verification for any deployment:

- Operator route renders the vNext login page.
- Unauthenticated `/healthz` returns only `{ "ok": true }` or `{ "ok": false }`.
- Unauthenticated `/api/status` returns 401.
- Authenticated `/api/status` reports OpenClaw service active, config valid, Control UI HTTP 200, and cron inventory available.
- Authenticated `/api/capabilities` returns the gateway capability inventory.
- Gateway websocket route still returns `101 Switching Protocols` and `connect.challenge`.

## Why vNext

Current dashboard truth:

- The bundled OpenClaw Control UI remains the trusted single-gateway baseline and fallback. It is the closest thing to protocol-native truth because it ships with the gateway.
- The previous third-party abhi Mission Control stack is now a historical comparison surface. It was useful as a temporary surface, but it is strategically weak: its OpenClaw gateway assumptions have drifted from the live protocol and it stores or exposes some gateway material too broadly for a long-lived operator plane.
- The recent restart-policy fix improves gateway survivability, but it does not solve dashboard fit.
- ClawX is the better design template for the product shape: gateway lifecycle, host API boundary, chat/session model, local stores/routes, diagnostics, and operator-first cockpit ergonomics.

Near-term rule: freeze new investment in abhi-specific features. Keep any concrete rollback/decommission state in private operator notes.

## ClawX Reference Map

Use ClawX for architecture lessons, not as a direct dependency:

- Gateway lifecycle: explicit connect, reconnect, degraded, offline, and teardown states.
- Host API: one boundary that mediates filesystem, process, provider, and gateway actions.
- Chat/session model: sessions are first-class objects, not just transient message panes.
- Stores/routes: small domain stores for gateway, chat, sessions, diagnostics, and settings; routes mirror operator tasks.
- Diagnostics: surface health, logs, capability snapshots, and recent failures without requiring shell access.
- Desktop shell: reject this part for our target. vNext is web/VPS-first and must work through private access paths.

## Target Architecture

### Layer 1: Private gateways

Each OpenClaw gateway stays private. Acceptable access paths:

- loopback plus SSH tunnel
- Tailscale or equivalent private overlay
- controlled sidecar on the same host
- reverse proxy only when it preserves private access and does not expose the raw gateway port

Dashboard responses must never include raw gateway tokens, provider keys, or secret values. Return token references by configured name or path only.

### Layer 2: Gateway registry

The registry tracks gateway reachability and capability, not secrets:

- gateway id, display name, environment, owner label
- access path type and opaque token reference
- protocol version and observed capability snapshot
- status: online, degraded, offline, unknown
- last probe time, last error class, and reboot-survival status

The registry must handle at least one offline placeholder cleanly before it is considered fleet-ready.

### Layer 3: Gregor cockpit

First useful release is one polished Gregor cockpit:

- chat send/history
- session list/select
- gateway health and degraded/offline states
- logs and diagnostics
- cron list/run/toggle where supported
- agents and providers as read-only inventory
- token/provider views fully redacted

### Layer 4: Orchestration

Add after the cockpit is solid:

- tasks and runs
- approvals
- handoffs
- Beads bridge
- audit timeline

No public API promise in the first implementation. Internal shapes can change until the cockpit proves real operator value.

## Internal Entities

Initial internal model names:

- `GatewayRef`: private gateway entry, access method, status, token reference.
- `AgentRef`: agent name, role, gateway ownership, read-only capability summary.
- `SessionRef`: session id, agent, channel/source, recency, selected state.
- `TaskRef`: operator-requested work item, not necessarily a Bead.
- `RunRef`: execution attempt, status, timestamps, gateway/agent binding.
- `ApprovalRef`: privileged action awaiting operator decision.
- `CapabilitySnapshot`: observed gateway protocol features and support flags.
- `AuditEvent`: append-only operator and system event.

## Migration Path

1. Validate the bundled Control UI as the current Gregor baseline.
2. Build vNext registry and cockpit against one private Gregor gateway.
3. Record live protocol/capability probes and abhi MC health without exposing secrets.
4. Keep abhi MC read-only/frozen for comparison while vNext gains coverage.
5. Decide freeze versus decommission once vNext handles chat, sessions, health, logs, cron, and redacted provider inventory.
6. Add multi-gateway registry and offline placeholder proof.
7. Add orchestration primitives only after cockpit workflows are stable.

Abhi MC decommission criteria:

- vNext covers day-to-day Gregor operation.
- bundled Control UI remains available as fallback.
- control-plane containers survive reboot or have documented restart policy proof.
- stale abhi-specific beads are closed or explicitly retained as upstream-watch items.

## MVP Acceptance

Gregor cockpit:

- chat send/history works
- session list/select works
- gateway health renders online, degraded, and offline states
- diagnostics/log view has enough evidence for first-pass triage
- cron list/run/toggle works where the gateway supports it
- provider/token views redact secrets and show references only

Fleet-ready base:

- registry handles multiple gateway refs
- at least one offline placeholder renders cleanly
- protocol version and capability snapshot display per gateway
- private access model documented and enforced

Ops:

- no raw public gateway port
- no dashboard response with raw tokens or provider secrets
- reboot survival checked for all control-plane containers
- Beads reflects vNext epic, child tasks, and superseded stale dashboard beads

## Tracker

The vNext epic owns this work. Existing dashboard beads should be linked or superseded, not silently rewritten.

- `openclaw-bot-gd7`: superseded by the vNext epic.
- `openclaw-bot-8vw`: linked to the current-live-truth documentation child.
- `openclaw-bot-2qp`: keep open only if abhi MC remains active; otherwise close as decommissioned/superseded.
- `openclaw-bot-cwh`: keep as upstream-watch while abhi MC remains; close when abhi MC is retired.

## Sources

- Live operator inspection, 2026-05-25.
- `ValueCell-ai/ClawX`, used as architecture reference.
- `abhi1693/openclaw-mission-control`, current temporary surface.
- [DASHBOARD-LANDSCAPE.md](DASHBOARD-LANDSCAPE.md).
- [VERTICAL-AGENTS.md](VERTICAL-AGENTS.md).
