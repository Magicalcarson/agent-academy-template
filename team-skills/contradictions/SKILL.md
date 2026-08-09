---
name: contradictions
description: Scan vault for contradictions and generate a report in the inbox without auto-editing
---

Execute `/contradictions [scope path]`.

Vault root: `vault\`

Required/Optional argument: optional `[scope path]` to limit the scan; defaults to the entire vault root if not provided.

Rules:
- **REPORT-ONLY Mode:** Do NOT automatically edit, rewrite, or reconcile any notes. Only discover and report contradictions.
- **Junction safety:**
  - `00-governance\` and `01-memory\` are NTFS junctions and read-only.
  - NEVER attempt to write to or modify files in `00-governance\` or `01-memory\`.
  - Reading from `00-governance\` and `01-memory\` is permitted for contradiction scanning.
- **Safe Deletion / Append-Only Report:**
  - Save the report file at: `vault\99-inbox\contradictions-YYYY-MM-DD.md` (date resolved in Asia/Bangkok timezone).
  - Do NOT overwrite the report file if it already exists. Instead, append a new `## Run @ HH:MM` section to the existing file.
- **IRON RULE Flagging:**
  - If a contradiction is detected that touches or conflicts with code-relevant rules in `00-governance\`, flag it explicitly in the report for the Trainer to review.

Steps:
1. Resolve the date and time in the Asia/Bangkok timezone to determine:
   - Report filename: `vault\99-inbox\contradictions-YYYY-MM-DD.md`
   - Run section header: `## Run @ HH:MM`
2. Determine scan scopes:
   - Check if an optional `[scope path]` was provided. If so, limit the scan to that subdirectory (within the safety guidelines).
   - Scan 1 (Governance vs Memory): Scan `vault\01-memory\` for contradictions against `vault\00-governance\` rules.
   - Scan 2 (Projects vs Architect): Scan `vault\03-projects\` and `vault\05-architect\` for contradictions among themselves.
3. Compare claims, rules, and facts:
   - Identify pairs of notes containing conflicting claims, outdated information, or mismatched facts (e.g., `<claim A in note X>` vs `<claim B in note Y>`).
4. Generate resolution recommendations (do NOT apply them):
   - For each conflict, suggest a resolution based on source freshness (newest date) or authority.
   - Assign the person who must decide the resolution (e.g., "Trainer", "Developer", "Academy Lead", or "Academy Analyst").
5. Create or update the report:
   - If `vault\99-inbox\contradictions-YYYY-MM-DD.md` does not exist, create it with frontmatter (`type: report`, `category: maintenance`) and a main heading.
   - Append the `## Run @ HH:MM` section followed by the list of identified contradiction pairs:
     - Conflict details: `<claim A in note X> vs <claim B in note Y>`
     - Suggested resolution
     - Who must decide
     - Flags (e.g., "Trainer Flag" if touching code-relevant rules).
6. Return the path of the report file and a summary of contradictions found.

Output:
- Path of the report file.
- Number of contradictions found.
- Summary of flags raised.
