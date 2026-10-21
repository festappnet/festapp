#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_FILE="${FESTAPP_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly STAGE_SUFFIX="${FESTAPP_STAGE_DATABASE_SUFFIX:-}"
readonly REQUESTED_SOURCES="${FESTAPP_STAGE_SOURCES:-}"
readonly ACK="${FESTAPP_REHEARSAL_ACK:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$REGISTRY_FILE" ]] || fail "missing source registry"
jq -e '.version == 1 and (.sources | type == "array" and length > 0)' "$REGISTRY_FILE" >/dev/null || fail "invalid source registry"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ -z "$STAGE_SUFFIX" || "$STAGE_SUFFIX" =~ ^[0-9]{14}$ ]] || fail "invalid staging database suffix"
[[ "$ACK" == "prepare-read-only-foreign-staging-bridge" ||
   "$ACK" == "prepare-additive-read-only-foreign-staging-bridge" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK to an approved foreign-staging mode"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run as root on the approved rehearsal host"

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
  [[ "$source" =~ ^[a-z][a-z0-9_]{0,19}$ ]] || fail "invalid source alias: $source"
  [[ -z "${SEEN[$source]:-}" ]] || fail "duplicate source alias: $source"
  SEEN[$source]=1
  jq -e --arg source "$source" '.sources | any(.alias == $source)' "$REGISTRY_FILE" >/dev/null || fail "unregistered source: $source"
  DATABASES+=("festapp_stage_${source}${STAGE_SUFFIX:+_$STAGE_SUFFIX}")
done

if [[ "$ACK" == "prepare-additive-read-only-foreign-staging-bridge" ]]; then
  [[ -n "$STAGE_SUFFIX" && "${#SOURCES[@]}" == "1" ]] || fail "additive bridge requires one source and a fresh timestamped suffix"
  readonly READER_ROLE="festapp_stage_reader_${SOURCES[0]}_$STAGE_SUFFIX"
else
  readonly READER_ROLE="festapp_stage_reader${STAGE_SUFFIX:+_$STAGE_SUFFIX}"
fi

cd "$COMPOSE_DIR"
docker compose config -q
psql_db() { local database="$1"; shift; docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$database" "$@"; }

[[ "$(psql_db "$TARGET_DATABASE" -Atqc "SELECT split_part(current_setting('server_version'),'.',1)")" == "17" ]] || fail "canonical target is not PostgreSQL 17"
selected_servers_sql="$(printf "'festapp_stage_%s'," "${SOURCES[@]}" | sed 's/,$//')"
selected_schemas_sql="$(for source in "${SOURCES[@]}"; do printf "'festapp_stage_%s_public','festapp_stage_%s_eshop','festapp_stage_%s_managed'," "$source" "$source" "$source"; done | sed 's/,$//')"
readonly PREEXISTING_TOPOLOGY="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',(SELECT coalesce(string_agg(srvname,',' ORDER BY srvname),'') FROM pg_foreign_server WHERE srvname NOT IN ($selected_servers_sql)),(SELECT coalesce(string_agg(nspname,',' ORDER BY nspname),'') FROM pg_namespace WHERE nspname LIKE 'festapp_stage_%' AND nspname NOT IN ($selected_schemas_sql)),(SELECT coalesce(string_agg(srvname,',' ORDER BY srvname),'') FROM pg_user_mappings WHERE srvname NOT IN ($selected_servers_sql)))")"
for source in "${SOURCES[@]}"; do
  [[ "$(psql_db "$TARGET_DATABASE" -Atqc "SELECT count(*) FROM pg_foreign_server WHERE srvname='festapp_stage_$source'")" == "0" ]] || fail "foreign server already exists: $source"
  [[ "$(psql_db "$TARGET_DATABASE" -Atqc "SELECT count(*) FROM pg_namespace WHERE nspname IN ('festapp_stage_${source}_public','festapp_stage_${source}_eshop','festapp_stage_${source}_managed')")" == "0" ]] || fail "foreign staging schemas already exist: $source"
done

if [[ "$ACK" == "prepare-read-only-foreign-staging-bridge" ]]; then
  [[ "${#SOURCES[@]}" == "${#REGISTRY_SOURCES[@]}" ]] || fail "initial bridge must select every registered source"
  [[ "$(printf '%s\n' "${SOURCES[@]}" | sort)" == "$(printf '%s\n' "${REGISTRY_SOURCES[@]}" | sort)" ]] || fail "initial bridge source set differs from registry"
  [[ "$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',(SELECT count(*) FROM festapp_merge.import_runs),(SELECT count(*) FROM auth.users),(SELECT count(*) FROM storage.objects),(SELECT count(*) FROM pg_foreign_server WHERE srvname LIKE 'festapp_stage_%'))")" == "0|0|0|0" ]] || fail "canonical target is not an empty bridge foundation"
else
  for source in "${SOURCES[@]}"; do
    [[ "$(jq -r --arg source "$source" '.sources[] | select(.alias == $source) | .role' "$REGISTRY_FILE")" == "merge-source" ]] || fail "additive bridge is restricted to merge sources"
    [[ "$(psql_db "$TARGET_DATABASE" -Atqc "SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='$source'")" == "0" ]] || fail "source already imported: $source"
  done
  expected_predecessors="$(for source in "${REGISTRY_SOURCES[@]}"; do [[ -n "${SEEN[$source]:-}" ]] || echo "$source:validated:1"; done | sort | paste -sd, -)"
  actual_predecessors="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT coalesce(string_agg(source_alias||':'||status||':'||runs,',' ORDER BY source_alias),'') FROM (SELECT source_alias,status,count(*) runs FROM festapp_merge.import_runs GROUP BY source_alias,status) x")"
  [[ "$actual_predecessors" == "$expected_predecessors" ]] || fail "canonical predecessor imports are not the exact validated set ($actual_predecessors)"
fi

for i in "${!SOURCES[@]}"; do
  source="${SOURCES[$i]}"
  database="${DATABASES[$i]}"
  project_ref="$(jq -r --arg source "$source" '.sources[]|select(.alias==$source)|.project_ref' "$REGISTRY_FILE")"
  state="$(psql_db "$database" -Atqc "SELECT concat_ws('|',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','eshop') AND c.relkind IN ('r','p')),(SELECT count(*) FROM festapp_managed_source.rows),(SELECT count(*) FROM festapp_managed_source.provenance),(SELECT source_alias FROM festapp_managed_source.provenance),(SELECT source_project_ref FROM festapp_managed_source.provenance),(SELECT managed_rows FROM festapp_managed_source.provenance),(SELECT raw_managed_delta_seconds BETWEEN 0 AND 900 FROM festapp_managed_source.provenance),(SELECT raw_artifact_sha256 ~ '^[0-9a-f]{64}$' AND raw_manifest_sha256 ~ '^[0-9a-f]{64}$' AND raw_schema_sha256 ~ '^[0-9a-f]{64}$' AND managed_artifact_sha256 ~ '^[0-9a-f]{64}$' AND managed_manifest_sha256 ~ '^[0-9a-f]{64}$' FROM festapp_managed_source.provenance))")"
  app_tables="${state%%|*}"
  remainder="${state#*|}"
  managed_rows="${remainder%%|*}"
  expected_tail="$managed_rows|1|$source|$project_ref|$managed_rows|t|t"
  [[ "$app_tables" =~ ^[1-9][0-9]*$ && "$remainder" == "$expected_tail" ]] || fail "$source staging provenance/state mismatch ($state)"
done

reader_password="$(openssl rand -base64 36 | tr -d '\n')"
reader_exists="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT count(*) FROM pg_roles WHERE rolname='$READER_ROLE'")"
if [[ "$reader_exists" == "0" ]]; then
  psql_db "$TARGET_DATABASE" <<SQL
CREATE ROLE $READER_ROLE LOGIN PASSWORD '$reader_password'
  VALID UNTIL '$(date -u -d '+24 hours' '+%Y-%m-%d %H:%M:%S+00')'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
SQL
else
  reader_state="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolinherit,rolreplication,rolbypassrls) FROM pg_roles WHERE rolname='$READER_ROLE'")"
  [[ "$reader_state" == "t|f|f|f|f|f|f" ]] || fail "existing staging reader has unsafe attributes ($reader_state)"
  psql_db "$TARGET_DATABASE" -c "ALTER ROLE $READER_ROLE PASSWORD '$reader_password' VALID UNTIL '$(date -u -d '+24 hours' '+%Y-%m-%d %H:%M:%S+00')'"
fi

for database in "${DATABASES[@]}"; do
  psql_db "$database" <<SQL
GRANT CONNECT ON DATABASE $database TO $READER_ROLE;
GRANT USAGE ON SCHEMA public, eshop, festapp_managed_source TO $READER_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA public, eshop, festapp_managed_source TO $READER_ROLE;
SQL
done

sql_file="$(mktemp)"
trap 'rm -f "$sql_file"' EXIT
{
  echo 'BEGIN;'
  echo 'CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA extensions;'
  for i in "${!SOURCES[@]}"; do
    source="${SOURCES[$i]}"
    database="${DATABASES[$i]}"
    echo "CREATE SCHEMA festapp_stage_${source}_public AUTHORIZATION postgres;"
    echo "CREATE SCHEMA festapp_stage_${source}_eshop AUTHORIZATION postgres;"
    echo "CREATE SCHEMA festapp_stage_${source}_managed AUTHORIZATION postgres;"
    echo "REVOKE ALL ON SCHEMA festapp_stage_${source}_public,festapp_stage_${source}_eshop,festapp_stage_${source}_managed FROM PUBLIC,anon,authenticated,service_role;"
    # The FDW reaches another database in the same PostgreSQL container through
    # its Docker-network alias. This retains SCRAM password authentication while
    # avoiding coupling the offline migration path to the API pooler.
    echo "CREATE SERVER festapp_stage_${source} FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'db',port '5432',dbname '$database');"
    echo "CREATE USER MAPPING FOR postgres SERVER festapp_stage_${source} OPTIONS (user '$READER_ROLE',password '$reader_password');"
    echo "IMPORT FOREIGN SCHEMA public FROM SERVER festapp_stage_${source} INTO festapp_stage_${source}_public;"
    echo "IMPORT FOREIGN SCHEMA eshop FROM SERVER festapp_stage_${source} INTO festapp_stage_${source}_eshop;"
    echo "IMPORT FOREIGN SCHEMA festapp_managed_source LIMIT TO (rows,provenance) FROM SERVER festapp_stage_${source} INTO festapp_stage_${source}_managed;"
  done
  echo 'COMMIT;'
} >"$sql_file"
psql_db "$TARGET_DATABASE" -f - <"$sql_file"

readonly POSTEXISTING_TOPOLOGY="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',(SELECT coalesce(string_agg(srvname,',' ORDER BY srvname),'') FROM pg_foreign_server WHERE srvname NOT IN ($selected_servers_sql)),(SELECT coalesce(string_agg(nspname,',' ORDER BY nspname),'') FROM pg_namespace WHERE nspname LIKE 'festapp_stage_%' AND nspname NOT IN ($selected_schemas_sql)),(SELECT coalesce(string_agg(srvname,',' ORDER BY srvname),'') FROM pg_user_mappings WHERE srvname NOT IN ($selected_servers_sql)))")"
[[ "$POSTEXISTING_TOPOLOGY" == "$PREEXISTING_TOPOLOGY" ]] || fail "pre-existing FDW topology changed"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
run_dir="$EVIDENCE_ROOT/foreign-staging-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$run_dir"
source_results='[]'
for i in "${!SOURCES[@]}"; do
  source="${SOURCES[$i]}"
  database="${DATABASES[$i]}"
  project_ref="$(jq -r --arg source "$source" '.sources[]|select(.alias==$source)|.project_ref' "$REGISTRY_FILE")"
  source_counts="$(psql_db "$database" -Atqc "SELECT concat_ws('|',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p')),(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='eshop' AND c.relkind IN ('r','p')),(SELECT count(*) FROM festapp_managed_source.rows))")"
  target_counts="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema='festapp_stage_${source}_public'),(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema='festapp_stage_${source}_eshop'),(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema='festapp_stage_${source}_managed'),(SELECT count(*) FROM festapp_stage_${source}_managed.rows),(SELECT count(*) FROM festapp_stage_${source}_managed.provenance WHERE source_alias='$source' AND source_project_ref='$project_ref'),(SELECT count(*) FROM pg_user_mappings WHERE srvname='festapp_stage_$source'),(SELECT has_schema_privilege('anon','festapp_stage_${source}_public','USAGE') OR has_schema_privilege('authenticated','festapp_stage_${source}_public','USAGE') OR has_schema_privilege('service_role','festapp_stage_${source}_public','USAGE')),(SELECT srvoptions @> ARRAY['host=db','port=5432','dbname=$database'] FROM pg_foreign_server WHERE srvname='festapp_stage_$source'))")"
  IFS='|' read -r source_public source_eshop source_managed <<<"$source_counts"
  expected_target="$source_public|$source_eshop|2|$source_managed|1|1|f|t"
  [[ "$target_counts" == "$expected_target" ]] || fail "$source FDW postcondition mismatch ($target_counts, expected $expected_target)"
  source_results="$(jq -cn --argjson prior "$source_results" --arg alias "$source" --arg project_ref "$project_ref" --arg database "$database" --argjson public "$source_public" --argjson eshop "$source_eshop" --argjson managed "$source_managed" '$prior + [{alias:$alias,project_ref:$project_ref,database:$database,public_foreign_tables:$public,eshop_foreign_tables:$eshop,managed_rows:$managed}]')"
done
reader_state="$(psql_db "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolinherit,rolreplication,rolbypassrls) FROM pg_roles WHERE rolname='$READER_ROLE'")"
[[ "$reader_state" == "t|f|f|f|f|f|f" ]] || fail "staging reader security postcondition failed ($reader_state)"
jq -n --arg mode "$ACK" --arg reader_role "$READER_ROLE" --arg registry_sha256 "$(shasum -a 256 "$REGISTRY_FILE" | awk '{print $1}')" \
  --arg preexisting_topology "$PREEXISTING_TOPOLOGY" --argjson sources "$source_results" \
  '{mode:$mode,registry_sha256:$registry_sha256,reader_role:$reader_role,reader_security:"login-with-24h-expiry-no-elevation",preexisting_topology_unchanged:true,preexisting_topology:$preexisting_topology,sources:$sources,deleted_or_overwritten_objects:0}' >"$run_dir/result.json"
chmod 0600 "$run_dir/result.json"
echo "Read-only local FDW staging bridge prepared: ${SOURCES[*]}"
echo "Evidence: $run_dir"
