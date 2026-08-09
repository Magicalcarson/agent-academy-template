---
name: daily
description: Create or update today's daily note in the team vault
---

Execute `/daily`.

Vault root: `vault\`

Daily note path: `vault\02-worklog\YYYY-MM-DD.md`

Timezone: Asia/Bangkok. Resolve `YYYY-MM-DD` from the current date in Asia/Bangkok, not UTC.

Rules:
- Do not use Google Calendar integration.
- Do not permanently delete anything. Safe Deletion only: move obsolete material to an archive/trash location inside the vault, or leave it in place with a dated note explaining why it was superseded.
- IRON RULE for any code-touching action: before modifying code, scripts, configs, or command files, inspect the relevant files, preserve existing behavior unless explicitly changing it, make the smallest coherent change, and verify with the most relevant available check.
- Update existing notes by injecting or replacing clearly bounded sections. Never overwrite an entire note unless the file is newly created or the user explicitly approves.
- Preserve user-written content and unknown fields.
- Search before creating linked notes; duplicate notes are vault rot.
- Never invent facts, entities, dates, sources, or links. Use `TBD` or `unknown` when a value is missing.

Steps:
1. Compute today's Asia/Bangkok date and target path:
   `vault\02-worklog\YYYY-MM-DD.md`
2. If the daily note does not exist, create it with a practical daily structure:
   - YAML frontmatter with `type: daily`, `date: YYYY-MM-DD`, `tags: [daily, worklog]`, `timezone: Asia/Bangkok`
   - `# YYYY-MM-DD`
   - `## Focus`
   - `## Tasks`
   - `## Notes`
   - `## Decisions`
   - `## Links`
3. If the daily note exists, update it in place. Add missing standard sections only if absent.
4. Scan vault task boards or task notes if they exist. Include overdue and due-today tasks in `## Focus` or `## Tasks`, preserving source links.
5. Scan the current conversation for today's relevant work:
   - tasks in progress
   - decisions made
   - people/projects/concepts mentioned
   - files or notes touched
6. Add concise dated bullets to the appropriate sections. Preserve source context and inline links where available.
7. If prior automation/log notes exist for the previous night, summarize only confirmed changes in a short `## Overnight changes` section. Skip silently if none are found.
8. Return the exact daily note path and a short list of sections changed.

Output:
- Path of the daily note.
- Created vs updated.
- Sections changed.
- Any skipped items with reason.
