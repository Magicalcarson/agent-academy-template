# Vault — the shared second brain

The vault is an Obsidian vault at `vault/`, inside this repository. It extends governance and memory; it does not replace either.

Scaffold it from `templates/vault/` during onboarding — see `prompts/02-install-obsidian-vault.md`.

## Layout

Hub note at the vault root; every other note links back to it.

| Folder | Contents | Written by |
|---|---|---|
| `00-governance/` | Junction to `governance/` — read-only mirror | governance edits only |
| `01-memory/` | Junction to the harness memory directory — read-only mirror | the memory protocol only |
| `02-worklog/` | Daily worklog files `YYYY-MM-DD.md` | any member |
| `03-team/` | One identity note per member, tagged `team/<id>` | the lead |
| `03-projects/` | One map-of-content note per project | the lead |
| `04-research/` | Persisted research output | any member |
| `05-architect/` | Refreshable codebase architecture notes | the lead orchestrates |
| `07-decisions/` | Decision records, one file per decision, plus an index | any member |
| `99-inbox/` | Quick captures awaiting consolidation | anyone, Trainer included |

**Graph convention:** encode membership as a tag (`tags: [team, team/<id>]`) rather than a filename, so renaming a note never breaks the graph. The shipped `graph.json` colors nodes by those tags and by folder path.

## Rules

1. **Junctions are read-only mirrors.** Never edit `00-governance/` or `01-memory/` through the vault — edit the source. The junctions exist so that Obsidian's graph, search, and backlinks can see those files.

   Two caveats worth knowing before they cost you an hour:

   - **Obsidian does not watch the junction target.** Editing `governance/workflow.md` from an editor outside Obsidian will not update the graph or search index. Reload the app (`Ctrl/Cmd+P` → *Reload app without saving*) after editing governance or memory externally.
   - **The privacy gate rejects reparse points.** Create the junctions *after* running `Invoke-PrivacyGate.ps1`, or the gate will fail on them. They are machine-local state, not template content.

   Enforce read-only in the UI with the **Force Read Mode** community plugin, configured for `00-governance/**` and `01-memory/**`. It is a soft block, not a filesystem permission — it prevents the accident, not the deliberate act.

2. **Safe deletion applies** (`safety.md`). Any command that rewrites a note larger than 1 KB must commit or stash first.

3. **The maker/reviewer gate applies** (`workflow.md`). A vault command that touches code — an architecture refresh, a consolidation pass over governance — is code work.

4. **Daily worklog.** New entries go to `02-worklog/YYYY-MM-DD.md`, appended continuously rather than batched at session end.

5. **Commit deliberately.** The vault shares a repository with governance and scripts, so a blind auto-commit timer would sweep unrelated in-progress work into a commit nobody reviewed. Commit after meaningful changes instead. Do not enable timed auto-commit.

6. **Register every vault command here.** If a member installs a new one, this file is updated in the same change. A command that is not listed here does not run.

7. **Recall discipline — read before you work.** A second brain helps only if the right note is open at the right moment. The bottleneck is recall, not capture.

   - **Before working on a codebase that has an architecture note**, read it first. That is the entire point of writing it.
   - **After a major change or merge**, refresh the note. It is a dated snapshot and it goes stale silently.
   - **Decisions belong in `07-decisions/`**, not buried in a worklog entry. "Why did we choose this?" is the question you will actually need answered in six months.

## Graphify single-writer rule

Two concurrent graph builds destroyed a 710-node graph in the system this template came from. The rule below exists because of that, and it is not obeyed by teams who are told the rule without the reason.

- **Protocol first.** A graph *build* — anything that writes `graphify-out/` — runs only when the lead assigns it in a dispatch. No member auto-runs a build; no hook or per-edit rule may trigger one. Read-only `query`, `path`, and `explain` are always available to everyone.
- **Lock, as defense in depth.** Before writing to `graphify-out/`, atomically create the directory `.graphify-out.lock` at the repository root — exclusive create, which fails if it already exists — containing the member name, process id, UTC timestamp, and task. If the lock is already there: **abort and report its contents. Never wait, never overwrite.** Remove the lock in a `finally` block, after success *or* failure. A stale lock may be removed only after confirming its process is dead, and only with the lead's approval; archive it rather than deleting it silently.
- **Atomic promotion.** Build to a temporary file and rename into place after verified success. Never copy over a live `graph.json`. A drop in node count requires the lead's explicit approval, with the expected old and new counts and a reason.
- **Undirected mode.** Keep the graph undirected so an ordinary incremental update can never flip the mode. Directed builds are one-off analyses that stay in scratch output and are never promoted.

## What the vault is not

- Not a replacement for `governance/`, which remains the single source of truth for team rules.
- Not a replacement for the harness memory, which remains the single source of truth for cross-session learning.
- Not a runtime. Members read governance through the harness, not through Obsidian.
- Not Trainer-only. Every active member is expected to use it.
