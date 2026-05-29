# Agent Topology

Promoted out of local agent guidance to keep public routing lean. This public reference describes the generic multi-agent pattern; concrete bot names, Linux users, gateway ports, channels, account mappings, and host state belong in private operator notes.

## Pattern

A small OpenClaw fleet can run on one host with a multi-user pattern:

- one Linux user per bot
- one systemd service per bot
- one private gateway listener per bot
- one workspace and identity scaffold per bot
- shared hardening, backup, monitoring, and wrapper doctrine
- per-bot skills, channels, models, and persona files

## Roles

Use role labels publicly. Keep private deployment mappings out of git.

- Primary personal operator bot: daily operations, CRM, health/lifestyle, light research.
- Publishing/content bot: marketing, creative writing, design/UI workflows.
- Dev/data bot: code, SQL/BI, project-management workflows.
- Research/knowledge bot: synthesis, education, PKM workflows.
- Security/ops bot: adversarial review, sysadmin, cloud/devops workflows.

## Coverage Model

Most personal-OS verticals can map onto the roles above. Finance and money-moving work should remain deferred or move into a single-purpose, credential-isolated bot with stricter security posture.

## Bootstrap Order

1. Lowest-blast-radius content/publishing bot.
2. Dev/data bot.
3. Research/knowledge bot.
4. Security/ops bot last, after chassis hygiene is proven.

## Retired Patterns

- Bidirectional file-pipeline agents are retired for this repo. `src/pai-pipeline/` is retained as archival source only.

## Evaluation Notes

- Keep coding delegation as a capability question, not a topology default.
- Use Mission Control vNext and the bundled Control UI as control-plane surfaces.
- Preserve concrete route, account, port, allowlist, and host inventory in private operator notes.
