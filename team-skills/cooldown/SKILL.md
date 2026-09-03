---
name: cooldown
description: Safely close active Agent Academy teammates' persistent visible PowerShell/Windows Terminal sessions after explicit confirmation. Use when asked to dismiss, close, stand down, or cool down visible team sessions.
---

# Cool down the Agent Academy team

Cooldown closes all targeted persistent active-member sessions and can discard in-flight work that has not reached a durable outbox. It is operational teardown, never a greeting or task assignment. It closes only windows whose recorded process identity and exact window handle still match.

## Run

1. Read `governance/roster.json`, `governance/team.md`, `governance/transport.md`, and ignored `governance/trainer.local.md` when present.
2. Confirm the actor is the lead, or the deputy under delegated or supervised-failover authority. Any other actor stops.
3. Confirm no target has unfinished work or an unsaved required reply. Ask for a checkpoint/outbox first when work is active.
4. Dry-run `scripts/cooldown-team.ps1 -Dispatcher <actor-id> -WhatIf`.
5. Verify the plan contains all targeted recorded active-member sessions, places the dispatcher last so earlier results remain observable, and contains no process-wide kill. Closing endpoints does not change authority or roster status.
6. Explain that the target CLI/TUI processes will end and obtain explicit confirmation.
7. Run the same command without `-WhatIf`.
8. Report every member, status, processId, windowHandle, and reason.

## Safety invariants

- Close only the exact recorded visible window after validating stored member/session/title metadata, visibility, owner process, and process-start freshness.
- Never use `Stop-Process`, `taskkill`, a PID-wide kill, or broad title/process matching. Academy windows can share one Windows Terminal process.
- Provider-controlled current titles are mutable UI and are not identity.
- Remove local warm-session state only after the exact window is confirmed closed.
- `notFound`, `identityRejected`, `closeRequestFailed`, `closeTimedOut`, or `error` is fail-closed. Do not broaden the target or guess another window.
- Preserve unfinished work and durable inbox/outbox records; do not modify external wrappers, project files, production data, or roster state.
- A cooldown result proves teardown only. A later warmup creates fresh readiness sessions.

The deterministic launcher is `scripts/cooldown-team.ps1` at the Academy repository root.
