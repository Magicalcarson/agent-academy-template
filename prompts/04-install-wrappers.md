# Configure providers and install wrappers

Wrappers are the default Tier 1 transport. They start one CLI process per dispatch and preserve packets and replies as files. They do not store authentication.

## Preconditions

- [ ] Work from the repository root.
- [ ] Confirm `governance/roster.json` and `templates/providers.example.json` parse as JSON.
- [ ] Confirm every roster `transport` key exists under `providers` in the example.
- [ ] Detect available CLIs with `Get-Command`; do not invoke a provider during detection.

## Checklist

1. [ ] If `providers.json` is absent, copy the example. If it exists, preserve it:

   ```powershell
   if (-not (Test-Path .\providers.json)) { Copy-Item .\templates\providers.example.json .\providers.json }
   ```

2. [ ] Ask the operator which installed executable serves each transport. Edit only `executable`, `arguments`, and `closeStdin` in `providers.json`.
3. [ ] Never add credential-bearing fields. Authentication stays in the CLI's own secure configuration and is completed by the operator outside this session.
4. [ ] Verify each configured executable with `Get-Command`; a missing transport means its member is not dispatchable yet.
5. [ ] Preview wrapper generation:

   ```powershell
   .\scripts\Install-Wrappers.ps1 -DryRun
   ```

6. [ ] Require create-or-preserve actions only. Obtain approval, then apply:

   ```powershell
   .\scripts\Install-Wrappers.ps1 -Apply
   ```

7. [ ] Inspect generated wrappers. Each must accept `-Task` and mandatory `-WorkDir`, enter the resolved work directory, restore the prior location, and invoke only its configured executable and arguments. A provider with `closeStdin: true` must receive closed/null standard input so non-TTY Codex execution cannot hang.
8. [ ] Use a version/help invocation or other zero-quota command to verify process launch. Do not spend provider quota without separate approval.

## Expected result

- One minimal wrapper exists per configured roster transport.
- The wrapper uses the explicit work directory and returns stdout, stderr, and exit status faithfully.
- Codex-style non-TTY execution cannot wait for additional standard input.
- No provider secret exists in the repository.

## Failure handling

- If JSON is malformed, a transport key is missing, or an executable does not resolve, do not generate that wrapper.
- If dry-run proposes replacing an existing wrapper, preserve it and ask the operator whether to reconcile the custom behavior.
- If a zero-quota launch fails, report the exact executable, arguments, work directory, and exit code without exposing environment values.

## Rollback

Move only wrappers created by this installer to the Recycle Bin. Restore any installer-recorded backup for a pre-existing wrapper. Preserve `providers.json` unless the operator confirms it was newly created and is no longer wanted.
