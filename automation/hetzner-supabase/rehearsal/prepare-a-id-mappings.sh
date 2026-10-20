#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly DECISIONS_FILE="${FESTAPP_A_IDENTITY_DECISIONS_FILE:-/var/lib/festapp-rehearsal-evidence/identity-decisions-v4.json}"
readonly EXPECTED_FILE_SHA256="474795575e9d4bd585a553cc8555e16abfc639995c23fff7727fc6951924c7b3"
readonly EXPECTED_DECISION_SHA256="df6793daa2f9d7a715668d7adfc3e40688d0d4897f53852ad97e19a8b9932275"
readonly SOURCE_REF="lwfpdjxsdmkfyrzqbrlk"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "prepare-a-deterministic-id-mappings" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=prepare-a-deterministic-id-mappings"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
[[ -f "$DECISIONS_FILE" ]] || fail "private identity decision file is unavailable"
[[ "$(stat -c '%a' "$DECISIONS_FILE")" == "600" ]] || fail "private identity decision file must be mode 0600"
[[ "$(sha256sum "$DECISIONS_FILE" | awk '{print $1}')" == "$EXPECTED_FILE_SHA256" ]] || fail "identity decision file checksum mismatch"
[[ "$(jq -r '.decision_sha256' "$DECISIONS_FILE")" == "$EXPECTED_DECISION_SHA256" ]] || fail "identity decision content checksum mismatch"
[[ "$(jq -r '[.validation.status,.validation.resolved,.validation.unresolved]|join("|")' "$DECISIONS_FILE")" == "pass|13|0" ]] ||
  fail "identity decisions are not approved and complete"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='default' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a'),
  (SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_a_public','festapp_stage_a_eshop')),
  (SELECT count(*)>0 FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='users'),
  (SELECT (SELECT count(*) FROM auth.users)=(SELECT count(*) FROM festapp_stage_default_managed.rows
    WHERE source_schema='auth' AND source_table='users')),
  (SELECT (SELECT count(*) FROM storage.objects)=(SELECT count(*) FROM festapp_stage_default_managed.rows
    WHERE source_schema='storage' AND source_table='objects')),
  (SELECT count(*)=1 FROM festapp_stage_a_managed.provenance
    WHERE source_alias='a' AND source_project_ref='$SOURCE_REF'),
  (SELECT managed_rows=(SELECT count(*) FROM festapp_stage_a_managed.rows)
    FROM festapp_stage_a_managed.provenance))")"
[[ "$STATE" == "17|1|0|100|t|t|t|t|t" ]] || fail "target is not approved a-mapping state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-id-mappings-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
readonly RUN_ID="$(psql_main -Atqc 'SELECT gen_random_uuid()')"
[[ "$RUN_ID" =~ ^[0-9a-f-]{36}$ ]] || fail "could not allocate import run ID"

{
  printf '%s\n' "BEGIN;" \
    "SET LOCAL statement_timeout = 0;" \
    "INSERT INTO festapp_merge.import_runs(run_id,source_alias,source_project_ref,snapshot_at,source_schema_fingerprint,transformation_version,status)" \
    "SELECT '$RUN_ID','a',source_project_ref,raw_snapshot_at,raw_schema_sha256,'a-id-map-2026-08-27.2','prepared'" \
    "FROM festapp_stage_a_managed.provenance WHERE source_alias='a' AND source_project_ref='$SOURCE_REF';" \
    "DO \$mapping\$" \
    "DECLARE relation record; base_id bigint;" \
    "BEGIN" \
    " FOR relation IN" \
    "  SELECT n.nspname target_schema,c.relname table_name,a.attname pk_column" \
    "  FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace" \
    "  JOIN LATERAL unnest(con.conkey) k(attnum) ON true JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum" \
    "  WHERE con.contype='p' AND cardinality(con.conkey)=1 AND n.nspname IN ('public','eshop')" \
    "    AND a.atttypid IN ('int2'::regtype,'int4'::regtype,'int8'::regtype)" \
    "    AND EXISTS (SELECT 1 FROM information_schema.foreign_tables f WHERE f.foreign_table_schema='festapp_stage_a_'||n.nspname AND f.foreign_table_name=c.relname)" \
    "  ORDER BY n.nspname,c.relname" \
    " LOOP" \
    "  EXECUTE format('SELECT coalesce(max(%I)::bigint,0) FROM %I.%I',relation.pk_column,relation.target_schema,relation.table_name) INTO base_id;" \
    "  EXECUTE format('INSERT INTO festapp_merge.id_mappings(run_id,source_table,source_id,target_id) SELECT %L,%L,s.%I::text,(%s+row_number() OVER (ORDER BY s.%I))::bigint::text FROM festapp_stage_a_%I.%I s'," \
    "    '$RUN_ID',relation.target_schema||'.'||relation.table_name,relation.pk_column,base_id,relation.pk_column,relation.target_schema,relation.table_name);" \
    " END LOOP;" \
    "END" \
    "\$mapping\$;" \
    "COPY festapp_merge.id_mappings(run_id,source_table,source_id,target_id) FROM STDIN WITH (FORMAT csv,DELIMITER E'\\t');"
  jq -r --arg run "$RUN_ID" '.decisions[] | [$run,"auth.users",.source_user_id,.target_user_id] | @tsv' "$DECISIONS_FILE"
  printf '%s\n' '\.' \
    "INSERT INTO festapp_merge.id_mappings(run_id,source_table,source_id,target_id)" \
    "SELECT run_id,'public.user_info',source_id,target_id FROM festapp_merge.id_mappings WHERE run_id='$RUN_ID' AND source_table='auth.users';" \
    "DO \$validate\$" \
    "DECLARE numeric_mappings bigint; auth_mappings bigint; profile_mappings bigint; verified_pairs bigint; collision_pairs bigint; missing_decisions bigint; stale_decisions bigint;" \
    "BEGIN" \
    " SELECT count(*) FILTER (WHERE source_table NOT IN ('auth.users','public.user_info'))," \
    "   count(*) FILTER (WHERE source_table='auth.users'),count(*) FILTER (WHERE source_table='public.user_info')" \
    " INTO numeric_mappings,auth_mappings,profile_mappings FROM festapp_merge.id_mappings WHERE run_id='$RUN_ID';" \
    " WITH source_users AS MATERIALIZED (" \
    "  SELECT (row_data->>'id')::uuid source_id,lower(row_data->>'email') email FROM festapp_stage_a_managed.rows" \
    "  WHERE source_schema='auth' AND source_table='users'" \
    " ) SELECT count(*) INTO verified_pairs FROM festapp_merge.id_mappings m" \
    " JOIN source_users s ON s.source_id=m.source_id::uuid JOIN auth.users t ON t.id=m.target_id::uuid AND lower(t.email)=s.email" \
    " WHERE m.run_id='$RUN_ID' AND m.source_table='auth.users' AND m.source_id<>m.target_id;" \
    " WITH collisions AS MATERIALIZED (" \
    "  SELECT s.row_data->>'id' source_id,t.id::text target_id FROM festapp_stage_a_managed.rows s" \
    "  JOIN auth.users t ON lower(t.email)=lower(s.row_data->>'email') AND t.id::text<>s.row_data->>'id'" \
    "  WHERE s.source_schema='auth' AND s.source_table='users'" \
    " ) SELECT count(*),count(*) FILTER (WHERE m.source_id IS NULL) INTO collision_pairs,missing_decisions" \
    " FROM collisions c LEFT JOIN festapp_merge.id_mappings m ON m.run_id='$RUN_ID' AND m.source_table='auth.users'" \
    "  AND m.source_id=c.source_id AND m.target_id=c.target_id;" \
    " SELECT count(*) INTO stale_decisions FROM festapp_merge.id_mappings m" \
    " WHERE m.run_id='$RUN_ID' AND m.source_table='auth.users' AND NOT EXISTS (" \
    "  SELECT 1 FROM festapp_stage_a_managed.rows s JOIN auth.users t" \
    "    ON lower(t.email)=lower(s.row_data->>'email') AND t.id::text<>s.row_data->>'id'" \
    "  WHERE s.source_schema='auth' AND s.source_table='users'" \
    "    AND s.row_data->>'id'=m.source_id AND t.id::text=m.target_id);" \
    " IF numeric_mappings=0 OR auth_mappings<>collision_pairs OR profile_mappings<>collision_pairs" \
    "    OR verified_pairs<>collision_pairs OR missing_decisions<>0 OR stale_decisions<>0 THEN" \
    "  RAISE EXCEPTION 'a mapping assertion failed: numeric %, collisions %, auth %, profile %, verified %, missing %, stale %',numeric_mappings,collision_pairs,auth_mappings,profile_mappings,verified_pairs,missing_decisions,stale_decisions;" \
    " END IF;" \
    " INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES ('$RUN_ID','a-id-mapping-preparation','pass',jsonb_build_object(" \
    "  'numeric_mappings',numeric_mappings,'identity_mappings',auth_mappings,'profile_mappings',profile_mappings," \
    "  'identity_decision_sha256','$EXPECTED_DECISION_SHA256'," \
    "  'raw_artifact_sha256',(SELECT raw_artifact_sha256 FROM festapp_stage_a_managed.provenance)," \
    "  'raw_manifest_sha256',(SELECT raw_manifest_sha256 FROM festapp_stage_a_managed.provenance)," \
    "  'managed_artifact_sha256',(SELECT managed_artifact_sha256 FROM festapp_stage_a_managed.provenance)," \
    "  'managed_manifest_sha256',(SELECT managed_manifest_sha256 FROM festapp_stage_a_managed.provenance)," \
    "  'managed_snapshot_at',(SELECT managed_snapshot_at FROM festapp_stage_a_managed.provenance)));" \
    "END" \
    "\$validate\$;" \
    "COMMIT;"
} | psql_main

psql_main -Atqc "SELECT jsonb_build_object(
  'run_id',run_id,'status',status,
  'mappings',(SELECT count(*) FROM festapp_merge.id_mappings WHERE run_id=import_runs.run_id),
  'mapping_relations',(SELECT count(DISTINCT source_table) FROM festapp_merge.id_mappings WHERE run_id=import_runs.run_id),
  'validation',(SELECT observed FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id AND check_name='a-id-mapping-preparation')
) FROM festapp_merge.import_runs WHERE run_id='$RUN_ID'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Source a deterministic ID mappings prepared with private identity decisions."
echo "Evidence: $RUN_DIR"
