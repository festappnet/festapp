#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOCAL_WORKDIR="${FESTAPP_LOCAL_DB_WORKDIR:-$SCRIPT_DIR/local_db}"
readonly LOCAL_PROJECT_ID="${FESTAPP_LOCAL_DB_PROJECT_ID:-festapp-db-tests-pg15}"
readonly LOCAL_DB_PORT="${FESTAPP_LOCAL_DB_PORT:-55432}"
[[ "$LOCAL_DB_PORT" =~ ^[0-9]+$ ]] || { echo "Invalid local DB port" >&2; exit 1; }
readonly DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:$LOCAL_DB_PORT/postgres?sslmode=disable"
readonly BASELINE_VERSION="20260805230000"
readonly BASELINE_FILE="$PROJECT_ROOT/supabase/baseline/${BASELINE_VERSION}_production_schema.sql"
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

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE SCHEMA IF NOT EXISTS eshop;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- Supabase's local image starts with broad defaults. Clear them before restore
-- so pg_dump's explicit grants recreate production ACLs rather than adding to
-- the local defaults.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
SQL

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$BASELINE_FILE" >/dev/null

temporary_dir="$(mktemp -d /tmp/festapp-local-db.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
baseline_rows="$temporary_dir/baseline_migrations.tsv"

while IFS= read -r migration_file; do
  filename="$(basename "$migration_file" .sql)"
  version="${filename%%_*}"
  if [[ "$version" =~ ^[0-9]{14}$ ]] && [[ "$version" < "$BASELINE_VERSION" || "$version" == "$BASELINE_VERSION" ]]; then
    printf '%s\t%s\n' "$version" "${filename#*_}" >> "$baseline_rows"
  fi
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -c "CREATE SCHEMA IF NOT EXISTS supabase_migrations; CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY, statements text[], name text);" \
  -c "CREATE TEMP TABLE baseline_versions(version text,name text);" \
  -c "\\copy baseline_versions FROM '$baseline_rows'" \
  -c "INSERT INTO supabase_migrations.schema_migrations(version,name,statements) SELECT version,name,ARRAY[]::text[] FROM baseline_versions ON CONFLICT (version) DO NOTHING;" \
  >/dev/null

# The baseline owns every version through BASELINE_VERSION. Only genuinely new,
# forward migrations are executed here.
supabase migration up --db-url "$DATABASE_URL" --include-all >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$PROJECT_ROOT/supabase/seed.sql" >/dev/null

# Persist the disposable identity for guarded mutation/concurrency test runners.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v disposable_project="$LOCAL_PROJECT_ID" <<'SQL' >/dev/null
CREATE SCHEMA IF NOT EXISTS festapp_test_support;
CREATE TABLE IF NOT EXISTS festapp_test_support.disposable_environment(singleton boolean PRIMARY KEY CHECK(singleton),project text NOT NULL);
INSERT INTO festapp_test_support.disposable_environment(singleton,project) VALUES(true,:'disposable_project') ON CONFLICT(singleton) DO UPDATE SET project=EXCLUDED.project;
SQL

echo "Local Festapp database is ready."
echo "DATABASE_URL=$DATABASE_URL"
