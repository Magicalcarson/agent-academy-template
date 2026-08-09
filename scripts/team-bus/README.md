# Team-bus transport seam

This folder provides the optional durable file-relay primitives used beneath the Academy packet contract. Messages move through same-volume staging, pending, inflight, archive, and quarantine states; publication and claim use atomic renames.

- `orchestrator-lock.ps1` owns the single-orchestrator lock and status record.
- `relay-lib.ps1` owns envelope validation and explicit message state transitions.
- There is no automatic pump or silent redispatch. An operator must reconcile abandoned inflight work.
- Agents never write relay state directly; the active orchestrator captures wrapper output and records it.

The default install uses direct wrappers. This directory is the documented seam for teams that later add a channel or durable relay transport.
