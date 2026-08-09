---
name: synthesis
description: Perform light synthesis for one specified team-vault MOC
---

Execute `/synthesis <MOC path>`.

Vault root: `vault\`

Required argument: path to one existing MOC markdown file inside the vault.

Rules:
- Light synthesis only. Do not scan the entire vault and do not run broad autonomous synthesis.
- Work on exactly one MOC at a time: the MOC passed as the required argument.
- Do not permanently delete anything. Safe Deletion only: move obsolete material to an archive/trash location inside the vault, or leave it in place with a dated note explaining why it was superseded.
- IRON RULE for any code-touching action: before modifying code, scripts, configs, or command files, inspect the relevant files, preserve existing behavior unless explicitly changing it, make the smallest coherent change, and verify with the most relevant available check.
- Never invent facts, entities, dates, sources, or links. Use `TBD` or `unknown` when a value is missing.
- Preserve source links and uncertainty.
- Keep changes bounded and reviewable.

Steps:
1. Validate the `<MOC path>` argument:
   - it must resolve inside `vault\`
   - it must exist
   - it must be a markdown file
2. Read the MOC and only the notes directly linked from that MOC unless a linked note explicitly points to one immediately necessary supporting note.
3. Identify light synthesis opportunities:
   - repeated themes across linked notes
   - unresolved tensions or contradictions
   - decisions implied by multiple notes
   - missing bridge links between already-linked notes
   - small candidate next actions
4. Do not create a separate synthesis note unless the MOC's existing convention clearly uses separate synthesis notes. Prefer updating the MOC with a bounded section:
   `## Light synthesis`
5. Write concise bullets with:
   - pattern observed
   - linked source notes
   - confidence level
   - suggested next action, if any
6. Add missing links between directly relevant notes only when strongly supported by existing content.
7. Update today's daily note at:
   `vault\02-worklog\YYYY-MM-DD.md`
   with a short link to the MOC and summary of synthesis performed.
8. Report what changed and what was skipped.

Output:
- MOC path.
- Linked notes reviewed.
- MOC sections updated.
- Links added.
- Daily note update.
- Skipped candidates with reason.
