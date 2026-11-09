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

The command prepares or reuses a content-verified immutable PostgreSQL 15 base,
then ordinary test commands acquire their own clean clone. The canonical owner is
`automation/local_db/runtime.py`; it never reads `.env.local` or guesses another
session's database. Default dedicated cluster: `festapp-sql-runtime`, loopback
port 55542. The baseline/ledger and full supported history remain authoritative.
Use `--upgrade` for an actual cold full replay, `--status` for leases/cache state,
`--prune` for owned abandoned runs, and `--stop` to stop only an unleased runtime.

## Running tests

```bash
./automation/test_all.sh db
node web_client/scripts/run_db_tests.js database/tests/companion_contract_test.sql
python3 automation/local_db/runtime.py exec -- node --test web_client/tests/database/retired_waitlist_registry.test.js
./automation/test_client.sh
```

No fixed behavior database URL is required: the wrappers acquire a unique
workspace and close their pools before deleting it. An explicit marked local
fixture remains supported for integration or supported-upgrade work. Empty SQL
filters fail; diagnostic retries never erase the first-attempt verdict.

First resolve root dependencies with `fvm flutter pub get`, then run
`fvm dart pub get` inside `packages/festapp_core`. For a partial run use
`./automation/test_client.sh core` or `./automation/test_client.sh flutter`.

Each SQL test runs in a transaction and rolls back its fixture data. The runner
may reset sequences, which is why it must target the dedicated local database,
never production.

The complete image Worker integration suite also needs local GoTrue and
PostgREST connected to that same marked disposable database. Supply its
`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `DATABASE_URL` before running
`pnpm --dir workers/image-worker run test:integration`. Missing or remote
fixtures fail instead of silently skipping. The suite runs the actual Worker
in workerd with local R2, native Images processing and a real rate limiter.
Backend requests are routed to local Auth/REST; Cloudflare cache-purge requests
invalidate the local Cache API. No production Worker, R2 bucket or user is used.

Web test files run sequentially because their disposable database cleanup and
schema locks are shared. Each concurrency test still opens its own simultaneous
SQL connections to prove the transaction races.

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

`bootstrap_local_db.sh` delegates to the owned runtime on 127.0.0.1:55542.
Choose another owned project/port with `FESTAPP_LOCAL_DB_PROJECT_ID` and
`FESTAPP_LOCAL_DB_PORT`. Cron execution is disabled and pg_net's worker uses an
empty sink database. Unowned containers, non-loopback port mappings, mismatched
markers and live leases prevent reuse or shutdown. No command links a remote
project or runs `db push`; production is outside this workflow.

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
