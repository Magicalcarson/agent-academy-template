# Publishing Agent Academy safely

This working directory is a release source, not the public repository itself. Publish only a verified snapshot under a neutral repository name such as `agent-academy-template`.

## Why clean history is required

Git history can retain deleted names, private records, paths, and earlier drafts. A clean working tree does not prove that its history is safe. Do not push this preparation repository, a private Academy installation, or either repository's existing `.git` directory to the public remote.

Create a new empty directory and repository from the allowlisted snapshot only. Confirm that the destination is empty before copying anything into it. Never include credentials, local provider configuration, private vault content, inbox/outbox records, worklogs, project state, or machine-specific files.

## Release gate

Complete every item before making the destination repository public:

1. Run `scripts/Invoke-PrivacyGate.ps1` against this template root and require a passing result.
2. Run the full Pester suite under `tests/` and require every test to pass.
3. Confirm exact parity between `manifests/release-allowlist.txt` and the files copied to the clean destination.
4. Search the snapshot and its filenames for private identities, credentials, internal hostnames, IP addresses, personal paths, prior-project names, and retired theme or character names.
5. Verify `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and every referenced third-party license file are present.
6. Parse every JSON file and PowerShell script; run PSScriptAnalyzer when available.
7. Open every relative documentation link and confirm its target exists in the destination.
8. Inspect the clean repository's staged diff and commit history before the first push. It should contain one intentional public baseline commit and no inherited history.
9. Obtain a human review of the final public snapshot. For commercial distribution or uncertain third-party material, obtain qualified legal advice.

## Publication boundaries

- The public project is the neutral **Agent Academy** template.
- The operator's private Academy installation is separate and is not a publication source.
- The author credit is **Pokpong Sittisak**.
- The root MIT License covers original Agent Academy material only.
- Bundled or adapted third-party skills remain under their upstream licenses and notices.
- Provider and product names identify compatibility only and do not imply affiliation or endorsement.

Publication is an external write. Preview the exact remote owner, repository name, visibility, and staged file list before creating the remote or pushing.
