# Canonical asset authority

Decision updated: 2026-10-18

The approved Storage retirement supersedes the original consolidation boundary
below. The shared image Worker owns all Festapp file/font operations in
`festapp-images` and `festapp-images-private`; former `a` URLs translate to
canonical imported keys. AKH retains its separate bucket/Auth/DB contract.
`festapp-public` sync/maps and encrypted backups remain independent.

Production copy, current-reference rewrite, Worker and scoped Edge adapters
are deployed. Cleanup remains fenced until the actual new-format independent
recovery passes. Storage services, original volumes and three source buckets
are not yet retired. Follow the authoritative
[plan](../../plans/storage-r2-retirement-plan-2026-10-18.md) and
[execution receipt](../security-remediation-20261016/storage-r2-retirement-execution-20261018.md)
for current gates, rather than treating source publication as live retirement.

## Historical 2026-08-27 consolidation boundary

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

This boundary is necessary because current code still reaches Supabase Storage
for `editor-files`, `public-files` and `images-temp`, including upload, copy and
delete behavior. Removing or redirecting those buckets now would broaden the
cutover and risk data loss. A future complete R2 migration requires a separate
inventory, application contract, copy/hash proof, adoption window and explicit
deletion approval.

Current measured source inventory is 1,199 objects and 521,859,566 bytes. Zero
equal bucket/key pairs exist between `default` and `a`, so every object can keep
its source key at the current evidence point. Production export must still
compute and verify SHA-256 for every object; metadata ETag is not content proof.
