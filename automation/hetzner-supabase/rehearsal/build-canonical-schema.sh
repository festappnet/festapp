#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly EXPECTED_POSTGRES_MAJOR="17"
readonly BASELINE_VERSION="20260805230000"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly BASELINE_FILE="$PROJECT_ROOT/supabase/baseline/${BASELINE_VERSION}_production_schema.sql"
readonly MIGRATIONS_DIR="$PROJECT_ROOT/supabase/migrations"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

readonly ACK="${FESTAPP_REHEARSAL_ACK:-}"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "invalid isolated rehearsal database name"
[[ "$ACK" == "canonical-schema-only" || "$ACK" == "resume-after-baseline-ledger-fix" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=canonical-schema-only"
[[ "$(id -u)" == "0" ]] || fail "run as root on the isolated rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "refusing host $(hostname -s); expected $EXPECTED_HOSTNAME"
[[ -f "$BASELINE_FILE" ]] || fail "missing canonical baseline $BASELINE_FILE"
[[ -d "$MIGRATIONS_DIR" ]] || fail "missing migrations directory $MIGRATIONS_DIR"
[[ -f "$COMPOSE_DIR/docker-compose.yml" ]] || fail "missing pinned Supabase Compose runtime"
[[ -f "$COMPOSE_DIR/docker-compose.festapp.yml" ]] || fail "missing Festapp Compose override"

cd "$COMPOSE_DIR"
docker compose config -q
[[ "$(docker compose ps --status running --services | grep -x 'db' || true)" == "db" ]] ||
  fail "database service is not running"

psql_rehearsal() {
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"
}

readonly POSTGRES_MAJOR="$(psql_rehearsal -Atqc "SHOW server_version" | cut -d. -f1)"
[[ "$POSTGRES_MAJOR" == "$EXPECTED_POSTGRES_MAJOR" ]] ||
  fail "PostgreSQL major $POSTGRES_MAJOR does not match approved target $EXPECTED_POSTGRES_MAJOR"

readonly BUSINESS_RELATIONS="$(psql_rehearsal -Atqc \
  "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p','v','m','S')")"
APPLY_BASELINE=true
if [[ "$ACK" == "canonical-schema-only" ]]; then
  [[ "$BUSINESS_RELATIONS" == "0" ]] ||
    fail "target is not an empty business-schema foundation ($BUSINESS_RELATIONS relations found)"
else
  readonly RESUME_STATE="$(psql_rehearsal -Atqc "SELECT concat_ws('|',
    (SELECT count(*) FROM supabase_migrations.schema_migrations),
    (SELECT count(*) FROM auth.users),
    (SELECT count(*) FROM storage.objects),
    to_regclass('public.organizations') IS NOT NULL,
    to_regclass('public.user_reset_token') IS NOT NULL,
    to_regclass('eshop.tickets') IS NOT NULL,
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S')),
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='eshop' AND c.relkind IN ('r','p','v','m','S'))
  )")"
  [[ "$RESUME_STATE" == "0|0|0|t|t|t|113|38" ]] ||
    fail "target does not match the one approved post-baseline resume state"
  APPLY_BASELINE=false
fi

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_ID="canonical-schema-$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/$RUN_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"

docker compose exec -T db pg_dump -U postgres -d "$TARGET_DATABASE" --schema-only --no-owner \
  >"$RUN_DIR/pre-apply-schema.sql"
chmod 0600 "$RUN_DIR/pre-apply-schema.sql"

if [[ "$APPLY_BASELINE" == true ]]; then
psql_rehearsal <<'SQL'
CREATE SCHEMA IF NOT EXISTS eshop;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
SQL

if [[ "$TARGET_DATABASE" == "postgres" ]]; then
  psql_rehearsal -qc "CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog"
else
  # pg_cron is configured to read jobs only from the runtime `postgres`
  # database. An isolated same-cluster rehearsal must not schedule effects, but
  # canonical functions in the baseline still need the extension-owned
  # `cron.schedule`/`cron.unschedule` signatures to compile. These inert stubs
  # are an operational compatibility exception to the application's
  # public-schema-only function rule; no application RPC is exposed here.
  psql_rehearsal <<'SQL'
CREATE SCHEMA IF NOT EXISTS cron AUTHORIZATION postgres;
CREATE OR REPLACE FUNCTION cron.schedule(text, text, text) RETURNS bigint
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'pg_cron is disabled in isolated rehearsal databases'; END $$;
CREATE OR REPLACE FUNCTION cron.unschedule(text) RETURNS boolean
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'pg_cron is disabled in isolated rehearsal databases'; END $$;
REVOKE ALL ON SCHEMA cron FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA cron FROM PUBLIC, anon, authenticated, service_role;
SQL
fi

psql_rehearsal <"$BASELINE_FILE"
psql_rehearsal -qc \
  "CREATE SCHEMA IF NOT EXISTS supabase_migrations; CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY, statements text[], name text);"
fi

while IFS= read -r migration_file; do
  filename="$(basename "$migration_file" .sql)"
  version="${filename%%_*}"
  name="${filename#*_}"
  [[ "$version" =~ ^[0-9]{14}$ ]] || continue

  if [[ "$version" > "$BASELINE_VERSION" ]]; then
    psql_rehearsal <"$migration_file"
  fi
  psql_rehearsal -v version="$version" -v name="$name" -q <<'SQL'
INSERT INTO supabase_migrations.schema_migrations(version, statements, name)
VALUES (:'version', ARRAY[]::text[], :'name')
ON CONFLICT (version) DO NOTHING;
SQL
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

psql_rehearsal -Atqc "SELECT jsonb_build_object(
  'postgres_version', current_setting('server_version'),
  'migration_count', (SELECT count(*) FROM supabase_migrations.schema_migrations),
  'public_relations', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S')),
  'eshop_relations', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='eshop' AND c.relkind IN ('r','p','v','m','S')),
  'auth_users', (SELECT count(*) FROM auth.users),
  'storage_objects', (SELECT count(*) FROM storage.objects)
)" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
sha256sum "$BASELINE_FILE" >"$RUN_DIR/baseline.sha256"
chmod 0600 "$RUN_DIR/baseline.sha256"

echo "Canonical schema baseline built without source data."
echo "Evidence: $RUN_DIR"
