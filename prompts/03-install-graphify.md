# Install Graphify safely

Graphify is optional. Installation downloads a Python package; a graph build may consume model quota and writes generated output. Obtain approval separately for installation and for every build.

## Preconditions

- [ ] Work from the repository root and read the Graphify single-writer rule in `governance/vault.md`.
- [ ] Detect `python`, `pip`, `uv`, and `graphify` with `Get-Command`; do not install during detection.
- [ ] Confirm that only the lead may assign a build. Read-only `query`, `path`, and `explain` do not require the build lock.

## Installation checklist

1. [ ] If `graphify` is absent, show the exact installer command and obtain approval to download software.
2. [ ] Prefer `uv tool install graphifyy` when `uv` is available; otherwise use:

   ```powershell
   python -m pip install graphifyy
   ```

3. [ ] Verify without building:

   ```powershell
   graphify --help
   ```

## Build checklist

A concurrent pair of builds once destroyed a 710-node graph in the source system. This is why the protocol is mandatory, not advisory.

1. [ ] Require a task packet from the lead naming the repository, member, build mode, expected output, and allowed node-count change.
2. [ ] Resolve `.graphify-out.lock` at the repository root. Create it with an exclusive operation and record member, process id, UTC time, and task. If it already exists, abort immediately and report its contents; never wait, overwrite, or guess that it is stale.
3. [ ] Build in the default **undirected** mode. Directed analyses stay in scratch output and are never promoted to the live graph.
4. [ ] Build into a separate staging location, not over the live `graphify-out/`.
5. [ ] Validate that staged `graph.json` parses, contains nodes, and has no unexplained node-count drop. A drop requires explicit lead approval with old count, new count, and reason.
6. [ ] Promote the verified staged output by rename on the same volume. Preserve the previous live output as a recoverable backup until the new graph is accepted.
7. [ ] Release the lock in a `finally` path after success or failure. A stale lock may be cleared only after its process is confirmed dead and the lead approves; archive its contents first.

## Expected result

- `graphify --help` succeeds after installation.
- At most one writer can touch graph output.
- A failed build leaves the previous live graph intact.
- The promoted graph is undirected, parseable, non-empty, and node-count-reviewed.

## Failure handling

- On package-install failure, report the command, interpreter, and final error; do not retry with administrator rights unless the operator approves.
- On lock contention, abort and report the lock record. Do not poll.
- On empty output, invalid JSON, missing report, or unexpected shrink, keep staging and the previous live graph unchanged.

## Rollback

Rename the recoverable prior output back into place only after verifying both resolved paths. Send the rejected staged output to the Recycle Bin. Never permanently delete a graph or its lock record.
