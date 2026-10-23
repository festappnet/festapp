#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOCAL_WORKDIR="${FESTAPP_LOCAL_DB_WORKDIR:-$SCRIPT_DIR/local_db}"
readonly LOCAL_PROJECT_ID="${FESTAPP_LOCAL_DB_PROJECT_ID:-festapp-db-tests-pg15}"
readonly LOCAL_DB_PORT="${FESTAPP_LOCAL_DB_PORT:-55432}"
[[ "$LOCAL_DB_PORT" =~ ^[0-9]+$ ]] || { echo "Invalid local DB port" >&2; exit 1; }
readonly DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:$LOCAL_DB_PORT/postgres?sslmode=disable"
# Local extension functions are owned by supabase_admin. The baseline still
# restores as postgres; forward migrations use the local extension-owning admin.
readonly MIGRATION_DATABASE_URL="postgresql://supabase_admin:postgres@127.0.0.1:$LOCAL_DB_PORT/postgres?sslmode=disable"
readonly BASELINE_VERSION="$(python3 "$PROJECT_ROOT/automation/baseline.py" field coveredThrough)"
readonly BASELINE_FILE="$(python3 "$PROJECT_ROOT/automation/baseline.py" field schema)"
readonly BASELINE_BOOTSTRAP="$(python3 "$PROJECT_ROOT/automation/baseline.py" field bootstrap)"
readonly BASELINE_SEED="$(python3 "$PROJECT_ROOT/automation/baseline.py" field referenceSeed)"
readonly MIGRATIONS_DIR="$PROJECT_ROOT/supabase/migrations"

for command in supabase psql; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: required command '$command' is not installed." >&2
    exit 1
  fi
done

if [[ "${1-}" == "--stop" ]]; then
  supabase stop --project-id "$LOCAL_PROJECT_ID" --no-backup
  exit 0
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "ERROR: missing local database baseline: $BASELINE_FILE" >&2
  exit 1
fi

duplicate_versions="$({
  find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \;
} | awk -F_ '/^[0-9]{14}_/ { count[$1]++ } END { for (version in count) if (count[version] > 1) print version }' | sort)"
if [[ -n "$duplicate_versions" ]]; then
  echo "ERROR: duplicate Supabase migration versions:" >&2
  echo "$duplicate_versions" >&2
  exit 1
fi

echo "Rebuilding isolated Festapp test database on 127.0.0.1:$LOCAL_DB_PORT..."
supabase stop --project-id "$LOCAL_PROJECT_ID" --no-backup >/dev/null 2>&1 || true
supabase db start --workdir "$LOCAL_WORKDIR" >/dev/null

# Local installation must never execute scheduled external production calls.
docker exec -e PGPASSWORD=postgres "supabase_db_$LOCAL_PROJECT_ID" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER SYSTEM SET cron.launch_active_jobs = off'
docker exec -e PGPASSWORD=postgres "supabase_db_$LOCAL_PROJECT_ID" psql -X -U supabase_admin -d postgres -Atqc 'SELECT pg_reload_conf()' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$BASELINE_BOOTSTRAP" -f "$BASELINE_FILE" -f "$BASELINE_SEED" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/local_db/reference_tenants.sql" >/dev/null
python3 "$PROJECT_ROOT/automation/baseline.py" ledger-sql | psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >/dev/null

# The baseline owns every version through BASELINE_VERSION. Only genuinely new,
# forward migrations are executed here.
python3 "$PROJECT_ROOT/automation/baseline.py" upgrade-local --database-url "$MIGRATION_DATABASE_URL" >/dev/null
# Match production's application owner while the extension-owning local admin
# remains responsible for extension setup. Tests deliberately use postgres as
# the operator, and SET ROLE for actual API permission assertions.
psql "$MIGRATION_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
GRANT ALL ON ALL TABLES IN SCHEMA public,eshop TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public,eshop TO postgres;
SELECT format('ALTER FUNCTION %s OWNER TO postgres',p.oid::regprocedure)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind IN ('f','w')
AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
\gexec
SQL
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$PROJECT_ROOT/supabase/seed.sql" >/dev/null
# Demo contract tests use the same versioned synthetic fixtures as the application.
# This bootstrap is pinned to the disposable localhost database above.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v demo_organization=1 \
  -f "$PROJECT_ROOT/automation/seed_demo_occasions.sql" >/dev/null

# Persist the disposable identity for guarded mutation/concurrency test runners.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v disposable_project="$LOCAL_PROJECT_ID" <<'SQL' >/dev/null
CREATE SCHEMA IF NOT EXISTS festapp_test_support;
CREATE TABLE IF NOT EXISTS festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY CHECK(singleton),project text NOT NULL);
INSERT INTO festapp_test_support.disposable_environment(singleton,project) VALUES(true,:'disposable_project') ON CONFLICT(singleton) DO UPDATE SET project=EXCLUDED.project;
SQL

echo "Local Festapp database is ready."
echo "DATABASE_URL=$DATABASE_URL"
