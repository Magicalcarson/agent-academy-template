# Install the shared skills

Install the canonical generic skill store on the four supported CLI surfaces. Dry-run is mandatory; applying writes under `$HOME` and requires explicit operator approval.

## Preconditions

- [ ] Work from the repository root.
- [ ] Confirm `team-skills/skills-manifest.json` parses:

  ```powershell
  Get-Content -Raw .\team-skills\skills-manifest.json | ConvertFrom-Json | Out-Null
  ```

- [ ] Confirm the manifest represents 28 skill directories and the available surfaces are Claude Code, Codex, Kimi, and Antigravity.
- [ ] Read `team-skills/sync-skills.ps1` before executing it. Do not modify it during installation.

## Checklist

1. [ ] Run the default dry-run:

   ```powershell
   .\team-skills\sync-skills.ps1
   ```

2. [ ] Review every source, destination, operation mode, backup action, garbage-collection action, change count, and error.
3. [ ] Confirm Antigravity uses `mirror`, not a junction. Its loader skips reparse points.
4. [ ] Require `errors=0`, no destination outside `$HOME`, and no unexpected skill outside the manifest.
5. [ ] Explain to the operator that apply reconciles live CLI skill directories and may move replaced entries to the Recycle Bin. Obtain explicit approval.
6. [ ] Apply:

   ```powershell
   .\team-skills\sync-skills.ps1 -Apply
   ```

7. [ ] Rerun the dry-run. Require zero remaining changes and zero errors.

## Expected result

- All 28 generic skills are planned for their declared surfaces.
- Claude Code, Codex, and Kimi use the manifest-selected link or mirror mode.
- Antigravity has real mirrored directories.
- A second dry-run is clean and idempotent.

## Failure handling

- On a path-escape, malformed manifest, reparse-point, or reconcile error: stop. Do not change permissions or bypass the guard.
- If one CLI surface is absent, install only the surfaces explicitly supported by the script's `-Surface` filter and record the skipped surface.
- If a destination contains untracked operator work, do not apply. Preserve the dry-run output and ask the operator how to retain it.

## Rollback

Use the backup locations reported by the installer. Restore only the affected surface from its Recycle-Bin backup, then rerun dry-run. Never use recursive permanent deletion on a live skill directory.
