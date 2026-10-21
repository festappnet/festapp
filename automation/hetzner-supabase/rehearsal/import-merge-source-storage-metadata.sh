#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_FILE="${FESTAPP_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly SOURCE_ALIAS="${FESTAPP_MERGE_SOURCE_ALIAS:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-merge-source-storage-metadata-preserve-runtime-ledger" ]] ||
  fail "set the merge-source Storage metadata acknowledgement"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "invalid isolated rehearsal database name"
[[ "$SOURCE_ALIAS" =~ ^[a-z][a-z0-9_]{0,19}$ ]] || fail "invalid merge source alias"
[[ -f "$REGISTRY_FILE" ]] || fail "source registry is missing"
readonly SOURCE_REF="$(jq -er --arg source "$SOURCE_ALIAS" '.sources[]|select(.alias==$source and .role=="merge-source")|.project_ref' "$REGISTRY_FILE")" ||
  fail "source is not a registered merge source"
readonly PREDECESSORS="$(jq -r --arg source "$SOURCE_ALIAS" '[.sources[].alias] as $all | ($all|index($source)) as $i | if $i == null or $i == 0 then error("invalid merge source order") else $all[0:$i]|join(",") end' "$REGISTRY_FILE")"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved rehearsal host"

readonly STAGE_MANAGED="festapp_stage_${SOURCE_ALIAS}_managed"
cd "$COMPOSE_DIR"
docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }

readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',
  split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS' AND source_project_ref='$SOURCE_REF' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='$SOURCE_ALIAS' AND v.check_name='$SOURCE_ALIAS-auth-import' AND v.status='pass'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='$SOURCE_ALIAS' AND v.check_name IN ('$SOURCE_ALIAS-storage-metadata-import','$SOURCE_ALIAS-storage-object-payloads')),
  (SELECT count(*) FROM $STAGE_MANAGED.provenance WHERE source_alias='$SOURCE_ALIAS' AND source_project_ref='$SOURCE_REF' AND managed_rows=(SELECT count(*) FROM $STAGE_MANAGED.rows)),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias=ANY(string_to_array('$PREDECESSORS',',')) AND status='validated'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias=ANY(string_to_array('$PREDECESSORS',',')) AND v.status<>'pass'))")"
readonly PREDECESSOR_COUNT="$(awk -F, '{print NF}' <<<"$PREDECESSORS")"
[[ "$STATE" == "17|1|1|0|1|$PREDECESSOR_COUNT|0" ]] ||
  fail "target is not an approved additive Storage metadata state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/$SOURCE_ALIAS-storage-metadata-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main -v source_alias="$SOURCE_ALIAS" -v source_ref="$SOURCE_REF" -v stage_managed="$STAGE_MANAGED" <<'SQL'
BEGIN;
SET LOCAL session_replication_role=replica;
SET LOCAL statement_timeout=0;
SELECT set_config('festapp.merge_source_alias',:'source_alias',true);
SELECT set_config('festapp.merge_source_ref',:'source_ref',true);
SELECT set_config('festapp.merge_stage_managed',:'stage_managed',true);

CREATE TEMP TABLE preexisting_storage_buckets ON COMMIT DROP AS
  SELECT id,to_jsonb(b) row_data FROM storage.buckets b;
CREATE UNIQUE INDEX ON preexisting_storage_buckets(id);
CREATE TEMP TABLE preexisting_storage_objects ON COMMIT DROP AS
  SELECT id,to_jsonb(o) row_data FROM storage.objects o;
CREATE UNIQUE INDEX ON preexisting_storage_objects(id);

DO $import$
DECLARE
  import_run uuid; column_record record; column_list text:=''; select_list text:=''; expression text;
  source_bucket_rows bigint; merged_bucket_rows bigint; source_object_rows bigint; source_bytes bigint;
  inserted_rows bigint; mapped_owner_rows bigint; orphan_rows bigint; overlap_rows bigint;
  duplicate_ids bigint; duplicate_keys bigint; changed_preexisting bigint;
  foreign_key record; child_not_null text; join_expression text; provenance jsonb;
  migration_rows_before bigint; migration_rows_after bigint; migration_digest_before text; migration_digest_after text;
  v_source_alias text:=current_setting('festapp.merge_source_alias');
  v_source_ref text:=current_setting('festapp.merge_source_ref');
  stage_managed text:=current_setting('festapp.merge_stage_managed');
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias=v_source_alias AND source_project_ref=v_source_ref AND status='blocked';
  EXECUTE format('SELECT count(*),coalesce(sum(coalesce((row_data->''metadata''->>''size'')::bigint,0)),0) FROM %I.rows WHERE source_schema=''storage'' AND source_table=''objects''',stage_managed)
    INTO source_object_rows,source_bytes;
  EXECUTE format('SELECT count(*) FROM %I.rows WHERE source_schema=''storage'' AND source_table=''buckets''',stage_managed)
    INTO source_bucket_rows;
  IF source_object_rows=0 OR source_bucket_rows=0 THEN RAISE EXCEPTION 'merge-source Storage snapshot is empty'; END IF;
  EXECUTE format('SELECT jsonb_build_object(''raw_artifact_sha256'',raw_artifact_sha256,''raw_manifest_sha256'',raw_manifest_sha256,''managed_artifact_sha256'',managed_artifact_sha256,''managed_manifest_sha256'',managed_manifest_sha256,''raw_snapshot_at'',raw_snapshot_at,''managed_snapshot_at'',managed_snapshot_at) FROM %I.provenance WHERE source_alias=%L AND source_project_ref=%L',stage_managed,v_source_alias,v_source_ref)
    INTO STRICT provenance;

  EXECUTE format('SELECT count(*)-count(DISTINCT row_data->>''id'') FROM %I.rows WHERE source_schema=''storage'' AND source_table=''objects''',stage_managed)
    INTO duplicate_ids;
  EXECUTE format('SELECT count(*) FROM (SELECT row_data->>''bucket_id'',row_data->>''name'',row_data->>''version'',count(*) FROM %I.rows WHERE source_schema=''storage'' AND source_table=''objects'' GROUP BY 1,2,3 HAVING count(*)>1) duplicates',stage_managed)
    INTO duplicate_keys;
  EXECUTE format('SELECT count(*) FROM %I.rows s JOIN storage.objects t ON t.id=(s.row_data->>''id'')::uuid WHERE s.source_schema=''storage'' AND s.source_table=''objects''',stage_managed)
    INTO overlap_rows;
  IF duplicate_ids<>0 OR duplicate_keys<>0 OR overlap_rows<>0 THEN
    RAISE EXCEPTION 'Storage object identity precondition failed: duplicate IDs %, duplicate logical keys %, UUID overlap %',duplicate_ids,duplicate_keys,overlap_rows;
  END IF;
  EXECUTE format('SELECT count(*) FROM %I.rows s JOIN storage.objects t ON t.bucket_id=s.row_data->>''bucket_id'' AND t.name=s.row_data->>''name'' AND t.version IS NOT DISTINCT FROM s.row_data->>''version'' WHERE s.source_schema=''storage'' AND s.source_table=''objects''',stage_managed)
    INTO overlap_rows;
  IF overlap_rows<>0 THEN RAISE EXCEPTION 'Storage logical object keys overlap the canonical target: %',overlap_rows; END IF;

  -- Old Storage encoded disabled versioning as the literal DISABLED while the
  -- canonical runtime encodes the same behavior as NULL. Normalize only this
  -- documented representation difference; every other behavioral field must
  -- remain exactly equal.
  EXECUTE format('WITH source_buckets AS (SELECT row_data FROM %I.rows WHERE source_schema=''storage'' AND source_table=''buckets'') SELECT count(*),count(*) FILTER (WHERE jsonb_set(s.row_data-''created_at''-''updated_at'',''{versioning_status}'',to_jsonb(coalesce(nullif(s.row_data->>''versioning_status'',''DISABLED''),''DISABLED'')),true)=jsonb_set(to_jsonb(t)-''created_at''-''updated_at'',''{versioning_status}'',to_jsonb(coalesce(nullif(to_jsonb(t)->>''versioning_status'',''DISABLED''),''DISABLED'')),true)) FROM source_buckets s JOIN storage.buckets t ON t.id=s.row_data->>''id''',stage_managed)
    INTO merged_bucket_rows,overlap_rows;
  IF merged_bucket_rows<>overlap_rows THEN RAISE EXCEPTION 'overlapping Storage buckets are not semantically identical: %/%',overlap_rows,merged_bucket_rows; END IF;

  SELECT count(*),encode(digest(coalesce(string_agg(to_jsonb(m)::text,'' ORDER BY to_jsonb(m)::text),''),'sha256'),'hex')
    INTO migration_rows_before,migration_digest_before FROM storage.migrations m;

  EXECUTE format('INSERT INTO storage.buckets OVERRIDING SYSTEM VALUE SELECT (jsonb_populate_record(NULL::storage.buckets,s.row_data)).* FROM %I.rows s WHERE s.source_schema=''storage'' AND s.source_table=''buckets'' AND NOT EXISTS (SELECT 1 FROM storage.buckets target WHERE target.id=s.row_data->>''id'')',stage_managed);
  GET DIAGNOSTICS inserted_rows=ROW_COUNT;
  IF inserted_rows<>source_bucket_rows-merged_bucket_rows THEN RAISE EXCEPTION 'source-only Storage bucket count mismatch: expected %, inserted %',source_bucket_rows-merged_bucket_rows,inserted_rows; END IF;

  FOR column_record IN
    SELECT c.column_name,c.ordinal_position,format_type(a.atttypid,a.atttypmod) sql_type
    FROM information_schema.columns c
    JOIN pg_class pc ON pc.relname=c.table_name
    JOIN pg_namespace pn ON pn.oid=pc.relnamespace AND pn.nspname=c.table_schema
    JOIN pg_attribute a ON a.attrelid=pc.oid AND a.attname=c.column_name
    WHERE c.table_schema='storage' AND c.table_name='objects' AND c.is_generated='NEVER'
    ORDER BY c.ordinal_position
  LOOP
    IF column_record.column_name IN ('owner','owner_id') THEN
      expression:=format('coalesce((SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>%L),(jsonb_populate_record(NULL::storage.objects,s.row_data)).%I)',column_record.sql_type,import_run,column_record.column_name,column_record.column_name);
    ELSE
      expression:=format('(jsonb_populate_record(NULL::storage.objects,s.row_data)).%I',column_record.column_name);
    END IF;
    column_list:=column_list||CASE WHEN column_list='' THEN '' ELSE ', ' END||format('%I',column_record.column_name);
    select_list:=select_list||CASE WHEN select_list='' THEN '' ELSE ', ' END||expression;
  END LOOP;
  EXECUTE format('INSERT INTO storage.objects (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.rows s WHERE s.source_schema=''storage'' AND s.source_table=''objects''',column_list,select_list,stage_managed);
  GET DIAGNOSTICS inserted_rows=ROW_COUNT;
  IF inserted_rows<>source_object_rows THEN RAISE EXCEPTION 'Storage object metadata count mismatch: expected %, inserted %',source_object_rows,inserted_rows; END IF;

  SELECT count(*) INTO changed_preexisting FROM preexisting_storage_buckets b LEFT JOIN storage.buckets t USING(id) WHERE t.id IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data;
  IF changed_preexisting<>0 THEN RAISE EXCEPTION 'pre-existing Storage buckets changed: %',changed_preexisting; END IF;
  SELECT count(*) INTO changed_preexisting FROM preexisting_storage_objects b LEFT JOIN storage.objects t USING(id) WHERE t.id IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data;
  IF changed_preexisting<>0 THEN RAISE EXCEPTION 'pre-existing Storage objects changed: %',changed_preexisting; END IF;

  EXECUTE format('SELECT count(*) FROM %I.rows s JOIN storage.objects t ON t.id=(s.row_data->>''id'')::uuid WHERE s.source_schema=''storage'' AND s.source_table=''objects'' AND (t.owner IS DISTINCT FROM coalesce((SELECT m.target_id::uuid FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>''owner''),(s.row_data->>''owner'')::uuid) OR t.owner_id IS DISTINCT FROM coalesce((SELECT m.target_id FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>''owner_id''),s.row_data->>''owner_id''))',stage_managed,import_run,import_run)
    INTO orphan_rows;
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage owner remapping did not converge: %',orphan_rows; END IF;
  SELECT count(*) INTO orphan_rows FROM storage.objects o WHERE o.bucket_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM storage.buckets b WHERE b.id=o.bucket_id);
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage objects have missing buckets: %',orphan_rows; END IF;
  SELECT count(*) INTO orphan_rows FROM storage.objects o WHERE o.owner IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=o.owner);
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage owner UUIDs have missing Auth users: %',orphan_rows; END IF;
  SELECT count(*) INTO orphan_rows FROM storage.objects o WHERE o.owner_id IS NOT NULL AND o.owner_id<>'' AND CASE
    WHEN o.owner_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      THEN NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=o.owner_id::uuid)
    ELSE true END;
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage owner_id values have missing Auth users: %',orphan_rows; END IF;
  EXECUTE format('SELECT count(*) FROM %I.rows s JOIN storage.objects t ON t.id=(s.row_data->>''id'')::uuid WHERE s.source_schema=''storage'' AND s.source_table=''objects'' AND t.owner IS NOT NULL AND t.owner_id IS NOT NULL AND t.owner::text IS DISTINCT FROM t.owner_id',stage_managed)
    INTO orphan_rows;
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage owner and owner_id disagree for imported rows: %',orphan_rows; END IF;
  EXECUTE format('SELECT count(*) FROM %I.rows s JOIN storage.objects t ON t.id=(s.row_data->>''id'')::uuid WHERE s.source_schema=''storage'' AND s.source_table=''objects'' AND (to_jsonb(t)-''owner''-''owner_id'') IS DISTINCT FROM (to_jsonb(jsonb_populate_record(NULL::storage.objects,s.row_data))-''owner''-''owner_id'')',stage_managed)
    INTO orphan_rows;
  IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage metadata transformation differs outside owner fields: %',orphan_rows; END IF;

  FOR foreign_key IN
    SELECT con.conname,child_ns.nspname child_schema,child.relname child_table,
      parent_ns.nspname parent_schema,parent.relname parent_table,con.conkey,con.confkey
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f' AND child_ns.nspname='storage'
  LOOP
    SELECT string_agg(format('c.%I IS NOT NULL',child_col.attname),' AND ' ORDER BY key_pair.ord),
      string_agg(format('c.%I=p.%I',child_col.attname,parent_col.attname),' AND ' ORDER BY key_pair.ord)
    INTO child_not_null,join_expression
    FROM unnest(foreign_key.conkey,foreign_key.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord)
    JOIN pg_attribute child_col ON child_col.attrelid=(format('%I.%I',foreign_key.child_schema,foreign_key.child_table))::regclass AND child_col.attnum=key_pair.child_attnum
    JOIN pg_attribute parent_col ON parent_col.attrelid=(format('%I.%I',foreign_key.parent_schema,foreign_key.parent_table))::regclass AND parent_col.attnum=key_pair.parent_attnum;
    EXECUTE format('SELECT count(*) FROM %I.%I c WHERE %s AND NOT EXISTS (SELECT 1 FROM %I.%I p WHERE %s)',foreign_key.child_schema,foreign_key.child_table,child_not_null,foreign_key.parent_schema,foreign_key.parent_table,join_expression) INTO orphan_rows;
    IF orphan_rows<>0 THEN RAISE EXCEPTION 'Storage foreign key % has % orphan rows',foreign_key.conname,orphan_rows; END IF;
  END LOOP;

  SELECT count(*),encode(digest(coalesce(string_agg(to_jsonb(m)::text,'' ORDER BY to_jsonb(m)::text),''),'sha256'),'hex')
    INTO migration_rows_after,migration_digest_after FROM storage.migrations m;
  IF migration_rows_after<>migration_rows_before OR migration_digest_after<>migration_digest_before THEN RAISE EXCEPTION 'Storage runtime migration ledger changed'; END IF;

  EXECUTE format('SELECT count(*) FROM %I.rows s WHERE s.source_schema=''storage'' AND s.source_table=''objects'' AND EXISTS (SELECT 1 FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=coalesce(s.row_data->>''owner_id'',s.row_data->>''owner''))',stage_managed,import_run)
    INTO mapped_owner_rows;
  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,v_source_alias||'-storage-metadata-import','pass',jsonb_build_object(
      'source_buckets',source_bucket_rows,'merged_buckets',merged_bucket_rows,
      'inserted_buckets',source_bucket_rows-merged_bucket_rows,'inserted_objects',source_object_rows,
      'mapped_owner_rows',mapped_owner_rows,'runtime_migration_ledger_rows',migration_rows_after,
      'runtime_migration_ledger_sha256',migration_digest_after,'preexisting_rows_changed',0,
      'uuid_overlaps',0,'logical_key_overlaps',0,'foreign_key_orphans',0,
      'source_provenance',provenance,'deleted_rows',0)),
    (import_run,v_source_alias||'-storage-object-payloads','blocked',jsonb_build_object(
      'metadata_rows',source_object_rows,'payload_bytes',source_bytes,'copied_payloads',0,'deleted_payloads',0));
  UPDATE festapp_merge.validation_results SET observed=jsonb_build_object(
    'auth_imported',true,'auth_users',(SELECT count(*) FROM auth.users),
    'storage_metadata_imported',true,'storage_objects',(SELECT count(*) FROM storage.objects),
    'storage_payloads_imported',false)
  WHERE run_id=import_run AND check_name=v_source_alias||'-auth-and-storage-import';
  GET DIAGNOSTICS inserted_rows=ROW_COUNT;
  IF inserted_rows<>1 THEN RAISE EXCEPTION 'Auth/Storage gate update count mismatch: %',inserted_rows; END IF;
END
$import$;
COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'source_alias',source_alias,'storage_buckets',(SELECT count(*) FROM storage.buckets),
  'storage_objects',(SELECT count(*) FROM storage.objects),
  'validation',(SELECT observed FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id AND check_name='$SOURCE_ALIAS-storage-metadata-import'),
  'payload_gate',(SELECT status FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id AND check_name='$SOURCE_ALIAS-storage-object-payloads')
) FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Merge-source Storage metadata imported; payload copy remains blocked: $SOURCE_ALIAS"
echo "Evidence: $RUN_DIR"
