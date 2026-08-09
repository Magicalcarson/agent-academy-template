# Install the portable worklog hook

The SessionStart worklog guard injects the latest bounded worklog tail and reminds the lead to log continuously. Installing it writes under `$HOME` and may update an existing harness configuration, so preview and approval are mandatory.

## Preconditions

- [ ] Work from the repository root.
- [ ] Confirm `vault/02-worklog/` exists.
- [ ] Read `governance/workflow.md` section 7.
- [ ] Inspect `scripts/Install-Hooks.ps1` and its portable hook source before execution.
- [ ] Confirm the hook derives `vault/02-worklog` from the repository root and contains no user-home literal.

## Checklist

1. [ ] Detect supported installed harnesses without reading their authentication files.
2. [ ] Preview:

   ```powershell
   .\scripts\Install-Hooks.ps1 -DryRun
   ```

3. [ ] Show every destination and whether it will be created, preserved, or backed up. The hook must be registered for SessionStart only.
4. [ ] Explain that apply writes under `$HOME` and may update a harness settings file. Obtain explicit operator approval.
5. [ ] Apply:

   ```powershell
   .\scripts\Install-Hooks.ps1 -Apply
   ```

6. [ ] Start a fresh supported CLI session from this repository. Confirm the hook shows only a bounded tail of the latest worklog and the current logging reminder, then exits successfully.
7. [ ] Start from a different working directory and confirm the installed repository-root reference still resolves correctly.

## Expected result

- The hook is registered exactly once for SessionStart.
- It resolves the Academy worklog without a machine-specific source path.
- Missing worklog files produce a harmless message; the hook never blocks session startup.
- Output is bounded and contains no credential or unrelated private file.

## Failure handling

- If the installer cannot preserve an existing hook array or settings document, do not apply.
- If configuration parsing fails, restore the backup immediately and report the parse error.
- If the hook blocks startup, disable its registration using the recorded backup and keep the hook file for diagnosis.

## Rollback

Use the installer's recorded backup to restore the prior harness settings. Move only the newly installed hook file to the Recycle Bin after confirming it is no longer referenced. Do not remove other hooks.
