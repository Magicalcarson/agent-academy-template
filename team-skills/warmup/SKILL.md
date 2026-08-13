---
name: warmup
description: Open or reuse visible persistent interactive CLI sessions for active Agent Academy teammates.
---

# Warm up the Agent Academy team

Warmup establishes transport readiness only. It does not assign project work.

## Run

1. Read `governance/roster.json`, `governance/workflow.md`, `governance/transport.md`, and local operator preferences when present.
2. Confirm the actor is `academy-lead`, or `academy-deputy` under delegated/supervised-failover authority.
3. Dry-run `scripts/warmup-team.ps1 -Dispatcher <actor-id> -WhatIf`.
4. Verify the plan contains every other active, dispatchable roster member and excludes the dispatcher and on-leave members.
5. Ask for GUI/process-launch approval, then run without `-WhatIf`.
6. Report each member, status, processId, and windowHandle.
7. For later work, create a durable packet first, dry-run `scripts/send-team-session.ps1`, then deliver to the existing session.

## Invariants

- Visible `Normal` Windows Terminal windows and native interactive provider modes only.
- Provider `interactiveArguments` come from local `providers.json`; credentials never enter this repository.
- Do not open replacement windows just to deliver another packet.
- Do not dispatch platform subagents.
