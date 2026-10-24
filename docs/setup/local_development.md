# Local database development

Festapp has an existing production schema that predates Supabase CLI migration
tracking. Timestamped files in `supabase/migrations/` are forward upgrades, not
a complete historical bootstrap. A clean local database therefore starts from
the versioned schema-only baseline and applies only migrations newer than that
baseline.

The single installation owner is [`supabase/baseline/manifest.json`](../../supabase/baseline/manifest.json).
It pins the schema-only snapshot, provider/bootstrap prerequisites, reference
seed and historical source manifest by SHA-256. The schema includes `public`
and `eshop` functions, policies, grants and triggers. No production rows or
secrets are copied. Reference rows are produced by the original clean install;
tenant/test identities remain in `supabase/seed.sql`.

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
the manifest-owned baseline through `20260906140000` and its reference seed,
records all 111 covered migration versions from the frozen source manifest,
applies the remaining forward migrations, and runs `supabase/seed.sql`.
Scheduled cron execution is disabled in this disposable local project before
installation so no scheduled external calls can run.

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
- Files at or below the baseline version are recoverable from pinned Git
  objects with SHA-256 verification. They are absent from the active migration
  directory. Their exact versions/names remain in the new database ledger.
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

## Existing local database upgrades and historical SQL

Never apply the schema snapshot over an existing database. The supported
starting contract remains the original baseline through `20260805230000`
and its covered ledger. Upgrade an explicitly selected local Docker database:

```bash
python3 automation/baseline.py upgrade-local --database-url \
  'postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable'
```

This reconstructs the frozen SQL in a temporary workspace and uses the normal
Supabase migration engine in that complete workspace. Supabase CLI requires
local files for recorded versions, so running `supabase migration up` directly
against the contracted source directory is unsupported; the wrapper reconstructs
the recorded inputs without executing them again. It retains the ledger and executes only
missing versions. Before the order-symbol contract it runs the existing
owner-only batch backfill in separate transactions until no rows remain.
It refuses remote URLs, local ports not published by a Festapp PostgreSQL
container and ledgers older than the supported starting contract. This command
is for local development; production upgrades keep their separate release gates.

Recover source or the full legacy email rehearsal kit without copying it back
into active source directories:

```bash
python3 automation/baseline.py historical-kit --email .codex-local/historical-sql
EMAIL_LOCAL_REHEARSAL=1 bash automation/email-delivery/rehearse-local.sh
```

Recovery uses only the exact Git commits and hashes in
[`automation/historical-sql-manifest.json`](../../automation/historical-sql-manifest.json).
It verifies every input before writing and refuses conflicting files. The email
fixture is pinned before the later order-symbol/sequence schema changes, so it
still tests the original legacy cutover, IDs, receipts and retry quarantine.
No network fallback is used. A shallow clone must first acquire the named Git
objects; full repository history already contains them. Keep private local
recovery evidence outside source control.

For a read-only deterministic comparison of two explicitly prepared disposable
instances on the same PostgreSQL major:

```bash
python3 automation/check_baseline_parity.py \
  --left supabase_db_festapp-size-cleanup-pg15 \
  --right supabase_db_festapp-size-cleanup-pg15-b \
  --report .codex-local/baseline-parity.json
```

The check includes the full catalog dump, application sequence values and the
manifest's reference rows. It excludes only migration bookkeeping, which is
verified separately by a no-op `supabase migration up`. PG15 and PG17 must be
compared independently. See the [cleanup evidence](../plans/repository-size-cleanup-RESULT-2026-10-21.md)
for the measured baseline parity and supported upgrade results.
