# Threat Model Cross-Reference: Berman 6-Layer ↔ MITRE ATLAS

> Cross-reference between our 6-layer prompt-injection defense (Berman model, implemented at `src/defense/`) and OpenClaw's official MITRE ATLAS threat model (v1.0-draft, 2026-02-04).
>
> Authoritative defense source: [DEFENSE-SYSTEM.md](DEFENSE-SYSTEM.md). Authoritative threat-model source: [docs.openclaw.ai/security/THREAT-MODEL-ATLAS.md](https://docs.openclaw.ai/security/THREAT-MODEL-ATLAS.md).
>
> Created: 2026-04-27. Owner: this repo. Tracks beads `openclaw-bot-vek` (this doc), `openclaw-bot-lw4` / `openclaw-bot-7gg` / `openclaw-bot-kou` (gap probes).

## Why this document exists

The OpenClaw maintainer's official threat model maps 16 named threats to 8 MITRE ATLAS tactics. Three of those threats have **"None specific"** or **"None"** as their documented mitigation. Our Berman 6-layer defense — built independently — covers most of the rest. This document makes the alignment explicit so:

1. Our defense is **defensible** as complementary to OpenClaw's model rather than a parallel reinvention
2. The three uncovered ATLAS threats become **probe candidates** with concrete acceptance criteria
3. Future audits can cite a single map rather than reasoning about defense coverage from scratch

The single most important quote from the maintainer's doc: T-EXEC-001 (Direct Prompt Injection) is rated **CRITICAL** with mitigation labeled *"Detection only, no blocking; sophisticated attacks bypass."* This is exactly the gap Berman L1+L2 was built to fill.

## Layer recap

### Berman 6-layer (this repo)

| Layer | Hook event | What it does | Source file |
|-------|-----------|--------------|-------------|
| L1 | `message_received` | Deterministic sanitizer: Unicode, base64/hex/ROT13 decode, role injection, zero-width, wallet flagging | `src/defense/layer1-sanitizer.ts` |
| L2 | `message_received` | LLM frontier scanner (high-risk channels only); nonce-delimited classification | `src/defense/layer2-scanner.ts` |
| L3 | `message_sending` + `llm_output` | Outbound content gate: secrets, internal paths, exfil URLs, financial data | `src/defense/layer3-outbound.ts` |
| L4 | `message_sending` + `llm_output` | Redaction pipeline: API keys, personal email, phone, dollar amounts | `src/defense/layer4-redaction.ts` |
| L5 | `llm_input` | Call governor: spend limit, volume limit, lifetime cap, dedup, circuit breaker | `src/defense/layer5-governor.ts` |
| L6 | `before_tool_call` | Access control: path guards, URL safety, DNS pinning | `src/defense/layer6-access.ts` |

### MITRE ATLAS 8 tactics, 16 threats (OpenClaw model)

| Tactic | ATLAS ID | Threats |
|--------|----------|---------|
| Reconnaissance | AML.TA0002 | T-RECON-001 Agent Endpoint Discovery, T-RECON-002 Channel Integration Probing |
| Initial Access | AML.TA0004 | T-ACCESS-001 Pairing Code Interception, T-ACCESS-002 AllowFrom Spoofing, T-ACCESS-003 Token Theft |
| Execution | AML.TA0005 | T-EXEC-001 Direct Prompt Injection, T-EXEC-002 Indirect, T-EXEC-003 Tool Argument Injection, T-EXEC-004 Exec Approval Bypass |
| Persistence | AML.TA0006 | T-PERSIST-001 Malicious Skill Installation, T-PERSIST-002 Skill Update Poisoning, T-PERSIST-003 Agent Configuration Tampering |
| Defense Evasion | AML.TA0007 | T-EVADE-001 Moderation Pattern Bypass, T-EVADE-002 Content Wrapper Escape |
| Discovery | AML.TA0008 | T-DISC-001 Tool Enumeration, T-DISC-002 Session Data Extraction |
| Collection / Exfiltration | AML.TA0009/10 | T-EXFIL-001 Data Theft via web_fetch, T-EXFIL-002 Unauthorized Message Sending, T-EXFIL-003 Credential Harvesting |
| Impact | AML.TA0011 | T-IMPACT-001 Unauthorized Command Execution, T-IMPACT-002 Resource Exhaustion, T-IMPACT-003 Reputation Damage |

## The mapping

Layers in **bold** are the primary mitigation; non-bold layers contribute partial coverage. **GAP** means no Berman layer addresses this threat — these are probe candidates.

| ATLAS Threat | OpenClaw Mitigation (per maintainer) | Berman Coverage | Notes |
|--------------|--------------------------------------|-----------------|-------|
| T-RECON-001 Agent Endpoint Discovery | Tailscale auth, loopback binding | (Infrastructure) | Loopback-only gateway (127.0.0.1:18789) covers this at the network layer; not a Berman concern |
| T-RECON-002 Channel Integration Probing | None specific | (Infrastructure) | Telegram allowFrom + loopback gateway are the de-facto controls; not a Berman concern |
| T-ACCESS-001 Pairing Code Interception | 1h DM expiry, 5m node expiry, channel delivery | (Infrastructure) | Out of Berman scope — handled at gateway-pairing layer |
| T-ACCESS-002 AllowFrom Spoofing | Channel-specific identity verification | (Infrastructure) | Telegram allowlist enforcement is gateway-level, not Berman |
| T-ACCESS-003 Token Theft | File permissions | **L6** + safety hook | L6 path guards on auth-profiles.json; safety hook gates credential transfers |
| **T-EXEC-001 Direct Prompt Injection** | *"Detection only, no blocking; sophisticated attacks bypass"* (CRITICAL) | **L1, L2** | This is the headline gap Berman fills. L1 deterministic patterns (16 system-override + 8 role-injection) + L2 LLM classifier with nonce-delimited prompt = blocking, not just detection. |
| **T-EXEC-002 Indirect Prompt Injection** | XML tags + security notice wrapping | **L1, L2** | L1 strips zero-width / Unicode obfuscation, decodes base64/hex/ROT13 before pattern match; L2 reclassifies with semantic understanding |
| T-EXEC-003 Tool Argument Injection | Exec approvals for dangerous commands | **L6** | L6 enforces path/URL guards before tool execution regardless of approval state |
| T-EXEC-004 Exec Approval Bypass | Allowlist + ask mode | (Infrastructure) | Out of Berman scope — `tools.profile` + `exec.security` enforce this |
| T-PERSIST-001 Malicious Skill Installation | GitHub account age check, pattern moderation | **(ClawKeeper)** + bundled-only skills policy | Our policy is zero ClawHub installs; ClawKeeper's `scan-skill` is the runtime check |
| T-PERSIST-002 Skill Update Poisoning | Version fingerprinting | **(ClawKeeper)** | Same as above; complemented by ClawKeeper drift detection |
| T-PERSIST-003 Agent Configuration Tampering | File permissions | **(ClawKeeper)** + L6 | ClawKeeper watches openclaw.json + AGENTS.md for boundary changes; L6 path guard on config writes |
| T-EVADE-001 Moderation Pattern Bypass | Pattern-based FLAG_RULES | **L1, L2** | L1 normalizes input before matching; L2 classifies semantically (verdicts overridden by symmetric score logic) |
| T-EVADE-002 Content Wrapper Escape | XML tags + security notice | **L1, L3** | L1 detects fake assistant/system/user role markers; L3 audits LLM output for injection artifacts |
| **T-DISC-001 Tool Enumeration** | **None specific** | **GAP** ← probe `openclaw-bot-lw4` | No deliberate Berman coverage. May be incidentally caught by L5 dedup if attacker repeats probes, but not by design. |
| T-DISC-002 Session Data Extraction | Session isolation per sender | **L3, L4** + (Infrastructure) | L3 redacts internal paths and injection artifacts in outbound; L4 redacts secrets and personal data; gateway session keying provides isolation. |
| T-EXFIL-001 Data Theft via web_fetch | SSRF blocking for internal networks | **L6** | L6 IPv4/IPv6 private range blocking + DNS pinning (3s timeout) covers SSRF at tool-call boundary |
| T-EXFIL-002 Unauthorized Message Sending | Outbound messaging gating | **L3, L4** | L3 cancels/modifies outbound at message_sending hook; L4 redacts before delivery |
| **T-EXFIL-003 Credential Harvesting** | **None specific** | **GAP** ← probe `openclaw-bot-7gg` | L6 path guards block reads of auth-profiles.json; safety hook blocks credential message sends; but no deliberate test coverage for ATLAS T0009 sub-techniques. Real coverage status: unverified. |
| T-IMPACT-001 Unauthorized Command Execution | Exec approvals, Docker sandbox option | **L6** + (Infrastructure) | L6 path guards + `exec.security: full` + ask mode |
| **T-IMPACT-002 Resource Exhaustion (DoS)** | **None** | **PARTIAL** ← probe `openclaw-bot-kou` | L5 governor covers spend + volume + lifetime + circuit breaker, but only at the LLM-call layer. No tool-execution timeout cap; no per-session message rate cap beyond Telegram's allowFrom gate. |
| T-IMPACT-003 Reputation Damage | LLM provider content policies | **L3, L4** | L3 outbound gate + L4 redaction prevent the bot itself from emitting flagged content even if upstream policies miss |

## Gap analysis: the three "None / None specific" threats

### T-DISC-001 Tool Enumeration

**Vector:** Adversary asks the agent to enumerate available tools or MCP capabilities (directly: "list every tool you have access to"; or indirectly via crafted document).

**Why it matters:** Successful enumeration informs downstream attacks (T-EXEC-003 tool argument injection, T-IMPACT-001 unauthorized command execution).

**Current status on Gregor:** Berman has no deliberate coverage. L5 dedup might fire if attacker re-probes, but a one-shot enumeration prompt is not addressed.

**Probe (bead `openclaw-bot-lw4`):** Write a test in `src/defense/__tests__/` that submits known tool-enumeration prompt patterns. If the test passes against current defense → coverage is incidental, document it as such. If it fails → real gap, file follow-up bead with mitigation proposal (likely L5 governor pattern match on enumeration phrasing or L3 outbound gate redaction of tool names).

### T-IMPACT-002 Resource Exhaustion (DoS)

**Vector:** Malicious user (or compromised allowlisted account) floods bot with messages or triggers expensive tool chains.

**Why it matters:** Cost amplification (LLM calls), reputational damage (bot unavailable), potential infrastructure impact.

**Current status on Gregor:** L5 governor caps spend + volume + lifetime + per-caller circuit breaker. Telegram `allowFrom` is a hard gate. Missing: per-session message rate cap beyond allowFrom; tool-execution timeout (`tools.exec.timeoutMs`).

**Probe (bead `openclaw-bot-kou`):** Set `tools.exec.timeoutMs` on Gregor; document per-session message rate cap if a gateway-level config exists, otherwise implement in defense plugin. Verify cost ceiling holds under simulated flood.

### T-EXFIL-003 Credential Harvesting

**Vector:** Prompt-injected agent reads `~/.openclaw/agents/<id>/agent/auth-profiles.json` or environment variables and exfiltrates via `web_fetch` / `message_sending`.

**Why it matters:** A successful exfil compromises every channel and provider the agent has credentials for.

**Current status on Gregor:** L6 path guards block reads of credential files. Safety hook (per MEMORY note) blocks credential transfers without explicit ack. **But:** no deliberate test coverage for ATLAS T0009 sub-techniques (collection from local system, collection from credential stores, etc.).

**Probe (bead `openclaw-bot-7gg`):** Write a test that attempts credential read + exfil through every plausible vector. Pass criterion: blocked at L6 (read attempt) or L3/L4 (exfil attempt). Document results.

## Defensible "complementary, not redundant" story

For any future audit asking "why a third-party defense system on top of OpenClaw's built-in mitigations":

1. **OpenClaw's threat model explicitly admits** the most critical threat (T-EXEC-001) has detection-only mitigation. Berman L1+L2 provide blocking.
2. **OpenClaw's model treats sandbox as optional** ("Docker sandbox option"). Our policy + ClawKeeper make plugin-level enforcement effectively mandatory.
3. **OpenClaw's model lacks an explicit semantic-parsing layer** for LLM instruction interpretation. Berman L2 is exactly that.
4. **Three threats have no documented mitigation** at all. Our gap analysis above turns those into testable probes rather than acceptance.

The architectures align rather than conflict. Most ATLAS threats fall into either Berman scope (input/output/execution/cost) or infrastructure scope (gateway, file permissions, network) — and the few "None specific" rows now have probe owners.

## Sources

- [OpenClaw Threat Model (MITRE ATLAS)](https://docs.openclaw.ai/security/THREAT-MODEL-ATLAS.md) — v1.0-draft, 2026-02-04
- [MITRE ATLAS Framework](https://atlas.mitre.org/) — adversarial threats to AI/ML systems
- [Reference/DEFENSE-SYSTEM.md](DEFENSE-SYSTEM.md) — Berman 6-layer authoritative reference
- [Reference/CLAWKEEPER.md](CLAWKEEPER.md) — supply-chain + drift detection
- [Reference/SECURITY.md](SECURITY.md) — VPS+LLM hardening (network/file-permission scope)
- Matthew Berman, original 6-layer architecture: [twitter thread](https://x.com/MatthewBerman/status/2030423565355676100)
