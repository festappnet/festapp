# Canonical Storage retirement

The authoritative scope is [the retirement plan](../../docs/plans/storage-r2-retirement-plan-2026-10-18.md).
The additive copy inventory is prepared; reference completeness remains blocked.
No production copy, rewrite,
Worker rollout, service retirement or bucket deletion has occurred.

Map styles are assets with dependencies, not standalone JSON files. Retain the
map package, style, sprite indexes/atlases and any consumed glyph assets. Existing
R2 map/sync artifacts keep their URLs. Before reusing a retained sprite bundle,
audit its exact manifest and downloaded files:

```sh
python3 automation/image-migration/map_dependencies.py \
  --style "$asset_evidence/source-style.json" \
  --sprite-manifest "$asset_evidence/retained-map-manifest.json" \
  --bundle-directory "$asset_evidence/verified-map-bundle" \
  --output "$asset_evidence/map-sprite-audit.json"
```

The audit checks all four sprite hashes/lengths, atlas geometry and icon outputs
from supported style expressions. It fails on missing symbols and dynamic
expressions requiring a tile audit. It does not fetch URLs, alter a style, infer
ownership or prove full offline closure. Pin the receipt to the source style hash;
do not silently substitute a different symbol. A passed sprite audit does not
replace package/style/glyph verification or the migration/restore gates.

Use the current inventory and conditional-copy tools, with evidence outside Git:

```sh
umask 077
asset_evidence="$HOME/.local/share/festapp-storage-retirement-20261018"
python3 automation/image-migration/collect-inventory.py --output "$asset_evidence/new-capture"
ssh festapp-backend-agent 'python3 -' < automation/image-migration/inventory-r2.py > "$asset_evidence/new-r2.json"
python3 automation/image-migration/build-manifest.py \
  --capture "$asset_evidence/new-capture" --r2-inventory "$asset_evidence/new-r2.json" \
  --retain-ownerless --retain-orphan-bytes \
  --output "$asset_evidence/new-manifest"
node automation/image-migration/copy-assets.mjs --manifest "$asset_evidence/new-manifest/manifest.json" --validate
```

Verify tenant activation and backend identity through the project backend-access
skill first. Captures contain customer rows and exact prestates; keep them private.
The collector uses a repeatable-read, read-only catalog-driven snapshot of all
`public` and `eshop` relations, classifies other schemas explicitly, and hashes
every local file. Generated search documents belong to their source fields.
They are not independent source locators or writable fields. Retained histories,
unassigned ownership, orphan files, unresolved identities and schema surprises
remain visible blockers. None is silently dropped or exempted as historical loss.

`--retain-ownerless` preserves an explicitly null original owner under service
custody. It assigns no human owner and grants no application write access. It
requires the captured RLS/role/policy boundary to match the audited closed
private-client contract; unexpected policies still block it. Original ownership
records remain verbatim in the manifest. `--retain-orphan-bytes` retains every
unregistered disk file in private R2 custody, with exact source path/hash and no
application reference. It neither discards those files nor asserts a public
read or a user owner. Both options are explicit; their default is fail-closed.

Copy readiness and reference-rewrite readiness are separate. A missing reference
blocks its rewrite and final retirement, while independently resolved source
objects can be copied additively. The copy tool never deletes a source.

The R2 collector uses the existing protected read-only source credential. It
streams every object through SHA-256, preserves metadata and checks that the
listing did not change. These DB/disk/R2 captures are separate online points.
Refresh them before any final rewrite; they are not an atomic snapshot.

After all source-copy blockers are resolved and code is reviewed on clean canonical
main, `copy-assets.mjs` accepts `--manifest`, `--r2-inventory`, `--r2-config` and
`--receipts`. The mode-0600 R2 config has `endpoint`, `accessKeyId` and
`secretAccessKey`; provision the required read/write bucket permissions through
the existing protected stores. Do not use or export a Supabase service-role key.
The driver rejects a dirty source or any commit differing from `origin/main`,
and a mismatched R2 inventory digest. A detached worktree at that exact reviewed
main commit is supported. Fetch main immediately before preparing that worktree.
It uses conditional S3 creates, exact length/MIME/SHA-256 checks, bounded SSH
streams for Storage, separate destination reads and atomic immutable receipts.
An existing conflicting object is an error. A missing receipt can be resumed
by rechecking the destination. No source deletion is implemented by this tool.
Unit tests simulate the object-store boundary; real provider copy remains unrun.

The alternative `--wrangler-remote` uses the existing authenticated Wrangler
connection instead of `--r2-config`. Run with Node 22 and the pinned installed
Wrangler dependency. Its fixed `wrangler.copy.json` connects only the four
inventoried buckets; the adapter permits writes only to the canonical pair.
No application Worker or route is deployed. R2 `onlyIf` enforces atomic
create-if-absent, with the same independent hash/MIME verification and receipts.
One object at a time is bounded to 64 MiB on the workstation; source hashing
still streams from the backend. Larger objects fail before a destination write.
The platform connection is disposed when the copy finishes or fails.

`prepare-cutover.py --manifest ... --receipts ... --output ...` verifies every
copy receipt against the exact manifest and R2 inventory, and prepares private
registry records plus exact before/after reference values. It rejects missing,
conflicting or mixed-source receipts, unresolved references and private URLs
without a reviewed permission boundary. This creates no SQL transaction and
performs no database mutation; atomic synchronization remains a separate gate.

Account cleanup now has staged canonical SQL sources and a forward migration:
`node automation/generate_storage_asset_migration.mjs --check` verifies assembly.
Its registry preserves the exact original user-owner binding independently of
Auth row deletion. SQL prepares a durable per-request queue and only completes
the account after all owned objects have been acknowledged. R2 deletion checks
the immutable key/SHA and purges public caches before acknowledgement; a failed
response or acknowledgement can be retried. Acknowledged registry tombstones
remove the original owner/key record. Unassigned files are not assigned to the
deleting user. Fonts, AKH and other buckets are outside this deletion capability.

The dedicated `ASSET_CLEANUP_SERVICE_SECRET` is restricted to the confirmation
Edge worker and the matching service route. Do not provision it as a user JWT,
font capability or Supabase service-role credential. The SQL cutover flag starts
inactive: verified registry import, complete producer/delta gates and coordinated
Worker/SQL/Edge activation are required before enabling this path. The registry
import and activation have not executed; a passed isolated SQL lifecycle test is
not evidence of a live R2 delete or completed cutover.

The prepared Worker maps historical `a` identities to `imports/a/` in the
canonical bucket pair. Default and AKH keys retain their existing identities;
AKH keeps its own bucket/Auth/SQL permissions. Deploy this binding change only
after the complete source transfer and final producer/delta gates. Do not
activate it against an incompletely copied bucket. This is not the P3 delivery
or custom-domain cutover.

Font transport uses a dedicated `TICKET_FONT_SERVICE_SECRET`, shared only by the
Worker and the three font-rendering Edge owners. Provision it in protected
Worker/Edge secret stores before activating the new transport. It is restricted
to immutable private `ticket-fonts/sha256/` read/create; end-user credentials and
arbitrary keys are rejected. IDs, hash validation and resolver policy stay owned
by the existing font resolver. Account-deletion transport is migrated in this
staged source; registry import and coordinated activation are still required.

The archive library can write the explicit v2 canonical-asset format with
`asset_format=True`; the existing online producer deliberately remains on v1
until migration/backup activation gates pass. The verifier retains a named
historical v1 reader and maps preserved R2 URLs according to the selected format.
No new off-host set, independent restore or recovery-kit refresh is claimed.

Targeted checks are in `image-service-regressions.yml` and `test_all.sh`:
Python inventory/archive fixtures, Node immutable-copy tests, Worker typecheck
and unit tests. Deno font/renderer/secret-isolation tests cover the Edge changes.
See [the execution receipt](../../docs/operations/security-remediation-20261016/storage-r2-retirement-execution-20261018.md)
for actual state and blockers.

## Historical scripts

The older scripts below are retained history. Their host matching and write
contracts are insufficient for this canonical cutover. Do not run them against
production to bypass the manifest, ownership, sync or publication gates.

# Supabase Storage → Cloudflare R2 Migration

Scripts for migrating image files from Supabase Storage to Cloudflare R2 and rewriting all database URLs.

## Architecture

```
Supabase Storage (public-files bucket)
  ↓ migrate-files.js (download via HTTP, upload via wrangler CLI)
Cloudflare R2 public-only bucket
  → https://img.festapp.net/ (direct custom domain after P3)
Cloudflare R2 private bucket
  → https://image-api.festapp.net/private/... (authenticated Worker)
```

## Scripts

| Script | Purpose | Destructive? |
|--------|---------|:---:|
| `migrate-files.js` | Download files from Supabase, upload to R2 | No (additive) |
| `rewrite-urls.js` | Rewrite all Supabase URLs in database to R2 URLs | **Yes** |
| `verify.js` | Check zero Supabase URLs remain in database | No (read-only) |
| `find-orphans.js` | List R2 objects not referenced in database | No (read-only) |
| `private-bucket-cutover.js` | Inventory/copy/verify private objects | Delete mode only |

## Setup

```bash
cd automation/image-migration
cp .env.example .env    # Fill in credentials
npm install
```

## Usage

### Step 1: Migrate files to R2

```bash
# Preview what will be migrated
node migrate-files.js --dry-run

# Run migration (uploads to R2 via wrangler CLI)
node migrate-files.js

# Increase parallelism (default: 3)
node migrate-files.js --concurrency 5
```

**Prerequisites:**
- `wrangler` authenticated (`npx wrangler login`)
- R2 bucket `festapp-images` exists
- `DATABASE_URL` set in `.env`

**How it works:**
1. Queries database for all distinct Supabase Storage URLs across 18+ columns
2. Filters to only this project's Supabase instance (`kjdpmixlnhntmxjedpxh`)
3. Downloads each file via public HTTP (no service role key needed)
4. Uploads to R2 via `wrangler r2 object put --remote`
5. Skips files already in R2 (idempotent)

### Private bucket isolation (P1 only)

```bash
npm run private:inventory
npm run private:copy
npm run private:verify
# Separate authorized source-deletion checkpoint only:
node private-bucket-cutover.js --delete --confirm-source-delete
```

The copy is resumable through `PRIVATE_CUTOVER_LEDGER`, verifies destination
size before recording success and never deletes a source during copy. The ledger
contains object keys and must remain restricted operational data.

### Step 2: Verify the authorized public route serves files

Before rewriting URLs, verify the Worker is serving files:

```bash
curl -I https://img.festapp.net/images/SOME_FILE.jpg
# Should return HTTP 200
```

### Step 3: Rewrite database URLs

```bash
# Preview changes (no writes)
node rewrite-urls.js --dry-run

# Apply URL rewrites
node rewrite-urls.js
```

**What it rewrites:**

| Table | Column | Type |
|-------|--------|------|
| `images` | `link` | Plain text |
| `icons` | `link` | Plain text |
| `occasions` | `data->image`, `data->email_banner`, `data->logo` | JSONB |
| `occasions` | `data->map_layer->layer_link`, `data->map_layer->logo` | JSONB |
| `occasions` | `features` (background URLs in array) | JSONB |
| `units` | `data->email_banner` | JSONB |
| `organizations` | `data->email_banner` | JSONB |
| `information` | `description` | HTML |
| `events` | `description` | HTML |
| `news` | `message` | HTML |
| `places` | `description` | HTML |
| `user_group_info` | `description` | HTML |
| `email_wrappers` | `html` | HTML |
| `email_templates` | `html` | HTML |
| `forms` | `header`, `header_off` | HTML |

**URL patterns handled:**
- `public-files/` bucket URLs → direct path mapping
- `custom-files/` bucket URLs → direct path mapping
- Signed `editor-files/` URLs (with `?token=...`) → `editor/` prefix

### Step 4: Verify migration

```bash
node verify.js
```

Checks:
1. Zero Supabase Storage URLs remaining in all columns
2. File count parity between Supabase and R2 (if credentials provided)
3. Dual-write period status

### Step 5: Find orphan images (optional)

```bash
# Human-readable output
node find-orphans.js

# JSON output
node find-orphans.js --json

# Write to file
node find-orphans.js --output orphans.json
```

Requires R2 API credentials in `.env`.

## Rollback

The direct-delivery cutover preserves stored `img.festapp.net` URLs. P3 rollback
restores only the recorded Worker route/version and purges the changed
representation; it never moves private data back or restores client-selected
credentials. See the evidence document for the required checkpoint record.

## Configuration

The R2 target URL is configured in `lib/url-rewriter.js`:

```javascript
export const R2_PREFIX = 'https://img.festapp.net/';
```

Stored `img.festapp.net` URLs remain stable when the hostname moves from Worker
to its exact public R2 bucket, so the direct-delivery cutover needs no DB rewrite.

## Migration Log

### 2026-02-18: Initial migration (workers.dev)

- **Files migrated:** 231 (230 initial + 1 retry)
- **Failed (missing in Supabase):** 4 files no longer exist in source bucket
- **Failed (editor-files):** 3 files in private bucket, need service role key
- **URL rewrites:** 362 rows (336 first pass + 26 second pass after html-rewriter fix)
- **Remaining:** 24 rows from hvezdamorska project (`lwfpdjxsdmkfyrzqbrlk`) — separate migration
- **Historical target URL:** a workers.dev migration route that is no longer a supported client contract

Current split-plane production checkpoints are tracked in
`docs/plans/image-delivery-cost-cutover-evidence-2026-08-23.md`.

The historical bulk URL rewrite refuses writes once the canonical mutation release marker exists. Use `--dry-run` for read-only inspection; canonical writes require typed commands or a separately approved data repair.
