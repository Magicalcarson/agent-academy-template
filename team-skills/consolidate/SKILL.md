---
name: consolidate
description: Consolidate inbox notes into the team vault without orphaning or overwriting important notes
---

Execute `/consolidate`.

Vault root: `vault\`

Inbox source: `vault\99-inbox\*.md`

Rules:
- Do not install commands or write outside the vault unless explicitly requested.
- Do not permanently delete anything. Safe Deletion only: after successful consolidation, move processed inbox notes to an archive/processed location inside the vault, or mark them as processed in place with a dated note.
- Before overwriting or materially rewriting any existing note larger than 1 KB, create a git safety point first:
  - Prefer a focused commit if the repository is clean enough and the user requested persistent history.
  - Otherwise use `git stash push -m "pre-consolidate safety: <note path>" -- <note path>`.
  - If git is unavailable or the vault is not a git repo, make a timestamped backup copy inside the vault and report it.
- IRON RULE for any code-touching action: before modifying code, scripts, configs, or command files, inspect the relevant files, preserve existing behavior unless explicitly changing it, make the smallest coherent change, and verify with the most relevant available check.
- Search before creating notes. Duplicate notes are vault rot.
- Never create orphan notes. Every created or updated note must be linked from at least one relevant index, MOC, daily note, project note, or source note.
- Never invent facts, entities, dates, sources, or links. Use `TBD` or `unknown` when a value is missing.
- Preserve source text and URLs when consolidating research or external claims.

Steps:
1. Enumerate markdown files matching:
   `vault\99-inbox\*.md`
2. For each inbox note, read it fully and classify its contents:
   - project/work item
   - task
   - decision
   - person/entity
   - concept/idea
   - research/source material
   - meeting/log/work session
   - unclear
3. Identify the appropriate destination by inspecting the vault's existing top-level folders, indexes, MOCs, and nearby naming conventions. Prefer existing folders and note patterns over creating new structures.
4. Search for existing matching notes before creating anything:
   - exact title
   - aliases
   - likely normalized names
   - key unique phrases
5. Merge into existing notes when a matching note exists:
   - append dated bullets or update bounded sections
   - preserve existing frontmatter and user text
   - add backlinks to source inbox note and relevant daily/project/MOC notes
   - create a git safety point before overwriting or materially rewriting any existing note larger than 1 KB
6. Create a new note only when no suitable note exists:
   - place it in the best matching existing folder
   - include clear frontmatter where the vault pattern supports it
   - link it from a relevant MOC/index/project/daily/source note
7. Extract tasks into the vault's existing task or board convention if present. If no clear convention exists, leave tasks in the consolidated destination note under a `## Tasks` section.
8. Extract decisions into the relevant project or topic note under a dated `## Decisions` entry where possible.
9. If the inbox item describes a substantial development/work session, add or update a worklog/dev-log note using the vault's existing worklog convention and link it from today's daily note.
10. After successful consolidation, apply Safe Deletion to each processed inbox note:
    - move it to an existing processed/archive folder inside `99-inbox` if one exists, or
    - mark it with a processed note in place if no archive convention exists.
11. Update today's daily note at:
    `vault\02-worklog\YYYY-MM-DD.md`
    with links to notes created or updated.

Output:
- Inbox files processed.
- Notes created.
- Notes updated.
- Safety commits/stashes/backups made.
- Inbox notes archived or marked processed.
- Items skipped with reason.
