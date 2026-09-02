# Festapp self-hosted Supabase migration

This directory contains reproducible, secret-free automation for the migration
described in `docs/plans/festapp-self-hosted-supabase-hetzner-plan-2026-08-27.md`.

Production exports, identity mappings, access tokens, database credentials and
raw inventory results must never be stored here. Real runs require an output
directory outside the repository.

## Current implemented boundary

The Wave 0 inventory foundation and its fail-closed decision gate are
implemented. Provider history, collision scans, all-writer classification and
manual decisions remain required before Wave 0 can pass. Run both source
catalog inventories into one private directory:

```bash
export FESTAPP_MIGRATION_OUTPUT=/absolute/private/path/wave-0
node automation/hetzner-supabase/merge/inventory.mjs \
  --source default --output "$FESTAPP_MIGRATION_OUTPUT/default.json"
node automation/hetzner-supabase/merge/inventory.mjs \
  --source a --output "$FESTAPP_MIGRATION_OUTPUT/a.json"
node automation/hetzner-supabase/merge/schema-fingerprint.mjs \
  "$FESTAPP_MIGRATION_OUTPUT/default.json" \
  "$FESTAPP_MIGRATION_OUTPUT/a.json"
node automation/hetzner-supabase/merge/collision-inventory.mjs \
  --output "$FESTAPP_MIGRATION_OUTPUT/collisions.json"
node automation/hetzner-supabase/merge/resolve-auth-collisions.mjs \
  --input "$FESTAPP_MIGRATION_OUTPUT/collisions.json" \
  --output "$FESTAPP_MIGRATION_OUTPUT/identity-decisions.json"
node automation/hetzner-supabase/merge/write-authority-inventory.mjs \
  --output "$FESTAPP_MIGRATION_OUTPUT/write-authority.json"
node automation/hetzner-supabase/runtime/validate-operational-readiness.mjs \
  --evidence="$FESTAPP_MIGRATION_OUTPUT/operational-readiness.json" \
  --output="$FESTAPP_MIGRATION_OUTPUT/operational-readiness-decision.json"
node automation/hetzner-supabase/merge/hybrid-readiness.mjs \
  --output "$FESTAPP_MIGRATION_OUTPUT/hybrid-readiness.json"
node automation/hetzner-supabase/merge/tenant-config-inventory.mjs \
  --output "$FESTAPP_MIGRATION_OUTPUT/tenant-configs.json"
node automation/hetzner-supabase/merge/migration-history-inventory.mjs \
  --output "$FESTAPP_MIGRATION_OUTPUT/migration-history.json"
```

Each source catalog inventory also writes a sibling `*.manifest.json`. It
deliberately remains `blocked` and unsigned until all Wave 0 evidence is
attached and signed by the approved evidence process. The collision,
write-authority, hybrid-readiness and tenant-config passes are immutable
supporting evidence files rather than source snapshot manifests.
The operational readiness decision is also append-only private evidence. It
expires after 30 minutes and is required in addition to repository readiness;
it performs no production mutation.

The collision pass reads Auth e-mails and Storage object keys only in memory.
Its evidence file contains source UUIDs plus one-run HMAC identifiers; the HMAC
key and raw identifiers are not persisted. It never resolves a collision.
The separate resolver applies only the approved, verified-email/default-UUID
rule and blocks every ambiguous input.
The write-authority inventory is deliberately blocking: regex discovery creates
a candidate list, and every entry needs a human-reviewed owner/contract before
the hybrid design may proceed.

`hybrid-readiness.mjs` associates the nine known Flutter direct-DML candidates
with their existing typed `client_sync_v1` command modules, then compares that
partial seam evidence with read-only evidence from source `a`. It resolves the
source from production `project.conf` files and verifies configured forced
occasions before reading live occasion aggregates. Every overload is checked
independently for `SECURITY DEFINER` and the exact approved `search_path`. The
report never authorizes the global hybrid gate: it does not prove operation
completeness, permission checks, deployed traffic or non-Flutter writers. It
never enables a cohort, changes a grant or deploys a function.

`tenant-config-inventory.mjs` reads only `automation/project.conf` from remote
`origin/prod/*` refs. Its allowlist excludes anon keys and other configuration.
An app without `FORCE_OCCASION_LINK` is conservatively classified as able to
reach every visible occasion in its source organization until deployment and
traffic evidence proves a narrower contract.

The checked-in RPC search-path hardening migration is a prepared artifact, not
permission to deploy. It requires the complete 41-signature client-sync
expansion to exist first and intentionally aborts on missing or additional
overloads. Apply it only inside the ordered expansion/rehearsal workflow; never
as an isolated hotfix to the current drifted `default` cloud project.

`migration-history-inventory.mjs` compares the immutable repository migration
set with the read-only `supabase_migrations.schema_migrations` history of both
approved sources. A missing history row is not proof that the SQL effect is
absent, and a recorded row is not proof that its current effect matches the
repository. The report never emits deployment permission; use it to identify
history divergence that must be reconciled by catalog comparison in a rehearsal
database.

`SUPABASE_ACCESS_TOKEN` may be supplied in the environment or in the repository
root `.env.local`. The scripts never print it. Source aliases are pinned to the
two approved project refs and cannot be redirected with `.env.local` project
metadata.

Do not provision infrastructure or implement a production importer until the
Wave 0 gate in the merge runbook is approved.
