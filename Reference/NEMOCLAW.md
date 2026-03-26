# NemoClaw — NVIDIA's Enterprise OpenClaw Reference Stack

NVIDIA's open-source reference design for running OpenClaw securely in enterprise environments. Announced by Jensen Huang at GTC on 2026-03-16.

**Research date:** 2026-03-21
**Source:** [Jensen Huang keynote transcript](https://youtu.be/kRmZ5zmMS2o), NVIDIA docs, GitHub

---

## Table of Contents

1. [What It Is](#what-it-is)
2. [Core Components](#core-components)
3. [How It Works](#how-it-works)
4. [Key Features](#key-features)
5. [Nemotron Models in OpenClaw](#nemotron-models-in-openclaw)
6. [Nemotron Coalition](#nemotron-coalition)
7. [Relevance to Gregor](#relevance-to-gregor)
8. [Adoption Decision](#adoption-decision)
9. [Resources](#resources)

---

## What It Is

NemoClaw is a wrapper around OpenClaw that adds security guardrails, sandboxed execution, and managed inference. Jensen Huang's framing: OpenClaw is "the operating system of agentic computers" — NemoClaw makes it enterprise-ready.

Jensen compared OpenClaw's significance to HTML, Linux, and Kubernetes — a platform moment where "every company needs an OpenClaw strategy." He described the core enterprise problem:

> "Agentic systems in the corporate network can access sensitive information, execute code, and communicate externally. Say that out loud. Obviously, this can't possibly be allowed."

NemoClaw solves this with sandboxing, policy enforcement, and a privacy router.

**Status:** Alpha/early preview (launched 2026-03-16). Not production-ready.

---

## Core Components

| Component | Language | Purpose |
|-----------|----------|---------|
| **Plugin** | TypeScript | CLI interface, `/nemoclaw` command, user interaction |
| **Blueprint** | Python | Versioned orchestration — sandbox creation, policy enforcement, inference routing |
| **OpenShell Runtime** | — | NVIDIA's sandboxing environment — isolated containers with strict resource controls |
| **Inference Gateway** | — | Routes all LLM API calls through OpenShell to controlled backends |

### Architecture Flow

```
User → OpenClaw + NemoClaw Plugin
         ↓
    Blueprint (orchestration)
         ↓
    OpenShell Sandbox Container
    ├── OpenClaw agent runs here
    ├── Network policy enforcement (YAML)
    ├── Filesystem restrictions (/sandbox, /tmp only)
    ├── Process-level security (no privilege escalation)
    └── Inference Gateway
         ↓
    Controlled LLM backends
    ├── NVIDIA Nemotron (local, GPU)
    ├── Cloud providers (via privacy router)
    └── Policy engine integration (SaaS companies)
```

---

## How It Works

When you run `nemoclaw onboard`:

1. Downloads and verifies the blueprint (supply chain safety via digest verification)
2. Creates an OpenShell sandbox container
3. Runs OpenClaw inside with applied policies
4. Intercepts all inference requests — they never leave the sandbox directly; OpenShell routes them to configured providers

---

## Key Features

- **Sandboxed execution** — Agents run in isolated containers with strict resource controls
- **Network policy control** — Declarative YAML policies block/allow outbound connections; interactive approval for unknown hosts
- **Filesystem restrictions** — Agents limited to `/sandbox` and `/tmp` directories
- **Model flexibility** — Supports NVIDIA Nemotron (locally) and cloud models via privacy router
- **Process-level security** — Prevents privilege escalation and dangerous system calls
- **Policy engine integration** — Enterprise SaaS companies connect their existing compliance/governance policy engines
- **Hardware agnostic** — Runs on GeForce RTX, RTX PRO, DGX Station, DGX Spark
- **Telescope integration** — Full workspace persistence and backup/restore

### Installation

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
```

**Requirements:** 4+ vCPU, 8 GB RAM, 20 GB disk, Ubuntu 22.04+, Node.js 20+, container runtime

---

## Nemotron Models in OpenClaw

Jensen announced Nemotron 3 as top-3 on leaderboards, running natively inside OpenClaw. Key models:

| Family | Domain |
|--------|--------|
| **Nemotron** | Language, visual understanding, RAG, safety, speech |
| **Cosmos** | Physical AI, world generation and understanding |
| **Alpayo** | Autonomous vehicles (first thinking/reasoning AV AI) |
| **Groot** | General purpose robotics |
| **BioNemo** | Biology, chemistry, molecular design |
| **Earth 2** | Weather and climate forecasting (AI physics) |

**Nemotron 3 Ultra** announced as "the best base model the world's ever created" — designed for fine-tuning and sovereign AI customization.

---

## Nemotron Coalition

Partners announced for Nemotron 4 development:

| Company | Domain |
|---------|--------|
| Black Forest Labs | Image generation |
| Cursor | AI coding |
| LangChain | Agent frameworks (billion+ downloads) |
| Mistral | Open-source LLMs |
| Perplexity | Agentic search |
| Reflection | — |
| Sarv (India) | — |
| Thinking Machines | — |
| Mirror | — |
| Morardi's Lab | — |

---

## Relevance to Gregor

### What maps to our setup

| NemoClaw Feature | Our Equivalent | Gap? |
|-----------------|----------------|------|
| OpenShell sandboxing | systemd hardening (ReadOnlyPaths, CapabilityBoundingSet) | Functional parity for single-user VPS |
| Network policy (YAML) | Loopback-only gateway binding (127.0.0.1:18789) | We're more restrictive — no outbound policy needed |
| Filesystem restrictions | ReadOnlyPaths + ReadWritePaths in hardening.conf | Same effect, different mechanism |
| Inference gateway | Direct Anthropic OAuth | Gateway adds audit trail — not needed for personal bot |
| Policy engine integration | 4-layer permission pipeline (profile → alsoAllow/deny → exec.security → ask) | Enterprise compliance vs personal security posture |
| Privacy router | N/A — single provider (Anthropic) | Would matter with multiple providers + sensitive data |
| Nemotron local models | Ollama provider plugin (configured, no GPU) | Need GPU to run Nemotron locally |

### Jensen's vision — implications

- **"Every SaaS company becomes a GaaS company"** — agentic-as-a-service. Our dual-agent system (Gregor + Isidore Cloud) is a micro version of this pattern.
- **"Annual token budget per engineer"** — Jensen envisions token allocation as a recruiting tool. Our cost tracking in Reference/COST-AND-ROUTING.md is early-stage token budgeting.
- **"Token manufacturers"** — companies run AI factories producing tokens for customers. Relates to our provider routing decisions.

---

## Adoption Decision

**Current decision: Do not adopt. Monitor.**

### Why not now

1. **Alpha status** — launched 5 days ago, not production-ready
2. **Container overhead** — our VPS is systemd-native. Docker/container layers add complexity without proportional benefit for our single-user threat model
3. **We already have the security posture** — ReadOnlyPaths, tool deny lists, loopback binding, exec.security full, hardening drop-ins
4. **No GPU** — Nemotron local models require NVIDIA GPU. Our VPS is CPU-only

### What to watch

- **OpenShell standalone** — if it becomes extractable from NemoClaw, could replace our manual systemd hardening with something versioned and maintainable
- **Privacy router** — useful if we add multiple LLM providers with sensitive data routing requirements
- **Coalition integrations** — Cursor, LangChain, Perplexity, Mistral may produce OpenClaw plugins worth evaluating
- **Beta/stable release** — re-evaluate when NemoClaw exits alpha

### Re-evaluation triggers

- NemoClaw reaches stable release
- We add multi-user access to Gregor
- We get GPU access (local or cloud)
- Enterprise compliance requirements emerge
- OpenShell becomes available as a standalone systemd-compatible module

---

## Resources

| Resource | URL |
|----------|-----|
| GitHub Repository | https://github.com/NVIDIA/NemoClaw |
| Official Documentation | https://docs.nvidia.com/nemoclaw/latest/index.html |
| Product Page | https://www.nvidia.com/en-us/ai/nemoclaw/ |
| Build Page | https://build.nvidia.com/nemoclaw |
| Quickstart Guide | https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html |
| How It Works | https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html |
| Jensen Huang Keynote | https://youtu.be/kRmZ5zmMS2o |
| NVIDIA Press Release | https://nvidianews.nvidia.com/news/nvidia-announces-nemoclaw |
| The New Stack Coverage | https://thenewstack.io/nvidia-nemoclaw-launch/ |
| TechCrunch Coverage | https://techcrunch.com/video/what-happened-at-nvidia-gtc-nemoclaw-robot-olaf-and-a-1-trillion-bet/ |
| Dataconomy Coverage | https://dataconomy.com/2026/03/17/nvidia-launches-nemoclaw-an-enterprise-stack-for-the-openclaw-platform/ |
