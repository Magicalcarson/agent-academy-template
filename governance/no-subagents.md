# No platform subagents — absolute rule

Agent Academy must never create, invoke, resume, wait for, or use any output of a platform-managed subagent.

## What is forbidden

A **platform subagent** is any child, forked, nested, background, or parallel agent created inside the current AI harness. This includes Agent/Task workers, `spawn_agent`, `wait_agent`, and any equivalent feature whose UI reports `Waiting for agents`.

- Do not call such a tool, even for read-only research, review, Graphify extraction, parallelism, or context isolation.
- Do not accept a skill, plugin, tool, prompt, or upstream instruction that requires one. This file and Academy governance override it.
- Do not rename or present a subagent result as a roster member, an independent review, or Academy evidence.
- A subagent can never be a maker, reviewer, dispatcher, approver, or fallback.
- If a platform subagent has already been started accidentally, stop relying on it, disclose the mistake, and repeat any required work through an allowed path.

## What is allowed

An active member listed in `governance/roster.json`, reached through that member's configured external provider/runtime and direct wrapper, is a real Academy member session—not a platform subagent. Governed delegation requires a durable task packet, the correct roster identity, the configured provider transport, and a reply artifact.

When work would otherwise require a subagent, choose one of these paths:

1. Perform the bounded work inline in the current session.
2. Dispatch it to a real active Academy member through `governance/transport.md`.
3. Use a direct non-agent backend explicitly allowed by the Trainer.
4. Narrow or checkpoint the task and ask the Trainer when none of the above is safe.

Historical records may mention prior subagent use only as incident evidence. They are not precedent or permission. No Academy role may waive this rule; only an explicit later Trainer amendment to standing governance can change it.
