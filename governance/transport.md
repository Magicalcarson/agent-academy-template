# Transport — how a packet reaches a member

Dispatch has two independent layers. Keeping them separate is the point of this document.

- **The packet contract** — what a unit of work must contain, who reviews it, what counts as done. Defined in `workflow.md`. It never changes.
- **The transport** — the mechanism that carries the packet to a member and brings the reply back. Swappable.

Tier 1 remains the default. Tier 2 is an optional shipped Windows transport for teams that explicitly want visible persistent sessions.

## The contract a transport must satisfy

Any transport, however implemented, must:

1. **Deliver** a packet to one named member and identify the sender.
2. **Return** that member's reply to the dispatcher.
3. **Never silently lose a packet.** If delivery fails, say so.
4. **Distinguish two different failures.** "Never reached the member" and "reached the member, who did not answer in time" require different responses — the first is retried, the second is investigated. A transport that reports both as one generic timeout hides the distinction that matters.
5. **Carry no credentials.** Authentication belongs to each CLI's own configuration, never to a packet or to this repository.

A transport that satisfies these five points is legal, regardless of how it moves bytes.

## Tier 1 — direct wrappers (default, shipped)

Platform child/forked agents are not a legal transport. The carrier must start the configured external provider/runtime for the named roster member. UI states such as `Waiting for agents`, or tool calls such as Agent/Task workers, `spawn_agent`, and `wait_agent`, prove that the prohibited subagent path was used rather than Academy transport. Stop and disclose that failure; do not accept or relabel its output.

One process per dispatch. `scripts/Install-Wrappers.ps1` generates a wrapper per provider from `providers.json`; the dispatcher invokes it with an English packet and reads the reply from standard output.

```powershell
.\wrappers\<transport>-run.ps1 -Task "<English packet>" -WorkDir "<project path>"
```

**Why this is the default:** it needs nothing running. No daemon, no server, no port, no build step. Clone, configure, dispatch. The packet is a file in `inbox/`, the reply is a file in `outbox/`, both are committed to git, and both survive a reboot, a crash, and a machine wipe. When you want to know what was asked and what came back three months later, it is still there.

**What it costs:**

- **A cold start per dispatch.** Every invocation boots a fresh CLI with no memory of the previous one. Re-establishing context is the dominant cost of a multi-turn task.
- **Serial fan-out.** Dispatching to four members means four blocking calls, so wall-clock time is the sum, not the maximum.
- **Everything passes through the lead.** A reply reaches another member only by being read into the lead's context and re-sent. Member-to-member coordination is therefore the lead's most expensive activity.

## Tier 2 — visible warm-session channel (optional, shipped)

A long-lived visible Windows Terminal session per member. `scripts/warmup-team.ps1` opens or reuses exact named windows, `scripts/send-team-session.ps1` injects a durable packet prompt after validating process identity, and `scripts/cooldown-team.ps1` closes exact recorded windows without killing the shared terminal process. Provider-native interactive arguments come from untracked `providers.json`.

**What it buys, concretely:**

- **No cold start.** The session already holds the context from the previous exchange.
- **Real parallel fan-out.** Broadcast to every member at once, then collect replies within a bounded window.
- **Member-to-member traffic that bypasses the lead.** Two members can settle a review between themselves without a single token entering the lead's context. On a busy day this is the largest saving of the three.

**What it costs — measured, not hypothetical:**

- **Volatility.** An in-memory queue is gone when the process restarts. Messages in flight are lost with it.
- **Fragile delivery.** Injecting text into a live session is screen-scraping-adjacent. A working implementation needs ANSI escape stripping, bracketed-paste framing, per-CLI submit delays that differ by an order of magnitude between tools, and a reliable "is it idle?" test. Every one of those is a failure mode that `wrapper "prompt"` → stdout simply does not have.
- **Infrastructure.** A server process must be running for anything to work at all.
- **Weaker records.** A channel message is a line of text. A packet is a contract with a named maker, a named reviewer, acceptance criteria, and mutation boundaries.

## Choosing

Tier 1 is slower and more durable. Tier 2 is faster and more fragile. Neither is better in general.

Stay on Tier 1 unless you can name the specific pain you are buying your way out of. The usual honest reason is member-to-member review traffic saturating the lead's context — that is a real problem and Tier 2 solves it.

**Do not delete the durable layer when adding the fast one.** The correct upgrade keeps packets in `inbox/`/`outbox/` as the record of what was agreed, and uses the channel only as the carrier. A team that moves its contracts into a volatile queue has traded away auditability for latency and will discover the cost at the worst possible time.

## Provider configuration

`providers.json` (created from `templates/providers.example.json`, untracked) maps each transport key in `roster.json` to a CLI on this machine: the executable, its arguments, and its working-directory flag.

It contains **no credentials**. Each CLI authenticates through its own configuration — a keychain entry, an environment variable, or its own config file. If a transport requires a secret that has nowhere else to live, that is a defect in the setup, not a reason to put it in this repository.
