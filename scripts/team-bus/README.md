# Relay Inbox Convention

This document specifies the file-based messaging and inbox directory convention for the Agent Academy team-bus coordination layer.

## Directory Layout

Each agent has a dedicated inbox structure under `inbox/<agent>/`:

| Path | Purpose |
| :--- | :--- |
| `inbox/<agent>/.tmp/` | Message staging directory. Used for writing content before atomic rename. |
| `inbox/<agent>/pending/` | Inbox queue for incoming messages. Only fully written files reside here (via atomic rename). |
| `inbox/<agent>/inflight/` | Message currently claimed and being processed by the agent. |
| `inbox/<agent>/archive/` | Successfully processed and completed messages. |
| `inbox/<agent>/quarantine/` | Invalid, malformed, or loop-detected messages. Contains both `.json` payload and `.reason` sidecar. |

*Note: All message publications must write to the same-volume staging directory `.tmp/` first and then perform an atomic rename into `pending/` to avoid race conditions with readers.*

---

## Message Schema Fields

Messages must comply with the following JSON schema:

| Field | Type | Description | Required |
| :--- | :--- | :--- | :--- |
| `schemaVersion` | String | Version identifier of the schema (e.g., `"1.0.0"`). | Yes |
| `id` | String | A 26-character globally unique ULID (lexicographically sortable). | Yes |
| `thread` | String | Thread identifier grouping related messages. | Yes |
| `from` | String | Declared sender name. Treated as coordination-only metadata (never trust as identity). | Yes |
| `to` | Array of Strings | Intended recipient agent name(s). | Yes |
| `type` | String | Message type classification (e.g., `"handoff"`, `"status"`, `"query"`). | Yes |
| `task` | String | Contextual task identifier or command. | Yes |
| `body` | Mixed | Payload content containing task-specific parameters or results. | Yes |
| `refs` | Array of Strings | ULIDs of referenced past messages. | No |
| `parentId` / `replyTo` | String | ULID of the direct parent message. | No |
| `depth` | Integer | Hopping depth counter. Incremented by 1 at each hop. | No |
| `ts` | String | ISO 8601 (RFC 3339) timestamp of message creation (e.g., `"2026-07-14T21:33:04+07:00"`). | Yes |

---

## Team Channel Rule

* `team-channel.md` is **append-only** and has a **single-writer** restriction.
* Only the **active orchestrator** is permitted to write/append to `team-channel.md`.

---

## Loop and Runaway Bounds

To prevent runaway cascades and infinite message loops, agents and the orchestrator must enforce the following bounds:

* **Depth Quarantine:** Messages with `depth` > `N` hops (where `N` is configured by the orchestrator, defaulting to 10) must be immediately routed to the `quarantine/` folder.
* **Rate Limits:** Maximum dispatch rate of **5 messages per 60 seconds** per agent.
* **Total Budget Cap:** Limit total messages processed within a single run/session to a predefined cap (e.g., 50 messages) to prevent memory/token/file consumption.
* **Duplicate Detection:** Rolling-hash-based duplicate detection of message payloads. Identical bodies or hashes detected within the window must be rejected and quarantined.

---

## Reconcile and Auto-Pump Rules

* **At-Least-Once Reconcile Rule:** If an agent crashes while processing a message (i.e. message remains stuck in `inflight/`), **manual reconciliation is required**. The orchestrator and libraries must **NEVER auto-redispatch** or silently re-run inflight items to prevent side effects.
* **No Auto-Pump:** The inbox does not automatically ingest or pump messages. Message processing and inbox state transitions must be invoked explicitly by the orchestrator based on judgment.
* **Output Capture:** Agents must never write to the team-bus files directly. The orchestrator invokes the agent wrapper, captures its standard output (stdout), and writes the resulting reply envelope on behalf of the agent.

---

## orchestrator-lock.ps1

For the coordinator lock helper, refer to the implementation and docs in [orchestrator-lock.ps1](orchestrator-lock.ps1).

- Holds `orchestrator.lock` exclusively for the manual pump; watchers read the read-shared `orchestrator.status.json`, never the lock file.