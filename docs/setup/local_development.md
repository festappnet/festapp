# Local database development

Festapp has an existing production schema that predates Supabase CLI migration
tracking. Timestamped files in `supabase/migrations/` are forward upgrades, not
a complete historical bootstrap. A clean local database therefore starts from
the versioned schema-only baseline and applies only migrations newer than that
baseline.

The baseline contains no production rows or secrets. It is a schema dump of the
`public` and `eshop` schemas, including functions, policies, grants and triggers.

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
`supabase/baseline/20260805230000_production_schema.sql`, records all migration
versions included in that baseline, applies newer forward migrations, and runs
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
- Files at or below the baseline version are retained for production history
  but are recorded as already represented when a local database is rebuilt.
- Newer migrations are applied normally by `supabase migration up` during the
  bootstrap.
- Pre-Supabase `0.x.sql` upgrade fragments live in
  `database/migrations_legacy/`; they are historical records and are not active
  migrations.
- Never edit an applied production migration. Add a new forward migration.

When deliberately refreshing the baseline, create a schema-only dump, verify
that it contains no `COPY` or `INSERT INTO` statements, update the baseline
version in `automation/bootstrap_local_db.sh`, and prove a clean rebuild plus
the database contract suite before replacing the old baseline.

## Production safety

`bootstrap_local_db.sh` uses only `127.0.0.1:55432` and the dedicated local
Supabase project ID. It does not read `DATABASE_URL`, link a remote project, or
run `db push`. Testing against production is not part of the supported workflow.
