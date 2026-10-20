#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-a-auth-preserve-password-hashes" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=import-a-auth-preserve-password-hashes"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked'),
  (SELECT count(*)>0 FROM festapp_merge.id_mappings m JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a'),
  (SELECT (SELECT count(*) FROM auth.users)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='users')
    AND (SELECT count(*) FROM auth.identities)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='identities')
    AND (SELECT count(*) FROM auth.sessions)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='sessions')
    AND (SELECT count(*) FROM auth.refresh_tokens)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='refresh_tokens')),
  (SELECT count(*) FROM auth.schema_migrations),
  (SELECT (SELECT count(*) FROM storage.objects)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='storage' AND source_table='objects')))")"
[[ "$STATE" == "17|1|t|t|76|t" ]] || fail "target is not approved a-Auth import state ($STATE)"

readonly AUDIT_DUPLICATES="$(psql_main -Atqc "WITH duplicate_keys AS (
  SELECT row_data->>'id' id,count(*) rows,count(DISTINCT row_data) variants
  FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='audit_log_entries'
  GROUP BY row_data->>'id' HAVING count(*)>1
) SELECT concat_ws('|',count(*),coalesce(sum(rows-1),0),count(*) FILTER(WHERE variants>1)) FROM duplicate_keys")"
[[ "$AUDIT_DUPLICATES" =~ ^[0-9]+\|[0-9]+\|0$ ]] || fail "source a audit log has conflicting duplicate IDs ($AUDIT_DUPLICATES)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-auth-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL session_replication_role = replica;
SET LOCAL statement_timeout = 0;

DO $import$
DECLARE
  import_run uuid;
  refresh_base bigint;
  relation record;
  target_column record;
  column_list text;
  select_list text;
  expression text;
  source_rows bigint;
  expected_rows bigint;
  before_rows bigint;
  after_rows bigint;
  inserted_rows bigint;
  changed_hashes bigint;
  missing_users bigint;
  foreign_key record;
  child_not_null text;
  join_expression text;
  orphan_rows bigint;
  refresh_mapping_count bigint;
  collision_users bigint;
  audit_duplicate_rows bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked';
  SELECT count(*) INTO refresh_mapping_count FROM festapp_stage_a_managed.rows
  WHERE source_schema='auth' AND source_table='refresh_tokens';
  SELECT count(*) INTO collision_users FROM festapp_merge.id_mappings
  WHERE run_id=import_run AND source_table='auth.users';
  SELECT count(*)-count(DISTINCT row_data->>'id') INTO audit_duplicate_rows
  FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='audit_log_entries';
  SELECT coalesce(max(id),0) INTO refresh_base FROM auth.refresh_tokens;
  INSERT INTO festapp_merge.id_mappings(run_id,source_table,source_id,target_id)
  SELECT import_run,'auth.refresh_tokens',row_data->>'id',
    (refresh_base+row_number() OVER (ORDER BY (row_data->>'id')::bigint))::bigint::text
  FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='refresh_tokens';
  IF (SELECT count(*) FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='auth.refresh_tokens')<>refresh_mapping_count THEN
    RAISE EXCEPTION 'refresh-token ID mapping count mismatch';
  END IF;

  FOR relation IN
    SELECT source_table table_name,count(*) source_rows
    FROM festapp_stage_a_managed.rows
    WHERE source_schema='auth' AND source_table<>'schema_migrations'
    GROUP BY source_table ORDER BY source_table
  LOOP
    source_rows:=relation.source_rows;
    IF relation.table_name='audit_log_entries' THEN source_rows:=source_rows-audit_duplicate_rows; END IF;
    EXECUTE format('SELECT count(*) FROM auth.%I',relation.table_name) INTO before_rows;
    column_list:=''; select_list:='';
    FOR target_column IN
      SELECT c.column_name,c.ordinal_position,format_type(a.atttypid,a.atttypmod) sql_type
      FROM information_schema.columns c
      JOIN pg_class pc ON pc.relname=c.table_name JOIN pg_namespace pn ON pn.oid=pc.relnamespace AND pn.nspname=c.table_schema
      JOIN pg_attribute a ON a.attrelid=pc.oid AND a.attname=c.column_name
      WHERE c.table_schema='auth' AND c.table_name=relation.table_name AND c.is_generated='NEVER'
      ORDER BY c.ordinal_position
    LOOP
      IF relation.table_name='refresh_tokens' AND target_column.column_name='id' THEN
        expression:=format('(SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.refresh_tokens'' AND m.source_id=s.row_data->>%L)',target_column.sql_type,import_run,target_column.column_name);
      ELSIF relation.table_name<>'users' AND target_column.column_name='user_id' THEN
        expression:=format('coalesce((SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>%L),(jsonb_populate_record(NULL::auth.%I,s.row_data)).%I)',
          target_column.sql_type,import_run,target_column.column_name,relation.table_name,target_column.column_name);
      ELSE
        expression:=format('(jsonb_populate_record(NULL::auth.%I,s.row_data)).%I',relation.table_name,target_column.column_name);
      END IF;
      column_list:=column_list||CASE WHEN column_list='' THEN '' ELSE ', ' END||format('%I',target_column.column_name);
      select_list:=select_list||CASE WHEN select_list='' THEN '' ELSE ', ' END||expression;
    END LOOP;

    IF relation.table_name='users' THEN
      EXECUTE format('INSERT INTO auth.users (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM festapp_stage_a_managed.rows s WHERE s.source_schema=''auth'' AND s.source_table=''users'' AND NOT EXISTS (SELECT 1 FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>''id'')',column_list,select_list,import_run);
      expected_rows:=source_rows-collision_users;
    ELSIF relation.table_name='identities' THEN
      EXECUTE format('INSERT INTO auth.identities (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM festapp_stage_a_managed.rows s WHERE s.source_schema=''auth'' AND s.source_table=''identities'' AND NOT EXISTS (SELECT 1 FROM festapp_merge.id_mappings m JOIN auth.identities t ON t.user_id=m.target_id::uuid AND t.provider=s.row_data->>''provider'' WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s.row_data->>''user_id'')',column_list,select_list,import_run);
      expected_rows:=source_rows-collision_users;
    ELSIF relation.table_name='audit_log_entries' THEN
      EXECUTE format('INSERT INTO auth.audit_log_entries (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM (SELECT DISTINCT ON (row_data->>''id'') row_data FROM festapp_stage_a_managed.rows WHERE source_schema=''auth'' AND source_table=''audit_log_entries'' ORDER BY row_data->>''id'',row_id) s',column_list,select_list);
      expected_rows:=source_rows;
    ELSE
      EXECUTE format('INSERT INTO auth.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM festapp_stage_a_managed.rows s WHERE s.source_schema=''auth'' AND s.source_table=%L',relation.table_name,column_list,select_list,relation.table_name);
      expected_rows:=source_rows;
    END IF;
    GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    EXECUTE format('SELECT count(*) FROM auth.%I',relation.table_name) INTO after_rows;
    IF inserted_rows<>expected_rows OR after_rows-before_rows<>expected_rows THEN
      RAISE EXCEPTION 'a Auth row mismatch for %: expected %, inserted %, delta %',relation.table_name,expected_rows,inserted_rows,after_rows-before_rows;
    END IF;
  END LOOP;

  WITH source_users AS MATERIALIZED (
    SELECT row_data FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='users'
  )
  SELECT count(*) FILTER (WHERE target.id IS NULL),
    count(*) FILTER (WHERE (source.row_data->>'encrypted_password') IS DISTINCT FROM target.encrypted_password)
  INTO missing_users,changed_hashes
  FROM source_users source LEFT JOIN auth.users target ON target.id=(source.row_data->>'id')::uuid
  WHERE NOT EXISTS (SELECT 1 FROM festapp_merge.id_mappings m WHERE m.run_id=import_run AND m.source_table='auth.users' AND m.source_id=source.row_data->>'id');
  IF missing_users<>0 OR changed_hashes<>0 THEN RAISE EXCEPTION 'a password continuity failed: missing %, changed %',missing_users,changed_hashes; END IF;

  FOR foreign_key IN
    SELECT con.conname,child_ns.nspname child_schema,child.relname child_table,
      parent_ns.nspname parent_schema,parent.relname parent_table,con.conkey,con.confkey
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f' AND child_ns.nspname IN ('auth','public','eshop') AND parent_ns.nspname='auth'
  LOOP
    SELECT string_agg(format('c.%I IS NOT NULL',child_col.attname),' AND ' ORDER BY key_pair.ord),
      string_agg(format('c.%I=p.%I',child_col.attname,parent_col.attname),' AND ' ORDER BY key_pair.ord)
    INTO child_not_null,join_expression
    FROM unnest(foreign_key.conkey,foreign_key.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord)
    JOIN pg_attribute child_col ON child_col.attrelid=(format('%I.%I',foreign_key.child_schema,foreign_key.child_table))::regclass AND child_col.attnum=key_pair.child_attnum
    JOIN pg_attribute parent_col ON parent_col.attrelid=(format('%I.%I',foreign_key.parent_schema,foreign_key.parent_table))::regclass AND parent_col.attnum=key_pair.parent_attnum;
    EXECUTE format('SELECT count(*) FROM %I.%I c WHERE %s AND NOT EXISTS (SELECT 1 FROM %I.%I p WHERE %s)',foreign_key.child_schema,foreign_key.child_table,child_not_null,foreign_key.parent_schema,foreign_key.parent_table,join_expression) INTO orphan_rows;
    IF orphan_rows<>0 THEN RAISE EXCEPTION 'Auth foreign key % has % orphan rows',foreign_key.conname,orphan_rows; END IF;
  END LOOP;

  PERFORM setval(pg_get_serial_sequence('auth.refresh_tokens','id'),(SELECT max(id) FROM auth.refresh_tokens),true);
  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'a-auth-import','pass',jsonb_build_object(
      'source_users',(SELECT count(*) FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='users'),
      'merged_users',collision_users,
      'inserted_users',(SELECT count(*) FROM festapp_stage_a_managed.rows WHERE source_schema='auth' AND source_table='users')-collision_users,
      'changed_password_hashes',0,'foreign_key_orphans',0,
      'refresh_token_id_mappings',refresh_mapping_count,
      'identical_rehearsal_audit_duplicates_deduplicated',audit_duplicate_rows));
  UPDATE festapp_merge.validation_results SET observed=jsonb_build_object('auth_imported',true,'auth_users',(SELECT count(*) FROM auth.users),'storage_imported',false,'storage_objects',(SELECT count(*) FROM storage.objects))
  WHERE run_id=import_run AND check_name='a-auth-and-storage-import';
END
$import$;

COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'auth_users',(SELECT count(*) FROM auth.users),'auth_identities',(SELECT count(*) FROM auth.identities),
  'auth_sessions',(SELECT count(*) FROM auth.sessions),'auth_refresh_tokens',(SELECT count(*) FROM auth.refresh_tokens),
  'auth_migration_rows',(SELECT count(*) FROM auth.schema_migrations),
  'changed_password_hashes',(SELECT observed->'changed_password_hashes' FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id AND check_name='a-auth-import')
) FROM festapp_merge.import_runs WHERE source_alias='a'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Source a Auth imported with canonical identity merges and unchanged password hashes."
echo "Evidence: $RUN_DIR"
