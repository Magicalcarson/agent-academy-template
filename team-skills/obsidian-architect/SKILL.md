---
name: obsidian-architect
description: Scan a codebase and maintain a bounded architecture note in the team vault without clobbering Trainer edits
---

Execute `/obsidian-architect <codebase root path>`.

This command turns a software project into a refreshable architecture note for the team vault. It reads code as code work, synthesizes grounded architecture documentation, and updates only bounded generated sections so Trainer edits survive refreshes.

## Required Argument

- `<codebase root path>` is required.
- Resolve it to an absolute path.
- Confirm it exists and is a directory.
- If the argument is missing, stop and ask for it. Do not infer silently.

## Vault Target

- Vault root: `vault\`
- Output directory: `vault\05-architect\`
- Output note: `vault\05-architect\<repo-name>.md`
- Derive `<repo-name>` from the codebase root directory name. Sanitize only characters invalid for Windows filenames.
- Timezone for all timestamps and daily references: `Asia/Bangkok`.

## Safety Rules

1. Read `governance\vault.md` before planning writes, and follow it.
2. Junction safety: never write into `vault\00-governance\` or `vault\01-memory\`.
3. Safe Deletion: never permanently delete files, notes, sections, or user content.
4. If the architect note already exists, update bounded generated sections only.
5. Never overwrite text outside generated markers.
6. Never modify `@user` sections.
7. If a needed section is missing, append a new bounded generated section rather than replacing the whole note.
8. If an existing note has no markers, preserve all existing content and append generated sections below it.
9. Do not write scan artifacts into the vault unless explicitly requested.

## Team Rule

IRON RULE: code reading IS code work.

- Count source files before scanning deeply.
- If the codebase has more than 100 files, Academy Lead must split the code scan between Academy Deputy and Academy Analyst.
- The split must be explicit: assign distinct directories, modules, or file categories to each.
- Merge findings only after checking both outputs against actual files.
- Do not let one agent summarize the entire large codebase alone.

## Scan Procedure

1. Identify project shape from real files only:
   - primary languages and file counts
   - package/build manifests
   - entry points
   - top-level modules/directories
   - runtime services, scripts, CI, Docker, deployment files
   - important dependencies and internal imports
   - tests and quality gates
   - git branch and current commit, if available
2. Prefer deterministic commands and structured parsers when available.
3. Never follow generated output, vendor caches, dependency directories, build directories, or binary blobs as architecture evidence unless they are the only deployment artifact and are directly relevant.
4. Treat code comments, README files, manifests, tests, and configuration as evidence, but rank executable code and manifests highest.
5. Mine recent commit messages only as weak evidence for key decisions. Mark inferred decisions as speculation.

## Anti-Fabrication Rule

Describe only what the scan and source files actually show.

- Do not invent modules, dependencies, data flows, users, roadmap, rationale, or decisions.
- If evidence is thin, say so and keep the note short.
- Mark inferred rationale, personas, and design intent as `confidence: speculation`.
- Preserve concrete source paths for claims.

## Note Format

Create or refresh one Markdown note at `vault\05-architect\<repo-name>.md`.

Use this structure:

```markdown
---
type: architecture
repo: <repo-name>
codebase: <absolute codebase root path>
scanned-at: <YYYY-MM-DD HH:mm Asia/Bangkok>
scanned-commit: <git commit or unknown>
tags:
  - architecture
  - codebase
ai-first: true
---

## For future Claude

<!-- @generated:summary:start -->
Short retrieval-first summary of what this codebase is and how to use this note.
<!-- @generated:summary:end -->

## Trainer Notes

<!-- @user:notes:start -->
<!-- Trainer-owned space. Do not edit inside this block. -->
<!-- @user:notes:end -->

## Overview

<!-- @generated:overview:start -->
Grounded project overview.
<!-- @generated:overview:end -->

## Architecture Map

<!-- @generated:diagram:start -->
One Mermaid diagram showing real modules and main flow.
<!-- @generated:diagram:end -->

## Modules

<!-- @generated:modules:start -->
Table or bullets for core modules, support modules, responsibilities, dependencies, and source paths.
<!-- @generated:modules:end -->

## Entry Points and Workflows

<!-- @generated:entrypoints:start -->
Executable entry points, request/job/data flows, CLI commands, services, and tests.
<!-- @generated:entrypoints:end -->

## Dependencies and Integrations

<!-- @generated:dependencies:start -->
Runtime dependencies, external services, storage, APIs, and config-backed integrations.
<!-- @generated:dependencies:end -->

## Key Decisions

<!-- @generated:decisions:start -->
Grounded decisions from source, manifests, docs, or commit messages. Mark weak inference.
<!-- @generated:decisions:end -->

## Refresh Log

<!-- @generated:refresh-log:start -->
- <YYYY-MM-DD HH:mm Asia/Bangkok> - Initial scan or refresh summary.
<!-- @generated:refresh-log:end -->
```

## Refresh Behavior

When the note exists:

1. Re-scan the codebase.
2. Compare new facts to current generated sections.
3. Replace only text between matching `<!-- @generated:<name>:start -->` and `<!-- @generated:<name>:end -->` markers.
4. Leave all other content byte-for-byte intact where possible.
5. Preserve `<!-- @user:* -->` blocks completely.
6. Update `scanned-at`, `scanned-commit`, and the generated refresh log.
7. Report exactly which generated sections changed.

When the note does not exist:

1. Create it under `vault\05-architect\`.
2. Include the `Trainer Notes` user block from the template.
3. Include all generated markers so future refreshes are bounded.

## Output Requirements

- The note must be useful for future retrieval, not decorative reading.
- Include concrete source paths for important claims.
- Include one Mermaid diagram if the module relationships are clear enough; otherwise state that the evidence is insufficient.
- Use `[[wikilinks]]` where they match established vault entities, but do not invent entities.
- Include confidence labels where claims are inferred.
- Finish by reporting:
  - codebase scanned
  - output note path
  - source file count
  - whether Academy Deputy and Academy Analyst split the scan
  - generated sections created or refreshed
  - any safety blocks encountered
