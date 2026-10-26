# Canonical asset recovery and diagnostics

Storage retirement completed on 2026-10-18: canonical public/private R2 owns the
files and fonts; old Storage/imgproxy and redundant buckets are retired. See
[current asset authority](../../docs/operations/supabase-self-hosted/storage-authority.md)
and the linked execution receipt. These tools do not enable another migration.

Retained supported boundaries:

- `storage_references.py` is the structural HTML/CSS/JSON reference parser used
  by current backup/recovery and its release provenance. Keep its implementation
  and tests intact; missing parser input must fail closed.
- `map_dependencies.py` audits exact style/sprite/glyph dependencies; a map style
  alone is not a complete offline bundle.
- `collect-inventory.py`, `inventory-r2.py`, `build-manifest.py`, `copy-assets.mjs`
  and their verified-copy/remote transport helpers preserve private inventories,
  immutable manifests, byte verification and sealed copy receipts. They remain
  tested for separately authorized recovery or asset repair. They are not routine
  deployment steps and copying never grants deletion authority.
- The prepare/render/apply-cutover and approved-reference-cleanup tools retain
  their pinned prestates, atomic typed-client-commit behavior and PG17 regression
  tests. They require their original reviewed inputs and separate operational
  authorization; no replay is performed by this source cleanup.
- `find-orphans.js` remains a read-only diagnostic with its public private-input
  schema, connection/R2 helpers and smoke tests. Its informational result never
  authorizes object deletion or proves complete reference closure.

Install supported JavaScript dependencies with pnpm 11.24.0:

```sh
pnpm --dir automation/image-migration install --frozen-lockfile
```

Protected values stay outside tracked files. Read current tenant activation and
backend identity through the backend-access procedure before any authorized live
operation. Keep inventories, receipts, object bytes and credentials private; do
not recapture historical expectations from current runtime output.

The older `migrate-files.js`, `rewrite-urls.js`, `verify.js`, private-bucket bulk
cutover, obsolete URL/HTML/Storage helpers and their unused dependencies were
removed. No package command points to a retired writer. Historical commands and
source are recoverable from the [cleanup record](../../docs/archive/repository-tooling-cleanup-2026-10-21.md).
The retired rewrite identity stays in the canonical-mutation retirement inventory
as a tombstone, not an executable compatibility path.
