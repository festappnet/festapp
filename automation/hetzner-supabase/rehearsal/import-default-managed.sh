#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly EXPECTED_AUTH_MIGRATIONS="76"
readonly EXPECTED_STORAGE_MIGRATIONS="61"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-default-auth-and-storage-metadata" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=import-default-auth-and-storage-metadata"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly SOURCE_ROWS="$(psql_main -Atqc "SELECT count(*) FROM festapp_stage_default_managed.rows WHERE (source_schema,source_table) NOT IN (('auth','schema_migrations'),('storage','migrations'))")"
[[ "$SOURCE_ROWS" =~ ^[1-9][0-9]*$ ]] || fail "default managed source is empty or invalid ($SOURCE_ROWS)"
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',
  split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='default' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.quarantined_rows),
  (SELECT count(*) FROM auth.users),
  (SELECT count(*) FROM storage.objects),
  (SELECT count(*) FROM auth.schema_migrations),
  (SELECT count(*) FROM storage.migrations),
  (SELECT count(*) FROM festapp_stage_default_managed.rows WHERE (source_schema,source_table) NOT IN (('auth','schema_migrations'),('storage','migrations')))
)")"
[[ "$STATE" == "17|1|2|0|0|$EXPECTED_AUTH_MIGRATIONS|$EXPECTED_STORAGE_MIGRATIONS|$SOURCE_ROWS" ]] ||
  fail "canonical target is not approved default-managed import state ($STATE)"

readonly TARGET_BUSINESS_ROWS="$(psql_main -Atqc "DO \$\$ DECLARE r record; n bigint; total bigint:=0; BEGIN
  FOR r IN SELECT schemaname,tablename FROM pg_tables
    WHERE schemaname IN ('auth','storage') AND tablename NOT IN ('schema_migrations','migrations')
  LOOP EXECUTE format('SELECT count(*) FROM %I.%I',r.schemaname,r.tablename) INTO n; total:=total+n; END LOOP;
  RAISE NOTICE 'total=%',total;
END \$\$;" 2>&1 | sed -n 's/^NOTICE:  total=//p')"
[[ "$TARGET_BUSINESS_ROWS" == "0" ]] || fail "managed target business tables are not empty ($TARGET_BUSINESS_ROWS rows)"

readonly REQUIRED_GAPS="$(psql_main -Atqc "WITH source_columns AS (
  SELECT source_schema,source_table,jsonb_object_keys(row_data) AS column_name
  FROM festapp_stage_default_managed.rows
  WHERE (source_schema,source_table) NOT IN (('auth','schema_migrations'),('storage','migrations'))
) SELECT count(*) FROM information_schema.columns target
LEFT JOIN source_columns source ON source.source_schema=target.table_schema
  AND source.source_table=target.table_name AND source.column_name=target.column_name
WHERE target.table_schema IN ('auth','storage')
  AND (target.table_schema,target.table_name) IN (
    SELECT source_schema,source_table FROM festapp_stage_default_managed.rows
    WHERE (source_schema,source_table) NOT IN (('auth','schema_migrations'),('storage','migrations'))
  )
  AND target.is_nullable='NO' AND target.column_default IS NULL
  AND target.is_identity='NO' AND target.is_generated='NEVER' AND source.column_name IS NULL")"
[[ "$REQUIRED_GAPS" == "0" ]] || fail "default managed import has $REQUIRED_GAPS unresolved required target columns"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/default-managed-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
psql_main -Atqc "SELECT jsonb_build_object(
  'source_business_rows',$SOURCE_ROWS,
  'target_auth_migration_rows',(SELECT count(*) FROM auth.schema_migrations),
  'target_storage_migration_rows',(SELECT count(*) FROM storage.migrations),
  'target_auth_users',(SELECT count(*) FROM auth.users),
  'target_storage_objects',(SELECT count(*) FROM storage.objects)
)" >"$RUN_DIR/preflight.json"
chmod 0600 "$RUN_DIR/preflight.json"

psql_main <<'SQL'
BEGIN;
SET LOCAL session_replication_role = replica;
SET LOCAL statement_timeout = 0;

DO $import$
DECLARE
  relation record;
  column_list text;
  select_list text;
  source_rows bigint;
  target_rows bigint;
  foreign_key record;
  child_not_null text;
  join_expression text;
  orphan_rows bigint;
  import_run uuid;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='default' AND status='blocked';

  FOR relation IN
    SELECT source_schema AS target_schema, source_table AS table_name, count(*) AS expected_rows
    FROM festapp_stage_default_managed.rows
    WHERE (source_schema,source_table) NOT IN (('auth','schema_migrations'),('storage','migrations'))
    GROUP BY source_schema,source_table ORDER BY source_schema,source_table
  LOOP
    SELECT
      string_agg(format('%I',target.column_name),', ' ORDER BY target.ordinal_position),
      string_agg(format('(jsonb_populate_record(NULL::%I.%I, row_data)).%I',
        relation.target_schema,relation.table_name,target.column_name),', ' ORDER BY target.ordinal_position)
    INTO column_list,select_list
    FROM information_schema.columns target
    WHERE target.table_schema=relation.target_schema AND target.table_name=relation.table_name
      AND target.is_generated='NEVER';
    IF column_list IS NULL THEN
      RAISE EXCEPTION 'no managed import columns for %.%',relation.target_schema,relation.table_name;
    END IF;
    EXECUTE format(
      'INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM festapp_stage_default_managed.rows WHERE source_schema=%L AND source_table=%L',
      relation.target_schema,relation.table_name,column_list,select_list,relation.target_schema,relation.table_name
    );
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.target_schema,relation.table_name) INTO target_rows;
    source_rows:=relation.expected_rows;
    IF source_rows <> target_rows THEN
      RAISE EXCEPTION 'managed row mismatch for %.%: source %, target %',relation.target_schema,relation.table_name,source_rows,target_rows;
    END IF;
  END LOOP;

  FOR foreign_key IN
    SELECT con.oid,con.conname,child_ns.nspname AS child_schema,child.relname AS child_table,
      parent_ns.nspname AS parent_schema,parent.relname AS parent_table,con.conkey,con.confkey
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f' AND child_ns.nspname IN ('auth','storage')
  LOOP
    SELECT string_agg(format('c.%I IS NOT NULL',child_col.attname),' AND ' ORDER BY key_pair.ord),
      string_agg(format('c.%I=p.%I',child_col.attname,parent_col.attname),' AND ' ORDER BY key_pair.ord)
    INTO child_not_null,join_expression
    FROM unnest(foreign_key.conkey,foreign_key.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord)
    JOIN pg_attribute child_col ON child_col.attrelid=(format('%I.%I',foreign_key.child_schema,foreign_key.child_table))::regclass
      AND child_col.attnum=key_pair.child_attnum
    JOIN pg_attribute parent_col ON parent_col.attrelid=(format('%I.%I',foreign_key.parent_schema,foreign_key.parent_table))::regclass
      AND parent_col.attnum=key_pair.parent_attnum;
    EXECUTE format('SELECT count(*) FROM %I.%I c WHERE %s AND NOT EXISTS (SELECT 1 FROM %I.%I p WHERE %s)',
      foreign_key.child_schema,foreign_key.child_table,child_not_null,
      foreign_key.parent_schema,foreign_key.parent_table,join_expression) INTO orphan_rows;
    IF orphan_rows <> 0 THEN
      RAISE EXCEPTION 'foreign key % has % orphan rows',foreign_key.conname,orphan_rows;
    END IF;
  END LOOP;

  UPDATE festapp_merge.validation_results
  SET status='pass',observed=jsonb_build_object(
    'auth_users',(SELECT count(*) FROM auth.users),
    'storage_buckets',(SELECT count(*) FROM storage.buckets),
    'storage_objects',(SELECT count(*) FROM storage.objects),
    'runtime_migration_ledgers_preserved',true,
    'object_payloads_copied',false
  ) WHERE run_id=import_run AND check_name='auth-and-storage-import';
  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'default-managed-foreign-keys','pass',jsonb_build_object('orphan_rows',0)),
    (import_run,'default-storage-object-payloads','blocked',jsonb_build_object('metadata_rows',(SELECT count(*) FROM storage.objects),'copied_payloads',0));
END
$import$;

COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'auth_users',(SELECT count(*) FROM auth.users),
  'auth_identities',(SELECT count(*) FROM auth.identities),
  'auth_sessions',(SELECT count(*) FROM auth.sessions),
  'storage_buckets',(SELECT count(*) FROM storage.buckets),
  'storage_objects',(SELECT count(*) FROM storage.objects),
  'auth_migration_rows',(SELECT count(*) FROM auth.schema_migrations),
  'storage_migration_rows',(SELECT count(*) FROM storage.migrations),
  'import_status',(SELECT status FROM festapp_merge.import_runs WHERE source_alias='default')
)" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Default Auth and Storage metadata imported; object payload gate remains blocked."
echo "Evidence: $RUN_DIR"
