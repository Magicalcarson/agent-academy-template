# Install the Obsidian vault

Create the local vault from the tracked scaffold. Obsidian and its community plugin are optional; junctions are machine-local and are created only after release validation.

## Preconditions

- [ ] Work from the repository root and resolve it with `$repoRoot = (Resolve-Path .).Path`.
- [ ] Confirm `templates/vault/hub.md` and exactly five files under `templates/vault/obsidian/` exist.
- [ ] Run the initializer if the scaffold has not yet been copied into `vault/`.
- [ ] Run `.\scripts\Invoke-PrivacyGate.ps1 -Root .` and require `Status = PASS` before creating any junction.

## Checklist

1. [ ] If Obsidian is absent, ask the operator whether to install it from its official distribution. Installing software requires approval.
2. [ ] Confirm the initializer copied scaffold content create-only and mapped `templates/vault/obsidian/` to `vault/.obsidian/`. Preserve any existing note or setting.
3. [ ] Open `vault/` as an Obsidian vault.
4. [ ] In Obsidian, ask the operator to enable Community plugins and install **Force Read Mode** from the Community plugins browser. Do not download or vendor its executable files into this repository.
5. [ ] Configure Force Read Mode for `00-governance/**` and `01-memory/**` after the junctions exist.
6. [ ] Ask the operator whether to create the governance junction. With approval, verify the source and target absolute paths, require that the target path is absent, then create it:

   ```powershell
   New-Item -ItemType Junction -Path (Join-Path $repoRoot 'vault\00-governance') -Target (Join-Path $repoRoot 'governance')
   ```

7. [ ] Ask the operator for the existing harness memory directory. Do not infer it. With approval, verify it is a directory and that `vault/01-memory` is absent, then create the junction:

   ```powershell
   New-Item -ItemType Junction -Path (Join-Path $repoRoot 'vault\01-memory') -Target '<operator-confirmed directory>'
   ```

8. [ ] In Obsidian, run **Reload app without saving** from the command palette, then confirm governance and memory notes appear in search and graph view.

## Expected result

- The live vault contains the hub, durable workspace folders, and five settings files.
- Force Read Mode protects the two mirrored paths in the UI.
- Junctions point only to the verified governance and memory sources.
- Tracked template content contains no reparse point or plugin executable.

## Failure handling

- If the privacy gate fails, do not create a junction. Fix the tracked release content first.
- If a junction target is missing, wrong, or already occupied, stop and report both resolved paths.
- If Obsidian does not refresh after an external edit, reload the app; its watcher does not reliably observe changes inside junction targets.
- If the plugin is unavailable, keep the mirrors read-only by policy and record that the UI soft guard is absent.

## Rollback

Close Obsidian. Before removing a junction, resolve and display both the junction and its target and verify the target remains intact. Send only the junction entry to the Recycle Bin; never recursively delete through it. Move only scaffold files created by this installation to the Recycle Bin, preserving pre-existing notes and settings.
