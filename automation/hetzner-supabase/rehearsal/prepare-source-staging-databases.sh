#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly EXPECTED_POSTGRES_MAJOR="17"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_FILE="${FESTAPP_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly STAGE_SUFFIX="${FESTAPP_STAGE_DATABASE_SUFFIX:-}"
readonly REQUESTED_SOURCES="${FESTAPP_STAGE_SOURCES:-}"
readonly ACK="${FESTAPP_REHEARSAL_ACK:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$REGISTRY_FILE" ]] || fail "missing source registry: $REGISTRY_FILE"
jq -e '.version == 1 and (.sources | type == "array" and length > 0)' "$REGISTRY_FILE" >/dev/null ||
  fail "invalid source registry"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "invalid isolated rehearsal database name"
[[ -z "$STAGE_SUFFIX" || "$STAGE_SUFFIX" =~ ^[0-9]{14}$ ]] || fail "invalid staging database suffix"
[[ "$ACK" == "prepare-empty-source-staging-databases" ||
   "$ACK" == "prepare-additive-source-staging-databases" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK to an approved source-staging mode"
[[ "$(id -u)" == "0" ]] || fail "run as root on the isolated rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
[[ -f "$COMPOSE_DIR/docker-compose.yml" ]] || fail "missing pinned Supabase runtime"

mapfile -t REGISTRY_SOURCES < <(jq -r '.sources[].alias' "$REGISTRY_FILE")
if [[ -n "$REQUESTED_SOURCES" ]]; then
  IFS=',' read -r -a SOURCES <<<"$REQUESTED_SOURCES"
else
  SOURCES=("${REGISTRY_SOURCES[@]}")
fi
[[ "${#SOURCES[@]}" -gt 0 ]] || fail "no staging sources selected"

declare -A SEEN=()
DATABASES=()
for source in "${SOURCES[@]}"; do
  [[ "$source" =~ ^[a-z][a-z0-9_]*$ ]] || fail "invalid source alias: $source"
  [[ -z "${SEEN[$source]:-}" ]] || fail "duplicate source alias: $source"
  SEEN[$source]=1
  jq -e --arg source "$source" '.sources | any(.alias == $source)' "$REGISTRY_FILE" >/dev/null ||
    fail "source is not registered: $source"
  DATABASES+=("festapp_stage_${source}${STAGE_SUFFIX:+_$STAGE_SUFFIX}")
done

cd "$COMPOSE_DIR"
docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }

readonly POSTGRES_MAJOR="$(psql_main -Atqc "SELECT split_part(current_setting('server_version'),'.',1)")"
[[ "$POSTGRES_MAJOR" == "$EXPECTED_POSTGRES_MAJOR" ]] || fail "unexpected PostgreSQL major: $POSTGRES_MAJOR"
[[ "$(psql_main -Atqc "SELECT to_regnamespace('festapp_merge') IS NOT NULL")" == "t" ]] ||
  fail "canonical merge foundation is missing"

existing_stage_databases=0
for database in "${DATABASES[@]}"; do
  existing_stage_databases="$((existing_stage_databases + $(psql_main -Atqc "SELECT count(*) FROM pg_database WHERE datname='$database'")))"
done
[[ "$existing_stage_databases" == "0" ]] || fail "one or more selected staging databases already exist"

if [[ "$ACK" == "prepare-empty-source-staging-databases" ]]; then
  [[ "${#SOURCES[@]}" == "${#REGISTRY_SOURCES[@]}" ]] || fail "initial staging must select every registered source"
  [[ "$(printf '%s\n' "${SOURCES[@]}" | sort)" == "$(printf '%s\n' "${REGISTRY_SOURCES[@]}" | sort)" ]] ||
    fail "initial staging source set differs from registry"
  readonly EMPTY_STATE="$(psql_main -Atqc "SELECT concat_ws('|',(SELECT count(*) FROM festapp_merge.import_runs),(SELECT count(*) FROM auth.users),(SELECT count(*) FROM storage.objects))")"
  [[ "$EMPTY_STATE" == "0|0|0" ]] || fail "target is not an empty canonical staging foundation ($EMPTY_STATE)"
else
  [[ -n "$STAGE_SUFFIX" ]] || fail "additive staging requires a fresh timestamped database suffix"
  for source in "${SOURCES[@]}"; do
    [[ "$(jq -r --arg source "$source" '.sources[] | select(.alias == $source) | .role' "$REGISTRY_FILE")" == "merge-source" ]] ||
      fail "additive staging is restricted to registered merge sources: $source"
    [[ "$(psql_main -Atqc "SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='$source'")" == "0" ]] ||
      fail "source already has an import run: $source"
  done
  expected_predecessors="$(for source in "${REGISTRY_SOURCES[@]}"; do [[ -n "${SEEN[$source]:-}" ]] || echo "$source:validated:1"; done | sort | paste -sd, -)"
  actual_predecessors="$(psql_main -Atqc "SELECT coalesce(string_agg(source_alias||':'||status||':'||runs,',' ORDER BY source_alias),'') FROM (SELECT source_alias,status,count(*) runs FROM festapp_merge.import_runs GROUP BY source_alias,status) x")"
  [[ "$actual_predecessors" == "$expected_predecessors" ]] ||
    fail "existing canonical imports are not the exact validated predecessor set ($actual_predecessors)"
fi

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/source-staging-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

for database in "${DATABASES[@]}"; do
  psql_main -v database="$database" <<'SQL'
SELECT format('CREATE DATABASE %I TEMPLATE template0', :'database') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC, anon, authenticated, service_role', :'database') \gexec
SQL
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$database" <<'SQL'
BEGIN;
CREATE SCHEMA extensions AUTHORIZATION postgres;
CREATE SCHEMA vault AUTHORIZATION postgres;
-- Source DDL may reference auth.uid(). Raw staging gets only this locked,
-- always-NULL compatibility stub; API roles cannot execute it.
CREATE SCHEMA auth AUTHORIZATION postgres;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SET search_path = '' AS 'SELECT NULL::uuid';
CREATE EXTENSION http WITH SCHEMA extensions;
CREATE EXTENSION moddatetime WITH SCHEMA extensions;
CREATE EXTENSION pg_net WITH SCHEMA extensions;
CREATE EXTENSION pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION pgaudit WITH SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION pgjwt WITH SCHEMA extensions;
CREATE EXTENSION unaccent WITH SCHEMA extensions;
CREATE EXTENSION "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION supabase_vault WITH SCHEMA vault;
SELECT format('REVOKE ALL ON DATABASE %I FROM anon, authenticated, service_role', current_database()) \gexec
REVOKE ALL ON SCHEMA public, extensions, vault, auth FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION auth.uid() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
SQL
done

result='[]'
for database in "${DATABASES[@]}"; do
  allow_connections="$(psql_main -Atqc "SELECT datallowconn FROM pg_database WHERE datname='$database'")"
  result="$(jq -cn --argjson prior "$result" --arg database "$database" --arg allow "$allow_connections" '$prior + [{database:$database,allow_connections:($allow == "t")}]')"
done
jq -n --arg mode "$ACK" --arg registry_sha256 "$(shasum -a 256 "$REGISTRY_FILE" | awk '{print $1}')" \
  --argjson sources "$(for source in "${SOURCES[@]}"; do jq -cn --arg alias "$source" --arg project_ref "$(jq -r --arg source "$source" '.sources[]|select(.alias==$source)|.project_ref' "$REGISTRY_FILE")" '{alias:$alias,project_ref:$project_ref}'; done | jq -s .)" \
  --argjson databases "$result" '{mode:$mode,registry_sha256:$registry_sha256,sources:$sources,databases:$databases,deleted_databases:0}' >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Locked empty source staging databases prepared: ${SOURCES[*]}"
echo "Evidence: $RUN_DIR"
