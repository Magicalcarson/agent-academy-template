---
name: warmup
description: Open active Agent Academy teammates in visible native interactive CLI/TUI sessions so the Trainer can watch responses and tool activity. Use when asked to warm up, prepare, or bring the team online before assigning work.
---

# Warm up the Agent Academy team

Open or reuse persistent readiness sessions only. Each member keeps one named visible Windows Terminal session; later governed packets are delivered to that existing native CLI/TUI with `scripts/send-team-session.ps1`. Warmup establishes transport readiness only. It does not assign project work, inspect project files, or fabricate a roster member.

## Run

1. Read `governance/roster.json`, `governance/team.md`, `governance/transport.md`, and ignored `governance/trainer.local.md` when present.
2. Confirm the actor is `academy-lead`, or `academy-deputy` under delegated/supervised-failover authority.
3. Dry-run `scripts/warmup-team.ps1 -Dispatcher <actor-id> -WhatIf`.
4. Verify the plan contains every other active, dispatchable roster member and excludes the dispatcher and on-leave members.
5. Ask for GUI/process-launch approval, then run without `-WhatIf`. A live matching session returns `reused`; only a missing or stale session may return `launched`.
6. Remain responsible for permission prompts from sessions you launched. Inspect the exact command and use `scripts/send-team-session.ps1 -PermissionDecision ApproveOnce` or `Deny`; the carrier intentionally offers no persistent always-allow decision. Escalate destructive, production/customer-data, credential, data-egress, spending, focus-change, or scope-expansion requests to the Trainer.
7. Report each member, status, processId, and windowHandle. A launched process proves transport readiness, not completion of later work.
8. For later work, create a durable packet first, dry-run `scripts/send-team-session.ps1`, inspect the target, then deliver to the existing session.

## Invariants

- Visible `Normal` Windows Terminal windows and native interactive provider modes only.
- Keep each session visible for the Trainer; do not minimize or hide it.
- Provider `interactiveArguments` come from local `providers.json`; credentials never enter this repository.
- Do not open replacement windows just to deliver another packet.
- Preserve inbox/outbox records and maker/reviewer gates. A greeting creates no work authorization.
- Do not dispatch platform subagents.

The deterministic launcher is `scripts/warmup-team.ps1` at the Academy repository root.
