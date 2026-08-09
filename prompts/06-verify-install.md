# Verify the installation

Run this acceptance list from the repository root. Verification must not change live CLI skill surfaces, create junctions, invoke paid models, commit, push, deploy, or touch production data.

## Preconditions

- [ ] Record the repository root, PowerShell version, and current `git status --short`.
- [ ] Confirm no reparse point exists in the tracked release tree. Machine-local vault junctions must be removed or tested from a clean clone.
- [ ] Create scratch locations only under the system temporary directory and record their resolved paths.

## 1. Static gates

1. [ ] Parse every PowerShell file and require zero parser errors:

   ```powershell
   $parseErrors = @()
   Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
     $tokens = $null
     $errors = $null
     [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
     $parseErrors += $errors
   }
   if ($parseErrors.Count -gt 0) { $parseErrors; throw 'PowerShell parse failed.' }
   ```

2. [ ] If PSScriptAnalyzer is already installed, run `Invoke-ScriptAnalyzer -Path . -Recurse` and require zero warnings/errors. Installing it requires separate approval.
3. [ ] Run `Invoke-Pester -Path .\tests` and require every test green. Installing Pester requires separate approval.
4. [ ] Run the de-projection gate and require `Status = PASS`. Build the marker strings at runtime so the verification document does not contain the forbidden values it is testing for:

   ```powershell
   $deprojectionMarkers = @(
     ('apart' + 'mentery')
     ('จุฑา' + 'รัตน์')
     ('pok' + 'po')
     ('ai' + 'ri')
   )
   .\scripts\Invoke-PrivacyGate.ps1 -Root . -AdditionalForbiddenMarker $deprojectionMarkers
   ```

## 2. Clean-clone rehearsal

1. [ ] Clone the completed repository into a new temporary directory.
2. [ ] Run the initializer with `-DryRun -TrainerName "Test"`; require only `WouldCreate` or `Preserve` actions and no writes.
3. [ ] Run without `-DryRun`; require `Create` for missing local seeds.
4. [ ] Run a third time; require `Preserve` for every existing file and no content change.

## 3. Skills rehearsal

1. [ ] Set `$env:HOME` to a new temporary directory in the rehearsal process only.
2. [ ] Run `team-skills/sync-skills.ps1` in default dry-run mode. Require 26 manifest skills, four declared surfaces, a non-negative change count, and zero errors.
3. [ ] Do not run `-Apply` against the operator's live home. Apply only inside the isolated temporary home if the operator explicitly wants the full rehearsal.

## 4. Prompt walkthrough

- [ ] In a fresh CLI session against the clean clone, follow `prompts/00-bootstrap.md` through this file.
- [ ] Require every expected output to be observable. A step the CLI cannot follow without unstated knowledge fails acceptance.

## 5. Dispatch round trip

1. [ ] Use `scripts/new-task-packet.ps1` to create an inbox packet for an active member with a different active reviewer, acceptance criteria, and allowed mutations.
2. [ ] Confirm the packet appears under `inbox/<member-id>/` and contains the supplied contract.
3. [ ] Attempt the same command with maker equal to reviewer; require a non-zero failure and no packet.
4. [ ] If a zero-quota wrapper probe is available, confirm it starts from the explicit work directory and returns its exit status. Do not invoke a paid task.

## 6. Freshness and final result

- [ ] Rerun the privacy gate and require the release allowlist to match the tree exactly.
- [ ] Require no reparse point in the clean clone.
- [ ] Compare final `git status --short` with the recorded baseline; only expected local rehearsal files may differ.
- [ ] Report a table of `PASS`, `FAIL`, or `SKIPPED BY OPERATOR` for static gates, initializer, skills, prompts, dispatch, wrappers, hooks, Obsidian, and Graphify.

## Failure handling

Preserve complete failing output, identify the first failing gate, and continue only with independent checks. Never weaken a guard, edit the allowlist by hand to hide an extra file, or test against live provider quota to make a result look complete.

## Rollback

Close processes using scratch files, verify each resolved temporary path is inside the recorded temporary root, and send the scratch directory to the Recycle Bin. Restore installer backups for any external configuration changed during the rehearsal.
