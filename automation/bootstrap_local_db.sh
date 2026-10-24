#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOCAL_WORKDIR="$SCRIPT_DIR/local_db"
readonly LOCAL_PROJECT_ID="festapp-db-tests-pg15"
readonly DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable"
if [[ "${1-}" == "--stop" ]]; then
  supabase stop --project-id "$LOCAL_PROJECT_ID" --no-backup
  exit 0
fi

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

echo "Rebuilding isolated Festapp test database on 127.0.0.1:55432..."
supabase stop --project-id "$LOCAL_PROJECT_ID" --no-backup >/dev/null 2>&1 || true
supabase db start --workdir "$LOCAL_WORKDIR" >/dev/null

# Local installation must never execute scheduled external production calls.
docker exec -e PGPASSWORD=postgres "supabase_db_$LOCAL_PROJECT_ID" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER SYSTEM SET cron.launch_active_jobs = off'
docker exec -e PGPASSWORD=postgres "supabase_db_$LOCAL_PROJECT_ID" psql -X -U supabase_admin -d postgres -Atqc 'SELECT pg_reload_conf()' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$BASELINE_BOOTSTRAP" -f "$BASELINE_FILE" -f "$BASELINE_SEED" >/dev/null
python3 "$PROJECT_ROOT/automation/baseline.py" ledger-sql | psql "$DATABASE_URL" -v ON_ERROR_STOP=1 >/dev/null

# The baseline owns every version through BASELINE_VERSION. Only genuinely new,
# forward migrations are executed here.
python3 "$PROJECT_ROOT/automation/baseline.py" upgrade-local --database-url "$DATABASE_URL" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$PROJECT_ROOT/supabase/seed.sql" >/dev/null

echo "Local Festapp database is ready."
echo "DATABASE_URL=$DATABASE_URL"
