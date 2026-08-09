# Installation guide

> Agent Academy was created and developed by **Pokpong Sittisak** and is distributed under the [MIT License](LICENSE).

This guide is the human-readable companion to `prompts/00-bootstrap.md`. Run commands from the repository root in PowerShell unless a step says otherwise.

## Preconditions

- Windows PowerShell 5.1 or PowerShell 7+
- Git
- at least one supported AI CLI already installed and authenticated through its own secure configuration
- optional: Obsidian for the vault, Python and `pip` or `uv` for Graphify

Do not paste credentials into `providers.json`, a prompt, a task packet, or this repository. Installing software, writing under `$HOME`, and any paid provider call require the operator's explicit approval.

## 1. Initialize local state

Preview first:

```powershell
.\scripts\Initialize-AgentAcademy.ps1 -DryRun -TrainerName "Your display name"
```

Review every `WouldCreate` action, then rerun without `-DryRun`. The initializer creates only missing local files and preserves existing content. A later run is safe and should report `Preserve`.

Rollback: move newly created local files to the Recycle Bin. Never permanently delete them. Existing files were not replaced.

## 2. Install team skills

```powershell
.\team-skills\sync-skills.ps1
```

Dry-run is the default. Review the destination plan, then approve the external writes and run:

```powershell
.\team-skills\sync-skills.ps1 -Apply
```

The installer reconciles Claude Code, Codex, Antigravity, and Gemini-compatible surfaces. Antigravity receives mirrored directories because its loader does not discover reparse points. Rollback uses the installer's Recycle-Bin backups; do not delete live skill directories manually.

## 3. Install the Obsidian vault

Install Obsidian from its official distribution if needed. Scaffold `vault/` from `templates/vault/`, copying `templates/vault/obsidian/` into `vault/.obsidian/`. Install **Force Read Mode** from Obsidian's Community plugins browser; its executable plugin files are deliberately not bundled here.

Run the privacy gate before creating the optional `00-governance/` and `01-memory/` junctions, because release validation rejects reparse points. The detailed sequence and reload caveat are in `prompts/02-install-obsidian-vault.md`.

## 4. Install Graphify

With approval to download a Python package:

```powershell
python -m pip install graphifyy
graphify --help
```

Graph builds are lead-assigned, single-writer operations. Read `governance/vault.md` and `prompts/03-install-graphify.md` before the first build.

## 5. Configure providers and wrappers

Copy `templates/providers.example.json` to the untracked local file `providers.json`, then set executable names or paths for installed CLIs. Do not add authentication fields.

```powershell
.\scripts\Install-Wrappers.ps1 -DryRun
.\scripts\Install-Wrappers.ps1 -Apply
```

Generated wrappers accept `-Task` and an explicit `-WorkDir`. Credentials remain owned by each CLI.

## 6. Install hooks

Preview the portable worklog guard, approve the write under `$HOME`, then apply it:

```powershell
.\scripts\Install-Hooks.ps1 -DryRun
.\scripts\Install-Hooks.ps1 -Apply
```

The hook resolves the worklog from the repository root; it does not embed a machine-specific path.

## 7. Verify

Follow `prompts/06-verify-install.md`. A complete install has passing PowerShell parse checks, tests, privacy gate, initializer idempotence, skill dry-run, and a maker/reviewer packet round trip.

Nothing in installation commits, pushes, deploys, or changes production data.
