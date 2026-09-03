---
name: verification-loop
description: "Evidence-based verification for Codex code dispatches."
---

# Verification Loop (Agent Academy adaptation, rev 3)

Run after a team-shaped implementation/refactor slice, before handoff to Lead or any authorized commit/PR, or when a dispatch explicitly asks for a verification pass. Manual only - no timers, no hooks, no MCP, no scripts. This supplements, never replaces, Lead's independent check-before-use review.

## Governance guard (read first)

- Obey the nearest AGENTS.md and Agent Academy governance/ rules; they override this skill.
- IRON RULE: a FAIL stops the run immediately - report for re-dispatch, never silently fix solo. A BLOCKED phase does NOT stop the run: continue with the remaining independent phases and report all statuses.
- Tool preflight: before Phase 1, check each required tool (pnpm, rg, git; PSScriptAnalyzer/Pester optional) with Get-Command. A missing tool marks its phases BLOCKED - never install anything.
- Never access or print credential values; never mutate production; never run destructive scripts.
- "Changed files" throughout = union of: unstaged (git diff --name-only), staged (git diff --cached --name-only), and untracked (git ls-files --others --exclude-standard) - report the three counts separately.

## Phases

Mark each PASS / FAIL / N/A / BLOCKED / NOT RUN, with the exact command and evidence. BLOCKED = this phase's own tool/precondition is missing. NOT RUN = suppressed only because an earlier mandatory FAIL stopped the run.

1. **Build** - run the focused repository's declared build scripts for affected workspaces. No build script = N/A.
2. **Typecheck** - run its declared typecheck scripts for affected workspaces. No typed source/provider = N/A.
3. **Lint** - run its declared non-rewriting lint scripts. For changed PowerShell, parse each `.ps1`; run PSScriptAnalyzer/Pester only if locally available. Never execute side-effectful scripts without an approved fixture or documented dry-run/WhatIf mode.
4. **Tests** - run the repository's declared tests wherever test files exist. No test files = N/A. Coverage is assessed separately and is N/A when no coverage provider is configured; never invent a threshold.
5. **Secrets heuristic** - rg -l --hidden -g '!node_modules/**' -g '!.git/**' -g '*.{ts,tsx,js,jsx,ps1,json,yaml,yml,toml}' -g '.env*' -e '(?i)(sk-[a-z0-9_-]+|api[_-]?key\s*[:=])' . - report file paths and counts ONLY; never print matched values.
6. **Diff review** - capture the complete Git name arrays in-process, but emit only the bounded summary below. Populate `$allowedPaths` with the packet's exact repository-relative mutation paths before running it; an empty allowlist fails safe by reporting every changed path as unexpected.

   ```powershell
   $sampleLimit = 20
   $pathCharacterLimit = 160
   $allowedPaths = @(
       # 'exact/repository-relative/path-from-packet'
   )

   function Normalize-RepoPath([string]$Path) {
       $normalized = $Path.Replace('\', '/')
       if ($normalized.StartsWith('./', [StringComparison]::Ordinal)) {
           return $normalized.Substring(2)
       }
       return $normalized
   }

   function Limit-DisplayPath([string]$Path) {
       if ($Path.Length -le $pathCharacterLimit) { return $Path }
       return $Path.Substring(0, $pathCharacterLimit - 3) + '...'
   }

   $porcelain = @(git status --porcelain=v1 --untracked-files=all)
   $trackedStatus = @($porcelain | Where-Object {
       $_.Length -ge 2 -and $_.Substring(0, 2) -ne '??'
   })
   $untrackedStatus = @($porcelain | Where-Object {
       $_.Length -ge 2 -and $_.Substring(0, 2) -eq '??'
   })
   $trackedNames = @(
       git diff --name-only
       git diff --cached --name-only
   ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
       ForEach-Object { Normalize-RepoPath $_ } | Sort-Object -Unique
   $untrackedNames = @(git ls-files --others --exclude-standard) |
       Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
       ForEach-Object { Normalize-RepoPath $_ } | Sort-Object -Unique
   $normalizedAllowedPaths = @($allowedPaths |
       ForEach-Object { Normalize-RepoPath $_ } | Sort-Object -Unique)
   $allChangedNames = @($trackedNames + $untrackedNames | Sort-Object -Unique)
   $unexpectedNames = @($allChangedNames | Where-Object {
       $normalizedAllowedPaths -notcontains $_
   })

   [pscustomobject][ordered]@{
       trackedChangeCount = $trackedStatus.Count
       untrackedCount = $untrackedStatus.Count
       trackedSample = @($trackedNames | Select-Object -First $sampleLimit |
           ForEach-Object { Limit-DisplayPath $_ })
       untrackedSample = @($untrackedNames | Select-Object -First $sampleLimit |
           ForEach-Object { Limit-DisplayPath $_ })
       trackedTruncated = $trackedNames.Count -gt $sampleLimit
       untrackedTruncated = $untrackedNames.Count -gt $sampleLimit
       unexpectedCount = $unexpectedNames.Count
       unexpectedPaths = @($unexpectedNames | Select-Object -First $sampleLimit |
           ForEach-Object { Limit-DisplayPath $_ })
   } | ConvertTo-Json -Depth 3 -Compress
   ```

   Use literal two-character status-prefix classification as shown; never use wildcard matching for `??`. Any `unexpectedCount` above zero fails Diff review. If more than 20 unexpected paths exist, inspect them in bounded directory slices instead of printing the full array. Then run explicitly: git diff --check; git diff --cached --check; git diff --stat; git diff --cached --stat; and exact `git diff -- <authorized-path>` / `git diff --cached -- <authorized-path>` commands for every authorized file. Look for unintended changes, missing error handling, and edge cases.

## Report format

```
VERIFICATION REPORT
Build:    PASS|FAIL|N/A|BLOCKED  <command + evidence>
Types:    ...
Lint:     ...
Tests:    ...  (coverage reported separately or N/A)
Secrets:  ...  (paths/counts only)
Diff:     PASS|FAIL  <commands run; X unstaged / Y staged / Z untracked + evidence>
Overall:  READY FOR DIRECTOR REVIEW | NOT READY
          (any required phase BLOCKED or FAIL => NOT READY; say which and why)
Risks / notes: ...
```

Reply in the dispatch's working language (English within the team). If the run changed files or produced a deliverable, end with the standard WORKLOG: line.
