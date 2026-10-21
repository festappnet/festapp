# Historical backend merge runbook

> The completed cloud merge commands referenced here were retired; recover the
> [pinned historical source](../../archive/cloud-merge-tooling-cleanup-2026-10-21.md) for deliberate historical replay.
> These commands are not current installation or release prerequisites.


This sequence belongs to the completed 2026 consolidation of former cloud sources.
Its Wave 0 permissions and source-import steps are not current installation or
upgrade instructions. Some standalone merge helpers were later removed; preserve
the [cleanup receipt](../work-items/completed/preactivation-and-migration-tool-cleanup-2026-10-07.md)
and recover historical source from its recorded Git revision only for a separately
scoped replay. Current operations start with
[server deployment](../../setup/server_deployment.md) and
[protected backend access](../../../.agents/skills/festapp-backend-access/SKILL.md).

## Wave 0: read-only inventory

1. Create a private `0700` evidence directory outside the repository.
2. Run `inventory.mjs` for `default` and `a`; preserve each `0600` inventory and
   sibling evidence manifest. Inventory manifests remain blocked and unsigned
   until all evidence below is attached and the approved signing step runs.
3. Generate the schema drift report with `schema-fingerprint.mjs`.
4. Generate the read-only migration history report with
   `migration-history-inventory.mjs`. Treat history rows as provenance clues,
   not schema truth. If either source has missing, extra or renamed versions,
   do not apply a timestamp catch-up to production. Build the repository
   baseline in rehearsal and compare catalog effects instead.
5. Add provider metrics for 30/90-day database and Storage growth, WAL rate and
   peak connections. The catalog snapshot intentionally cannot infer history.
6. Complete the write-authority matrix for every client, Function, cron,
   webhook, payment/bank callback, image worker and manual script.
7. Perform the separately approved private identity/Storage collision pass.
   Never place identities, mappings or object listings in Git.
   Apply `resolve-auth-collisions.mjs` only when every collision is the approved
   verified-email/default-UUID case; any ambiguity remains a blocker.
8. Resolve every schema drift and collision, and assign an owner to every manual
   decision.
9. Select a source-compatible PostgreSQL major and pinned Supabase release.
10. Size DB, Storage, WAL, staging and restore workspace with at least 50% disk
   headroom after all are included.

Stop immediately on an unknown writer, source mismatch, unexplained schema drift,
unresolved collision or missing source credential.

## Wave 0 approval gate

Infrastructure provisioning is prohibited until all of these are attached to a
signed inventory manifest and explicitly approved:

- both source fingerprints and schema drift disposition;
- all-tenant write-authority matrix;
- table classification and embedded-reference registry;
- Auth/provider/MFA and Storage collision disposition;
- combined sizing, PostgreSQL major and runtime pin;
- RPO, RTO, cloud retention, DNS owner, secret owner and on-call owner;
- decision between journaled hybrid and full maintenance freeze.

## Isolated canonical-schema rehearsal

The already approved empty rehearsal host may build the repository-owned schema
without copying source rows. Transfer the current Festapp checkout to the host,
verify its commit, and run as root:

```bash
FESTAPP_REHEARSAL_ACK=canonical-schema-only \
  automation/hetzner-supabase/rehearsal/build-canonical-schema.sh
```

The builder refuses any hostname other than
`festapp-supabase-rehearsal-01`, any PostgreSQL major other than 17, and any
target that already has a business relation in `public` or `eshop`. It first
stores a root-only schema snapshot, applies the canonical baseline and only the
later repository migrations, and records aggregate evidence proving that Auth
and Storage still contain zero source rows. It never runs `supabase/seed.sql`.

If a migration fails, stop. Do not repair the partially applied target by hand
and do not add a force/overwrite mode. Recreate the empty rehearsal foundation
through the separately reviewed restore procedure, preserve the failed evidence,
then rerun the exact automated sequence.

## Empty private merge staging

After the canonical schema evidence passes, prepare the locked staging ledger:

```bash
FESTAPP_REHEARSAL_ACK=prepare-empty-private-merge-staging \
  automation/hetzner-supabase/rehearsal/prepare-merge-staging.sh
```

The script is additive and single-use. It refuses any host except the exact
rehearsal hostname, any PostgreSQL major except 17, a migration ledger other
than 101, non-empty Auth or Storage, or an existing `festapp_merge` schema. The
schema is inaccessible to `anon`, `authenticated` and `service_role` and starts
with zero rows.

Rows which cannot satisfy the canonical contract must be inserted into
`festapp_merge.quarantined_rows`, never silently discarded. A quarantined row
keeps the rehearsal run blocked until an explicit `repair` decision or an
`omit-with-ledger` decision names the checksum of private evidence. The two
known orphan `default.user_companions` rows therefore remain preserved and
blocked; this step does not import them or mutate either cloud source.

## Encrypted read-only source snapshot

Never write a plaintext production dump. Prepare a private `0700` output
directory outside the repository, provide the exact source database URL only in
the process environment, and encrypt the `pg_dump` stream directly to a native
age recipient or an existing SSH Ed25519 public key:

```bash
FESTAPP_SOURCE_DATABASE_URL='postgresql://...' \
FESTAPP_EXPORT_AGE_RECIPIENT='age1...' \
  node automation/hetzner-supabase/merge/export-source.mjs \
  default /private/evidence/default.dump.age
```

Repeat for every alias in `merge/source-registry.json`. The exporter accepts only
the centrally registered approved project refs, requires TLS, keeps the password out of child
process arguments, refuses a group/world-accessible directory, never overwrites
an artifact, and writes a sibling `0600` checksum manifest. A failed stream is
preserved for diagnosis and must not be mistaken for a complete artifact because
it has no manifest.

For the rehearsal application schemas, use `rehearsal-export-clouds.mjs`. It
creates a unique one-hour export role separately in each approved project,
grants only read access to `public` and `eshop` plus `BYPASSRLS`, streams both
encrypted snapshots, and then sets the role to `NOLOGIN NOBYPASSRLS` and
revokes every temporary schema/table/sequence grant. It does not drop the
disabled role, so the run leaves an auditable non-destructive record. Managed
`auth` and `storage` schemas are exported separately through the read-only
Management API path; the temporary role must never inherit their administrative
owner roles merely to make `pg_dump` pass.

```bash
node automation/hetzner-supabase/merge/rehearsal-export-clouds.mjs \
  /private/evidence/root ~/.ssh/id_ed25519.pub
```

For an additive rehearsal of one newly registered source against an already
validated canonical target, restrict both application and managed exports with
the same explicit subset. This does not weaken the final cutover gate, which
still requires fresh evidence for every registered source:

```bash
FESTAPP_EXPORT_SOURCES=slunovrat \
  node automation/hetzner-supabase/merge/rehearsal-export-clouds.mjs \
  /private/evidence/root ~/.ssh/id_ed25519.pub
FESTAPP_EXPORT_SOURCES=slunovrat \
  node automation/hetzner-supabase/merge/export-managed-schemas.mjs \
  /private/evidence/root/cloud-snapshots-RUN ~/.ssh/id_ed25519.pub
```

After both application manifests exist, export managed rows into the same
private run directory:

```bash
node automation/hetzner-supabase/merge/export-managed-schemas.mjs \
  /private/evidence/root/cloud-snapshots-RUN ~/.ssh/id_ed25519.pub
```

Every `auth` and `storage` table must have a primary key; there is no `ctid`
fallback. The read-only API pages are streamed directly into age encryption.
This page-window consistency is sufficient only for rehearsal. The final
cutover uses the separately defined freeze/final-marker freshness gate.

The managed exporter uses 10,000-row pages. Production measurements on the two
largest `a` Auth tables returned about 3.5 MB in 1.8–2.0 seconds per page. This
reduces the measured 802,000-row export from roughly 1,600 API round trips at
the original conservative page size to about 82 without adding parallel source
load. Re-benchmark after provider/API changes; do not raise concurrency merely
to shorten a rehearsal.

## Isolated raw-source staging databases

Application archives are never restored over the canonical database. Prepare
two additive, non-public PostgreSQL databases on the exact rehearsal host:

```bash
FESTAPP_REHEARSAL_ACK=prepare-empty-source-staging-databases \
  automation/hetzner-supabase/rehearsal/prepare-source-staging-databases.sh
```

The guarded builder refuses an existing staging database, non-empty target Auth
or Storage, a missing private merge schema, a PostgreSQL major other than 17 or
any other hostname. `festapp_stage_default` and `festapp_stage_a` contain only
the target extension foundation and deny connection/schema access to public
application roles. Restore application pre-data and data only; post-data
constraints are intentionally validated after transformation against the
canonical target, not forced onto a raw source staging copy.

Managed rows are staged as encrypted-stream-to-`COPY` JSONB, not restored over
runtime Auth or Storage:

```bash
node automation/hetzner-supabase/merge/stage-managed-export.mjs \
  default /private/default.managed.jsonl.age ~/.ssh/id_ed25519
```

Repeat for `a`. The loader verifies the source ref, encrypted artifact checksum,
exact hostname, PostgreSQL major, absent staging schema and final row count. It
creates only `festapp_managed_source.rows` inside the matching isolated source
database; plaintext rows exist only in the streaming process memory.

## Required source-a post-import sequence

The relational importer deliberately leaves source `a` blocked. Declared FKs
are insufficient because the production schema also contains undeclared scalar,
polymorphic and JSON references. Every fresh rehearsal must run the following
forward-only sequence against its newly created target; none of these scripts
has a force, delete or overwrite mode:

```bash
FESTAPP_REHEARSAL_ACK=repair-a-registered-semantic-references-forward-only \
  automation/hetzner-supabase/rehearsal/repair-a-semantic-references.sh

FESTAPP_REHEARSAL_ACK=repair-a-registered-embedded-payloads-forward-only \
  automation/hetzner-supabase/rehearsal/repair-a-embedded-payloads.sh

FESTAPP_REHEARSAL_ACK=repair-a-operational-references-forward-only \
  automation/hetzner-supabase/rehearsal/repair-a-operational-references.sh

FESTAPP_REHEARSAL_ACK=validate-a-reference-registry \
  automation/hetzner-supabase/rehearsal/validate-a-reference-registry.sh
```

The final validator is the only step allowed to return the import to
`validated`. It compares registered source values through the deterministic ID
map, verifies transformed payload equality, proves obsolete inter-project sync
is inert, and requires every registered legacy Storage link to have a copied
object. Their host rewrite remains a separate `api.festapp.net` activation
gate. High sequence values are not compacted in place: a fresh target may use a
new deterministic allocation policy only before import and only when the full
reference registry proves every dependent value is transformed.

Both relational importers also extract any legacy
`organizations.data.ONESIGNAL_REST_API_KEY` into
`organization_notification_secrets` under the mapped target organization ID and
remove the JSON key before the row becomes client-visible. The semantic repair
and final registry validator preserve that separation. A fresh merge must fail
if any source credential lacks a server-only target row or any target
organization JSON still contains the key.

After validation, perform an application-level endpoint canary in this order:
old cloud → self-hosted tunnel → old cloud. Compare semantic config values and
released-client fallback counts rather than requiring equal numeric IDs. For
CSM Ostrava the proven baseline is 26 information rows, 47 news rows, 128
places and 969 events.

## Registered legacy merge sources without migration history

`slunovrat` is an old PostgreSQL 15 source with no trustworthy
`supabase_migrations.schema_migrations` ledger. Never attempt to make that cloud
project current by replaying the canonical migration directory in place. It is
a read-only export source. Restore its application and managed exports into
private staging, transform them into the fresh PostgreSQL 17 canonical schema,
and validate the result there.

For every additive registry source, run the generic sequence with the same
`FESTAPP_MERGE_SOURCE_ALIAS`: ID mapping, relational import, Auth import,
Storage metadata import, payload copy/evidence, integrity validation, then the
source-scoped client-state rebuild/final validator. The last validator is the
only owner of the source run's `blocked -> validated` transition. Missing old
tables are either explicitly `not applicable` when empty or preserved in the
private quarantine ledger; they are never synthesized or silently discarded.

The 2026-08-28 Slunovrat rehearsal proved five occasions, 2,455 source Auth
users (five approved canonical identity mappings), 254 Storage objects, 91
losslessly quarantined legacy rows and 30 public client-sync scopes. Its public
canary returned the mapped Slunovrat 2026 occasion with 132 events. The 228
legacy Storage URLs across all registered sources have copied objects, but
their host rewrite remains an `api.festapp.net` cutover gate.
