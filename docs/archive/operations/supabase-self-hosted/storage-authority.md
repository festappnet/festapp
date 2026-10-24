# Storage authority during the self-hosted cutover

> Historical backend migration record. The production switch completed on 2026-09-10. Planning statuses and commands below describe that earlier phase; they are not current release gates. Use [current documentation](../../../README.md) and its open work items for present operations.


Decision date: 2026-08-27. The source inventory and copy sequence below are the
original migration record, not a current object count or instruction to reopen
cloud writes. The production switch completed on 2026-09-10.

## Current write/read boundary

New image uploads and copies use the image Worker/R2 path. Historical canonical
Storage URLs remain an explicit read/delete compatibility boundary; their
presence does not permit restoring the old Storage upload/copy writers.
Follow [image delivery](../../../backend/image_worker.md) for current ownership and
adoption gates, and [server deployment](../../../setup/server_deployment.md) for
runtime setup.

## Original consolidation decision

The Supabase consolidation does not perform a new Supabase-to-R2 migration.
Every object that still exists in either cloud Supabase Storage project is
copied, hash-verified and imported into the one canonical self-hosted Supabase
Storage service. Source objects are not deleted.

The existing R2 image-delivery architecture remains separate:

- `img.festapp.net` and `a.img.festapp.net` continue to select their existing
  project-specific R2 public buckets;
- `image-api.festapp.net` continues to own authenticated image operations;
- after backend cutover, both image project IDs authenticate against the one
  canonical Supabase endpoint while retaining their R2 bucket routing;
- the unfinished P3/P4 image-delivery cutover keeps its own evidence gates and
  receives no destructive authority from this migration.

At the decision date, code still reached Supabase Storage
for `editor-files`, `public-files` and `images-temp`, including upload, copy and
delete behavior. Removing or redirecting those buckets now would broaden the
cutover and risk data loss. A future complete R2 migration requires a separate
inventory, application contract, copy/hash proof, adoption window and explicit
deletion approval.

The 2026-08-27 source inventory recorded 1,199 objects and 521,859,566 bytes. Zero
equal bucket/key pairs exist between `default` and `a`, so every object can keep
its source key at the current evidence point. Production export must still
compute and verify SHA-256 for every object; metadata ETag is not content proof.
