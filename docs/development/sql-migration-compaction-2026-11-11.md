# SQL migration compaction, 2026-11-11

370 committed forwards through `20261107170000` are folded into the
[final-state baseline](../../supabase/baseline/manifest.json). Schema plus
reference seed replace 308,445 SQL lines with 99,692, removing 208,753 lines
(67.7%). The 23 later migrations on integration base `fbcdc070e` remain separate
and byte-for-byte unchanged. No production migration or deployment is included.

Installers restore the final state and record all 481 covered ledger versions.
Historical originals remain checksum-pinned gzip recovery fixtures, not active
SQL. Python and Node tooling recover exact original bytes without Git or network
access. Shared writers refuse to regenerate covered active SQL. A separate
cleanup removes 39 redundant connector-history SQL copies (11,047 lines), whose
original inputs are reconstructed from the immutable migration's SOURCE blocks.

## Preserved upgrade and execution boundaries

Existing databases still execute their missing original migrations. Covered
forwards are staged too, ensuring order-symbol backfill finishes before the
NOT NULL contract. The separate email rehearsal selects its original predecessor
snapshots even when later revisions retain the same filenames.

The folded security history left the migration connection in `supabase_admin`.
The manifest records this execution context. Only the temporary CLI copy of the
first later forward receives its explicit session-role prelude; repository SQL
and recovered historical bytes remain unchanged. This preserves the original
cold replay's grants instead of accidentally inheriting another owner's defaults.
The owned local runtime retains its loopback/container fencing, canonical owner
alignment and role checks. It expands validated literal seed includes before
streaming SQL and fingerprints compressed recovery objects and nested seeds.

## Verification

The [machine-readable receipt](sql-migration-compaction-2026-11-11.json) records
installation hashes and integration-base comparisons.

- Rebuilt both PG15 and PG17 from the unchanged current-main 393-migration chain,
  then independently installed the compacted baseline plus 23 forwards using
  the current owned SQL runtime and pinned providers.
- Strict current-main comparisons pass for schema/ACL, roles and memberships,
  extensions, all 504 ledger versions, reference rows and sequences. Both sides
  have cron disabled and zero unresolved regclass references. No provider table
  exclusion was needed for these integration comparisons. Grant statement and
  policy-role ordering are normalized without omitting permissions.
- PG17's 75 retained historical MAINTAIN grants are recorded explicitly, guarded
  by provider major. Fresh installations generate their own abuse/Wix secrets;
  secret bytes are never captured. Font seeds remain shared checksum-pinned inputs.
- One declared volatile reference field, `email_capacity.next_send_at`, is omitted
  from row equality. The baseline represents a retired waitlist OID with a zero
  tombstone; current main's existing November retirement forward removes it before
  strict validation. No numeric OID from another cluster becomes a live reference.
- Earlier populated September-upgrade evidence retained order state, price and
  JSON marker, backfilled its symbol before the contract and reached 489 versions.
  Earlier targeted SQL runs passed five contracts on PG15 and two on PG17.
- Recovery/corruption, immutable-writer, staged-backfill, recorded execution-role,
  literal-include, runtime identity and source-parity checks cover the integration.

Two broader tooling failures were reproduced on an independent unchanged
`fbcdc070e` checkout: route abuse-inventory classification and duplicate authored
ownership of `occasion_reserved_public_paths_internal()`. They are not waived
production release gates. Full canonical mirror results remain associated with
the exact integration candidate and its local CI receipt.

The publication candidate was subsequently rebased onto `7c0636be7`, retaining
its new read-only bank-refund forward (24 active forwards total). Effective
source/assembler checks and both affected SQL contracts passed after the rebase.
The full local mirror was incomplete because another session held its global
lock. The owner explicitly accepted the main publication/review exception;
GitHub remains authoritative for full CI and all production release gates.
