# Local database development

Festapp has an existing production schema that predates Supabase CLI migration
tracking. Timestamped files in `supabase/migrations/` are forward upgrades, not
a complete historical bootstrap. A clean local database therefore starts from
the versioned schema-only baseline and applies only migrations newer than that
baseline.

The installation contract is `supabase/baseline/manifest.json`. It pins the
schema, provider bootstrap, non-tenant reference seed, covered migration ledger
and immutable historical Git inputs by checksum. The baseline contains no
production rows or secrets.

## First-time setup and reset

1. Install Supabase CLI and `psql`, then start Docker Desktop, Colima, or
   another Docker-compatible runtime. The CLI is used only for this isolated
   development database, never to install the production system.
2. Rebuild the dedicated local database:

   ```bash
   ./automation/bootstrap_local_db.sh
   ```

The command deletes and recreates only the Docker volume belonging to
`festapp-db-tests-pg15`, starts PostgreSQL 15 on port `55432`, restores
the manifest-owned baseline through `20260906140000`, records its 111 covered
migration versions, applies newer forward migrations, and runs
`supabase/seed.sql`.

Database URL:

```text
postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable
```

Stop and remove the isolated database with:

```bash
./automation/bootstrap_local_db.sh --stop
```

## Running tests

```bash
# Override any DATABASE_URL supplied by .env.local.
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  ./automation/test_all.sh db

# Run one SQL contract directly.
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  node web_client/scripts/run_db_tests.js database/tests/companion_contract_test.sql

# Complete client suite (core + native Dart adapters + Flutter), no database.
./automation/test_client.sh
```

First resolve root dependencies with `fvm flutter pub get`, then run
`fvm dart pub get` inside `packages/festapp_core`. For a partial run use
`./automation/test_client.sh core` or `./automation/test_client.sh flutter`.

Each SQL test runs in a transaction and rolls back its fixture data. The runner
may reset sequences, which is why it must target the dedicated local database,
never production.

## Migration rules

- Active migrations use one unique `YYYYMMDDHHMMSS_name.sql` filename in
  `supabase/migrations/`.
- Covered historical SQL is recovered from checksum-pinned Git objects rather
  than kept in the active migration directory. Its versions remain in the ledger.
- The bootstrap uses `automation/baseline.py upgrade-local` to materialize a
  complete temporary migration history for Supabase CLI and apply active forwards.
- Pre-Supabase `0.x.sql` upgrade fragments live in
  `database/migrations_legacy/`; they are historical records and are not active
  migrations.
- Never edit an applied production migration. Add a new forward migration.

When refreshing the baseline, prove schema, reference-row, sequence and ACL
parity on PG15 and PG17, checksum every installation input, and preserve supported
upgrades before removing covered files. Never rewrite an applied migration.

## Existing local database upgrades and historical recovery

A disposable local database with the original August baseline ledger is supported:

```bash
python3 automation/baseline.py upgrade-local --database-url 'postgresql://supabase_admin:postgres@127.0.0.1:55432/postgres?sslmode=disable'
python3 automation/baseline.py historical-kit /tmp/festapp-historical-kit --email
```

The upgrade command requires a loopback port owned by a local Festapp Docker
PostgreSQL container. It runs the existing order-symbol backfill before the
corresponding contract migration, then applies the remaining forwards. It refuses
older or missing original-baseline ledgers. Use the extension-owning local role
`supabase_admin` where required by the provider image.

Historical recovery needs the full Git objects pinned in
`automation/historical-sql-manifest.json`; use a full clone or fetch the recorded
commits in a shallow checkout. Recovery validates all checksums before writing,
refuses conflicting files, and never substitutes current source definitions.
`automation/email-delivery/rehearse-local.sh` uses this kit for its legacy upgrade.

## Production safety

`bootstrap_local_db.sh` defaults to `127.0.0.1:55432` and its dedicated local
Supabase project ID. Isolated checks may select a separate project, workdir and
port with `FESTAPP_LOCAL_DB_PROJECT_ID`, `FESTAPP_LOCAL_DB_WORKDIR` and
`FESTAPP_LOCAL_DB_PORT`. Scheduled cron execution is disabled before SQL restore. It does not read `DATABASE_URL`, link a remote project, or
run `db push`. Testing against production is not part of the supported workflow.

## Generated app fonts

Version shared font binaries only in `automation/fonts/`. Flutter copies under
`fonts/` and all web copies under `web_client/src/assets/fonts/` are ignored.
Before running Flutter commands directly after a fresh checkout, prepare assets:

```sh
node automation/configure_fonts.js . --assets-only
```

This reads the selected tenant's `FONT_FILES` and copies bytes without rewriting
configuration. `apply_config.sh`, the client test wrapper, web dev/build commands
and CI prepare these assets automatically. Tenant-specific files listed in
`FONT_FILES` remain versioned sources under `fonts/`. The ticket renderer's
`ticket-assets/font.ttf` remains a deployment input for its independent bundle.
