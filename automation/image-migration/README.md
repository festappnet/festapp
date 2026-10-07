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
