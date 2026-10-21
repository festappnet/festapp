#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly EXPECTED_POSTGRES_MAJOR="17"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "${FESTAPP_REHEARSAL_ACK:-}" == "prepare-new-isolated-runtime-foundation" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=prepare-new-isolated-runtime-foundation"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "FESTAPP_REHEARSAL_DATABASE must be a new timestamped rehearsal database"
[[ "$(id -u)" == "0" ]] || fail "run as root on the isolated rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"

cd "$COMPOSE_DIR"
docker compose config -q
[[ "$(docker compose ps --status running --services | grep -x 'db' || true)" == "db" ]] ||
  fail "database service is not running"

psql_admin() {
  local database="$1"
  shift
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database" "$@"
}

readonly SOURCE_STATE="$(psql_admin postgres -Atqc "SELECT concat_ws('|',
  split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM auth.schema_migrations),
  (SELECT count(*) FROM storage.migrations),
  (SELECT count(*) FROM _realtime.schema_migrations),
  (SELECT count(*) FROM _realtime.tenants),
  (SELECT count(*) FROM _realtime.extensions),
  (SELECT count(*) FROM _realtime.feature_flags),
  (SELECT count(*) FROM realtime.schema_migrations),
  (SELECT count(*) FROM pg_database WHERE datname='$TARGET_DATABASE'))")"
[[ "$SOURCE_STATE" == "$EXPECTED_POSTGRES_MAJOR|76|61|31|1|1|0|72|0" ]] ||
  fail "runtime foundation source or target state is not approved ($SOURCE_STATE)"

psql_admin postgres -v target="$TARGET_DATABASE" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER postgres TEMPLATE template0', :'target') \gexec
SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC, anon, authenticated, service_role', :'target') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO postgres, supabase_admin, supabase_auth_admin, authenticator, supabase_realtime_admin, supabase_storage_admin, dashboard_user', :'target') \gexec
SQL

psql_admin "$TARGET_DATABASE" <<'SQL'
CREATE SCHEMA extensions AUTHORIZATION supabase_admin;
CREATE SCHEMA vault AUTHORIZATION supabase_admin;
CREATE EXTENSION dblink WITH SCHEMA public;
CREATE EXTENSION http WITH SCHEMA extensions;
CREATE EXTENSION moddatetime WITH SCHEMA extensions;
CREATE EXTENSION pg_net WITH SCHEMA extensions;
CREATE EXTENSION pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION pgaudit WITH SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION pgjwt WITH SCHEMA extensions;
CREATE EXTENSION postgres_fdw WITH SCHEMA extensions;
CREATE EXTENSION supabase_vault WITH SCHEMA vault;
CREATE EXTENSION unaccent WITH SCHEMA extensions;
CREATE EXTENSION "uuid-ossp" WITH SCHEMA extensions;
SQL

# Preserve the runtime ACLs as well as ownership. The canonical application
# baseline is applied by the deliberately non-superuser `postgres` role and
# relies on the same grants it has in the live Supabase runtime (notably on
# auth.users). Omitting ACLs creates a foundation that is not runtime-equivalent.
docker compose exec -T db pg_dump -U supabase_admin -d postgres --schema-only \
  --schema=auth --schema=storage --schema=realtime --schema=_realtime \
  --schema=supabase_functions --schema=graphql --schema=graphql_public | \
  psql_admin "$TARGET_DATABASE" >/dev/null

docker compose exec -T db pg_dump -U supabase_admin -d postgres --data-only --no-owner --no-acl \
  --table=auth.schema_migrations --table=storage.migrations \
  --table=_realtime.schema_migrations --table=_realtime.tenants \
  --table=_realtime.extensions --table=_realtime.feature_flags \
  --table=realtime.schema_migrations | \
  psql_admin "$TARGET_DATABASE" >/dev/null

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/isolated-target-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
psql_admin "$TARGET_DATABASE" -Atqc "SELECT jsonb_build_object(
  'database', current_database(),
  'postgres_major', split_part(current_setting('server_version'),'.',1),
  'auth_migrations', (SELECT count(*) FROM auth.schema_migrations),
  'storage_migrations', (SELECT count(*) FROM storage.migrations),
  'realtime_control_rows', (SELECT count(*) FROM _realtime.schema_migrations) +
    (SELECT count(*) FROM _realtime.tenants) + (SELECT count(*) FROM _realtime.extensions) +
    (SELECT count(*) FROM _realtime.feature_flags) + (SELECT count(*) FROM realtime.schema_migrations),
  'auth_users', (SELECT count(*) FROM auth.users),
  'storage_objects', (SELECT count(*) FROM storage.objects),
  'business_relations', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p','v','m','S')),
  'existing_databases_deleted', 0
)" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"

readonly RESULT="$(jq -r '[.postgres_major,.auth_migrations,.storage_migrations,.realtime_control_rows,.auth_users,.storage_objects,.business_relations,.existing_databases_deleted]|join("|")' "$RUN_DIR/result.json")"
[[ "$RESULT" == "$EXPECTED_POSTGRES_MAJOR|76|61|105|0|0|0|0" ]] ||
  fail "isolated runtime foundation validation failed ($RESULT)"

echo "New isolated Supabase runtime database prepared without application data."
echo "Evidence: $RUN_DIR"
