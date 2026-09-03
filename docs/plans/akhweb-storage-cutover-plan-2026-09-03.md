# AKH web storage cutover and Pilgrimway retirement

Date: 2026-09-03  
Status: Complete  
Verification: standard

## Outcome

The live AKH web no longer reads or writes the legacy Festapp Supabase project
`lwfpdjxsdmkfyrzqbrlk`. Its database and Auth remain owned by AKH project
`iinvsjtnbyxfrdygsfpo`, while all public images use the same canonical
`image-api.festapp.net` + Cloudflare R2 architecture as other applications,
through a dedicated R2 bucket and `akh.img.festapp.net` public hostname. All
stored AKH objects and persisted URLs are migrated without changing page behavior.
The unused Pilgrimway application is unpublished and cannot justify retaining
the legacy `images-temp` runtime path.

## Scope

### In scope

- `akh-cr/akhweb`: copy the complete `akhweb` bucket to R2, rewrite persisted
  URLs, move server actions to the canonical image API, and remove all four
  Supabase image functions and their shared secret.
- `festappnet/festapp`: register AKH in the image Worker, add its authorization
  contract, R2 binding, public hostname, tests and deployment configuration.
- Live AKH Netlify application (`akhcr.cz` / `main--akhweb.netlify.app`).
- `rawen-dev/pilgrimway`: unpublish any matching Netlify site and archive the
  unused repository when its current external state is confirmed.
- Record the plan and operational evidence in `festapp`.

### Out of scope

- `festapp-rideshare` and its independent project `xamctptqmpruhovhjcgm`.
- Moving the AKH-owned database/Auth project itself to Festapp self-hosting or
  to R2-backed persistence.
- Migrating other `images-temp` experiments after Pilgrimway is retired.
- Deleting source Storage objects or the whole `lwfpdjxsdmkfyrzqbrlk` project;
  those remain governed by the broader Supabase decommission runbook.

## Constraints

- Production Auth, data migration and deployment require standard verification.
- Preserve source objects as rollback evidence; do not delete them during this
  cutover (`docs/operations/supabase-self-hosted/storage-authority.md`).
- Keep AKH's existing `uploadImageAction` / `deleteImages` application
  interfaces; their internal HTTP target changes to `image-api.festapp.net`.
- Preserve object keys inside the dedicated R2 bucket.
- Before pushing `akhweb/main`, fetch and compare current `origin/main`, update
  the branch if it advanced, and rerun affected validation.
- Do not disturb the pre-existing Festapp `automation/release/fastlane/Fastfile`
  worktree change.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| AKH DB/Auth and proxy functions use `iinvsjtnbyxfrdygsfpo`. | `akhweb/lib/supabase/config.ts`; deployed function inventory | Keep this project as AKH's canonical backend. |
| The proxy falls back to legacy `lwfp...`, and no target override secret is deployed. | `akhweb/supabase/functions/_shared/verify-event-manager.ts`; AKH secret-name inventory | Remove the fallback and the cross-project hop. |
| Legacy bucket `akhweb` has 476 objects / 211,550,482 bytes. | Management SQL against `lwfp...storage.objects`, 2026-09-03 | Copy and byte/hash-verify all objects before switching. |
| Seven AKH fields contain 90 rows referencing the legacy host. | Management SQL against `iinvs...`, 2026-09-03 | Apply a checked-in forward URL-rewrite migration. |
| Existing Worker supports only projects `default` and `a` and only Festapp permission/image-record RPCs. | `workers/image-worker/src/project-registry.ts`, `upload.ts`, `delete.ts` | Add an explicit AKH registry/auth mode; never pretend AKH has the Festapp schema. |
| Only AKH code calls legacy `upload-image` / `delete-image`. | Cross-repository endpoint and symbol scan | Delete those functions after caller cutover. |
| Pilgrimway only consumes a signed `images-temp/poi_off.json` style URL, expired 2025-12-18. | `rawen-dev/pilgrimway/lib/main.dart`; live HTTP 400 | Retire rather than migrate it. |
| The AKH Netlify site is `akhweb`, with production URL `akhcr.cz`. | Netlify site/deploy inventory, 2026-09-03 | Validate the exact deployed commit and production surface. |

The current AKH write flow is browser/server action -> AKH proxy -> shared
secret -> legacy-project Storage function -> legacy `akhweb` bucket. Reads use
the legacy public URLs persisted in AKH content tables.

## Target architecture and invariants

### Canonical owner and contract

The Festapp image Worker owns image transport and R2 persistence. Registry entry
`akhweb` binds the AKH Supabase origin/anon key (server configuration only), a
dedicated `festapp-images-akhweb` R2 bucket and `akh.img.festapp.net`. The Worker
validates the user's AKH JWT through a narrow `get_can_manage_images()` RPC,
writes canonical keys supplied through a bounded AKH path contract, and does
not call Festapp-only image-record RPCs. AKH server actions preserve their local
interface while calling `image-api.festapp.net/upload|delete` with
`projectId=akhweb`.

### Invariants

1. All 476 source objects exist at the same keys in the target and match by
   SHA-256 before database URLs change.
2. No AKH persisted value or production source references `lwfp...` after the
   final deployment.
3. Only authenticated AKH event managers can upload or delete.
4. Delete cannot target another hostname, R2 project or key prefix.
5. Source data remains intact until the broader legacy-project deletion gate.
6. All four old Supabase image functions and the shared secret are absent.

### Entry points and forbidden bypasses

- Keep: `image-api.festapp.net/upload|delete`, project ID `akhweb`, public host
  `akh.img.festapp.net`, and the AKH server-action interfaces.
- Forbidden: AKH Supabase image proxy/storage functions, `STORAGE_FUNCTIONS_URL`,
  `STORAGE_URL`, `UPLOAD_SECRET`, and legacy image host allowlists.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Use a dedicated R2 bucket/hostname registered in the existing image
  Worker; AKH DB/Auth stays independent.
- **D2:** Preserve object keys and rewrite the exact legacy Storage base to
  `https://akh.img.festapp.net/`.
- **D3:** Switch upload before database URLs, reconcile source deltas, then
  switch delete and readers; no permanent dual-write or fallback remains.
- **D4:** Retire Pilgrimway and do not migrate its `images-temp` dependency.

### Assumptions

- **A1:** The Cloudflare account permits a new R2 bucket and Worker custom-domain
  route; resolve before copy and abort without switching if provisioning fails.
- **A2:** No untracked external caller knows the shared upload secret; resolve
  by deleting the legacy functions and confirming no repository caller remains.

### Blockers

- None at plan time. If no Pilgrimway Netlify site exists in the authenticated
  account, record that absence rather than deleting an unrelated similarly
  named site.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| AKH Supabase image proxy functions | Current browser/server boundary | Delete after image API adoption | Supabase function inventory |
| AKH `STORAGE_FUNCTIONS_*` fallback | Routes proxy to `lwfp...` | Delete | Repository absence search |
| `UPLOAD_SECRET` in AKH and legacy projects | Cross-project authorization | Unset after function cutover | Supabase secret-name inventory |
| Legacy `upload-image`, `delete-image` functions | Storage writers on `lwfp...` | Delete after final reconciliation | Supabase function inventory |
| `akhweb` legacy hostname allowlist | Loads old image URLs | Replace with `akh.img.festapp.net` | Build plus absence search |
| Legacy URL values in seven AKH fields | Read path to old bucket | Transactionally rewrite | Zero-count database query |
| Storage-secret helper/tests and storage-side functions | Implements obsolete second hop | Delete | Repository absence search |
| Pilgrimway deployment | Unused consumer | Unpublish; archive repo | Netlify and GitHub state |

## Implementation waves

### Wave 1 — Reproducible target and migration tooling

**Goal**

The image Worker describes AKH as a first-class R2 project and migration tooling
provides a resumable, hash-verifying Supabase-to-R2 copy.

**Changes**

- Add registry ID `akhweb`, R2 binding/hostname, exact CORS origin and AKH auth
  mode to `workers/image-worker`.
- Add `get_can_manage_images()` to AKH with fixed search path and authenticated-
  only execute.
- Extend upload/delete with a bounded AKH key contract and no Festapp-only image
  record side effects; add focused Worker tests.
- Change AKH server actions to the canonical image API and remove all Supabase
  image functions/helpers/config/tests.
- Add a checked-in R2 copy/hash verifier and exact URL migration.

**Migration/deletion**

- No production state changes in this wave.

**Failure and compatibility**

- Copy is idempotent only for byte-identical targets; mismatched collisions
  abort. URL migration is retry-safe exact replacement.

**Validation**

- Run focused Deno/Vitest tests, lint/build, and dry-run inventory.

**Exit condition**

- Both repositories' tests pass and no AKH production code contains the legacy
  proxy/fallback/shared-secret path.

### Wave 2 — Copy, verify and transitional writer cutover

**Goal**

Every source object is present in dedicated AKH R2 and all new writes go there.

**Changes**

- Create R2 bucket `festapp-images-akhweb` and route `akh.img.festapp.net`
  through the image Worker.
- Copy all source objects preserving key/content type/cache control.
- Compare source/target key sets, sizes and SHA-256.
- Deploy the Worker and AKH authorization RPC, then switch AKH uploads to the
  canonical image API while legacy reads remain valid.

**Migration/deletion**

- Reconcile objects created on the source during the initial copy immediately
  after the writer switch.

**Failure and compatibility**

- Any copy/hash mismatch stops before URL rewrite. Source remains the rollback
  read path until the database migration commits.

**Validation**

- Inventory reports 476 matching objects and 211,550,482 matching bytes (or a
  strictly explained post-inventory delta captured by reconciliation).

**Exit condition**

- Target parity passes and a disposable authenticated upload smoke succeeds
  through the canonical API.

### Wave 3 — Reader and database cutover

**Goal**

All persisted and generated AKH image URLs use the AKH project.

**Changes**

- Apply the checked-in SQL migration to `iinvs...`.
- Replace the legacy image hostname with `akh.img.festapp.net` in Next.js.
- Deploy/push the web change only after fetching current upstream main.

**Migration/deletion**

- Rewrite the seven confirmed text fields transactionally and assert the old
  host count becomes zero.

**Failure and compatibility**

- Database rollback is an exact reverse origin replacement while source
  objects remain retained; new uploads must not be reversed without first
  copying their objects back.

**Validation**

- Zero legacy DB references; the live surface returns 200 and representative
  images load from `akh.img.festapp.net`.

**Exit condition**

- Live pages and admin image flow use only canonical URLs.

### Wave 4 — Contract and legacy contraction

**Goal**

The cross-project runtime is unreachable and Pilgrimway is retired.

**Changes**

- Switch deletes to the canonical image API and validate strict project/host/key
  routing.
- Delete all four AKH/legacy Supabase image functions.
- Unset `UPLOAD_SECRET` on both projects.
- Unpublish the exact Pilgrimway Netlify site if present; archive the confirmed
  unused GitHub repository.
- Update this plan with execution evidence.

**Migration/deletion**

- Do not delete legacy Storage objects; retain them only as the named broader
  decommission boundary.

**Validation**

- Function/secret inventories, cross-repository absence search, target object
  parity, live HTTP and authenticated production smoke.

**Exit condition**

- No active caller or function reaches legacy Storage; only retained rollback
  objects remain for whole-project decommission.

## Rollout and rollback

Copy precedes writers, writers precede URL rewrite, and legacy removal follows
live validation. Before URL rewrite, rollback means redeploying the prior AKH
proxy. After URL rewrite, rollback also requires reversing the exact origin in
the seven fields; source objects are retained for that purpose. Once new AKH
uploads exist only in the target, rollback requires copying those keys back and
must not be improvised.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Authorization preserved | AKH RPC and Worker tests | targeted SQL + `workers/image-worker` tests |
| Web contract preserved | AKH app suite and production build | `npm test -- --run && npm run lint && npm run build` |
| Object parity | Copy verifier | key/size/SHA-256 summary |
| URL migration complete | AKH management SQL | zero fields containing `lwfp...` |
| Runtime contraction | Supabase inventories and `rg` | no old functions, secret or hostname |
| Live behavior | Production smoke and HTTP | upload/delete passes; both sites 200 |

## Definition of complete

- [x] Every intended entry point reaches the registered AKH R2 project.
- [x] All source objects and persisted URLs are migrated and verified.
- [x] Legacy functions and secrets are removed.
- [x] Pilgrimway is unpublished and archived, or exact absence is recorded.
- [x] Standard targeted validation and live smoke pass.
- [x] No unintended fallback or legacy reference remains in AKH production code.

## Execution evidence

- Cloudflare Worker version `91274cb4-fe67-401a-b8cc-0a5410ab2a0e` serves the
  dedicated `festapp-images-akhweb` bucket at `akh.img.festapp.net`. A disposable
  AKH administrator passed upload, public GET (200), delete and subsequent GET
  (404) through the production image API.
- Two complete source-to-target SHA-256 passes matched 476 objects and
  211,550,482 bytes, manifest
  `108b2fc540a995a85904df49cf637589944d7426563844cec9f5cf6a94f47068`.
- The checked-in URL migration was applied to `iinvsjtnbyxfrdygsfpo`.
  All seven fields contain zero legacy-host rows; 89 current rows (140 URL
  occurrences) use `akh.img.festapp.net`. Five sampled objects returned 200.
- AKH commits `d9de0d3` and `0628b55` are pushed on current upstream `main`;
  the production build and 151 tests pass. Lint retains 13 pre-existing errors
  and 6 warnings outside the storage change.
- Both projects report zero scoped legacy image functions and zero
  `UPLOAD_SECRET`. The source objects remain intact as the rollback boundary.
- Netlify contains no site associated with `rawen-dev/pilgrimway` and GitHub
  Pages/deployment inventories are empty. The repository is archived.

## Residual risks

- Legacy source objects remain publicly readable until the whole `lwfp...`
  project is decommissioned; no in-scope client will reference them.
