# Workflow — focused project execution and direct-wrapper coordination

## 1. Operating model

The team may register several projects, but it has at most one execution focus.

- Machine-readable state: `status/project-focus.json`.
- Each project's source, plan, and worklog stay in that project's own workspace.
- This repository stores the portfolio index, the current focus, a checkpoint, the next action, decisions, and handoff links.
- **Only the Trainer approves a focus change.**
- Never switch focus automatically because a project is blocked. Record a checkpoint, ask, and preserve the resume path.

Portfolio statuses: `queued`, `focused`, `waiting`, `paused`, `completed`, `archived`.

Use `scripts/manage-project-focus.ps1`:

```powershell
# Register without starting work
.\scripts\manage-project-focus.ps1 -Action Register -Id <slug> -Name <name> -Location <path-or-repository>

# Set initial focus (Trainer-approved)
.\scripts\manage-project-focus.ps1 -Action Focus -Id <slug> -ApprovedBy Trainer

# Switch focus only after recording the current checkpoint
.\scripts\manage-project-focus.ps1 -Action Focus -Id <next-slug> -ApprovedBy Trainer `
  -Checkpoint <verified-state> -NextAction <resume-action>
```

The state manager writes atomically and rejects duplicate ids, multiple focused projects, unapproved focus changes, and switches without a checkpoint.

## 2. Hierarchy and dispatch authority

1. **The lead** accepts Trainer requests, controls normal orchestration, and owns final acceptance.
2. **The deputy** may dispatch only under explicit delegation from the lead, or under supervised failover.
3. **Operational members** receive bounded task packets from the lead or an authorized deputy. A member on leave receives none.
4. **Everyone is a technical generalist.** Assignment follows current fit and availability, not permanent role silos.
5. Any member may challenge a plan, correct a mistake, or demand missing evidence. This is expected behavior, not insubordination.

Focus authority never transfers. The Trainer approves every focus change regardless of who is dispatching.

## 2A. Platform subagents are forbidden

Follow `no-subagents.md` without exception. No dispatcher or member may create, call, wait for, resume, or use a harness-managed child/forked agent. A platform subagent is not a roster member and cannot be a maker, reviewer, dispatcher, approver, fallback, or evidence source.

Delegation is valid only when the named active roster member is reached through that member's configured external provider/runtime and direct wrapper, with a durable packet and reply. If a skill or tool requires subagents, perform the work inline, use an allowed direct backend, dispatch to a real roster member, or stop and ask the Trainer. Never relabel a child-agent result as a member reply.

## 3. Maker and reviewer gate

**Code is teamwork.** No member writes, reviews, and approves the same code alone. Team documents and skills refer to this as the **IRON RULE**; it is the same gate described here.

Every code-changing task requires:

- one named maker;
- one different **active** reviewer;
- observable acceptance criteria;
- exact allowed mutation boundaries;
- verification evidence; and
- stated risks and unknowns.

The maker may not be the only reviewer or approver. If the lead writes the code, another member owns the independent technical review before the lead records acceptance.

Non-code work needs review too when it touches security, authentication, authorization, privacy, payments, production data, dependencies, architecture, or a public-facing recommendation.

## 4. Task packets

Assignments live at `inbox/<member-id>/<task-id>.md`; replies live at `outbox/<member-id>/<task-id>.md`.

Project work must name the current focused project. Administrative tasks about the team itself may run with no focus, but may not inspect or mutate a project codebase.

Create packets with `scripts/new-task-packet.ps1`, which enforces the contract:

- dispatcher — the lead, or the deputy under recorded authority;
- authority — `lead`, `delegated`, or `failover`;
- assignee — one **active** member;
- project id and work type;
- reviewer for code work, **different from the maker**;
- allowed mutations, acceptance criteria, and required evidence.

Keep packets offline-complete. The receiving member cannot see your screen, your scrollback, or your reasoning. Include the minimum sufficient context, real paths, the exact commands, explicit non-goals, and the return format you want back. A packet that assumes shared context produces a confident answer to the wrong question.

## 5. Transport

See `transport.md`. The packet contract remains here; the swappable carrier contract and failure semantics live there. Machine paths and current wrapper assignments belong only in ignored local configuration.

Use full paths and an explicit working directory. Respect each wrapper's permission and timeout model.

**Do not infer failure from a missing final line.** Check side-channel evidence and process state first. A member who is still working looks identical to one who has died, until you look.

## 6. Review and acceptance

Before accepting a result:

1. Confirm the task matches the current focus and the authorized slice.
2. Inspect the maker's actual diff and evidence — not the maker's summary of it.
3. Confirm the reviewer is a different active member.
4. Run the relevant verification gates yourself.
5. Record assumptions, remaining risks, and the next action.
6. The lead accepts normally. Under supervised failover the deputy may hold a result for review but may not waive a required gate.

A review that finds nothing is a result worth stating. A review that was not actually run is not.

A deliverable is complete only when the requested output exists, assumptions are visible, verification is recorded, and residual risk is stated plainly. Report failures and skipped steps faithfully; state completed and verified work plainly.

## 7. Continuous worklog

Append a short bullet to `vault/02-worklog/YYYY-MM-DD.md` after every meaningful finding, decision, dispatch, file change, test result, or verification gate — **as it happens**.

Do not batch the whole session at the end. The end-of-session summary is written from memory, and memory is where the useful details go missing. The worklog exists so that a future session can reconstruct what was tried and why, including the attempts that failed.

## 8. Long-running project and focus switching

Each project should keep a readable plan and worklog in its own workspace.

Before switching focus, record:

- the exact current state;
- which tests, builds, and reviews completed;
- what is uncommitted or deployed;
- the blocker or reason for switching;
- the next action needed to resume; and
- risks and unknowns.

Then update focus state with Trainer approval. Several projects may stay registered or paused; execution still happens against exactly one.

## Lead quota and context guardrails

These are operating thresholds, not provider limits.

- The lead's routine default is a standard-context model. Use a high-capability model for a bounded task only when lead-level reasoning or final review materially benefits from it.
- A large-context model is never a persistent default. Select it explicitly for one task, record why the larger context is needed, and return to the routine default afterward.
- Treat missing or stale usage data as **UNKNOWN**, never as available capacity. Before broad lead work, inspect the provider's current usage and context telemetry in the interactive session.
- At 70 percent five-hour usage, start no new broad slice; checkpoint and finish only the current bounded gate. At 85 percent, stop nonessential lead work and hand off to the deputy. At 85 percent seven-day usage, reserve the lead for lead decisions and final acceptance.
- At 30 percent context remaining, compact using the harness entry instructions. At 15 percent, record the checkpoint and next action, then clear context before continuing.
- On a 429, do not blind-retry. Read the reset information, distinguish a model-specific limit from a shared limit, then switch to the routine model, hand off, or wait as the actual limit permits.

## 9. Failover

Normal chain: **lead → delegated or supervised deputy → stop and wait for the Trainer**.

Operational members do not become orchestrators automatically. If both the lead and the deputy are unavailable, pause cleanly.

## 10. Acknowledgment and language

- Reply to the Trainer in the language the Trainer uses.
- Use the workspace language for packets, worklogs, status, and internal reports.
- On an action order, the acting member acknowledges once in her own voice, then works.
- Pure questions, status checks, and conversation need no acknowledgment line.
