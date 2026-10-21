# Runtime policy and retained source provenance

The directory name is historical. Current canonical backend operations use these
retained boundaries:

- `runtime-writer-policy.json` classifies live Function/Worker entrypoints and
  their canonical security requirements; `runtime-writer-policy.mjs` checks them.
- `edge-function-test-coverage.mjs` validates executable production Function test
  mappings and remains a required automation gate.
- `source-registry.json` and `reference-registry.json` are installed runtime and
  recovery provenance. Their bytes and release-manifest identities remain intact.
- `client-adapter-audit.mjs` keeps the exact local typed-RPC/canonical-only adapter
  audit formerly embedded in the cloud hybrid report. It performs no remote I/O.
  `write-authority-policy.json` retains its original nine adapter declarations.
- `write-authority-inventory.mjs` retains local writer discovery/classification and
  all privacy/no-overwrite evidence safeguards. Discovery is conservative static
  evidence and does not authorize live migration or source writes.
- `lib.mjs` retains registry validation, repository root, private-output fencing
  and deterministic hashing. It no longer reads credentials or calls a cloud API.

The completed cloud inventory/export, collision/identity merge, freeze/rollback,
source staging, tenant-cohort and repository cutover commands were removed.
Recover their original source and inputs together only for a separately scoped
historical replay. See the [cleanup record](../../../docs/archive/cloud-merge-tooling-cleanup-2026-10-21.md).
No current tenant setup, release or recovery requires restoring deleted commands.
