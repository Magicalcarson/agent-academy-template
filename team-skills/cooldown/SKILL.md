---
name: cooldown
description: Safely close exact visible Agent Academy warm-session windows after explicit confirmation.
---

# Cool down the Agent Academy team

Cooldown closes only windows whose recorded process identity and exact window handle still match.

## Run

1. Read `governance/roster.json`, `governance/workflow.md`, and local operator preferences when present.
2. Confirm no target has unfinished work or an unsaved required reply.
3. Dry-run `scripts/cooldown-team.ps1 -Dispatcher <actor-id> -WhatIf`.
4. Verify the dispatcher is last and no process-wide kill is planned.
5. Ask for explicit close approval, then run without `-WhatIf`.
6. Report every member, status, processId, and windowHandle.

## Invariants

- Close exact recorded windows only; never kill a shared Windows Terminal process.
- Missing or stale identity fails closed.
- Preserve unfinished work and durable inbox/outbox records.
