#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-a-relational-data-with-derived-state-blocked" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=import-a-relational-data-with-derived-state-blocked"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly MAPPING_COUNT="$(psql_main -Atqc "SELECT count(*) FROM festapp_merge.id_mappings m JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND r.status='prepared'")"
[[ "$MAPPING_COUNT" =~ ^[1-9][0-9]*$ ]] || fail "source a mapping set is empty or invalid ($MAPPING_COUNT)"
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='default' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a' AND status='prepared'),
  (SELECT count(*) FROM festapp_merge.quarantined_rows q JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a'),
  (SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_a_public','festapp_stage_a_eshop')),
  (SELECT (SELECT count(*) FROM auth.users)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='users')
    AND (SELECT count(*) FROM storage.objects)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='storage' AND source_table='objects')))")"
[[ "$STATE" == "17|1|1|0|100|t" ]] || fail "target is not approved a-import state ($STATE)"

readonly LEDGER_DIFFERENCES="$(psql_main -Atqc "SELECT count(*) FROM festapp_stage_a_public.supabase_migrations s
JOIN public.supabase_migrations t USING(version) WHERE to_jsonb(s)-'version'<>to_jsonb(t)-'version'")"
[[ "$LEDGER_DIFFERENCES" == "0" ]] || fail "legacy migration ledger contains conflicting duplicate versions"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-canonical-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
psql_main -Atqc "SELECT jsonb_build_object(
  'source_tables',(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_a_public','festapp_stage_a_eshop')),
  'id_mappings',$MAPPING_COUNT,
  'auth_users',(SELECT count(*) FROM auth.users),'storage_objects',(SELECT count(*) FROM storage.objects)
)" >"$RUN_DIR/preflight.json"
chmod 0600 "$RUN_DIR/preflight.json"

psql_main <<'SQL'
BEGIN;
SET LOCAL session_replication_role = replica;
SET LOCAL statement_timeout = 0;

CREATE TEMP TABLE festapp_a_mapping_domains AS
WITH RECURSIVE import_run AS (
  SELECT run_id FROM festapp_merge.import_runs WHERE source_alias='a' AND status='prepared'
), domains(target_schema,target_table,target_column,mapping_table) AS (
  SELECT n.nspname,c.relname,a.attname,
    CASE WHEN n.nspname='public' AND c.relname='user_info' THEN 'auth.users' ELSE n.nspname||'.'||c.relname END
  FROM pg_constraint con
  JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN LATERAL unnest(con.conkey) key(attnum) ON true
  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=key.attnum
  WHERE con.contype='p' AND EXISTS (
    SELECT 1 FROM festapp_merge.id_mappings m,import_run r
    WHERE m.run_id=r.run_id AND m.source_table=n.nspname||'.'||c.relname
  )
  UNION
  SELECT child_ns.nspname,child.relname,child_col.attname,parent_domain.mapping_table
  FROM domains parent_domain
  JOIN pg_namespace parent_ns ON parent_ns.nspname=parent_domain.target_schema
  JOIN pg_class parent ON parent.relnamespace=parent_ns.oid AND parent.relname=parent_domain.target_table
  JOIN pg_attribute parent_col ON parent_col.attrelid=parent.oid AND parent_col.attname=parent_domain.target_column
  JOIN pg_constraint con ON con.contype='f' AND con.confrelid=parent.oid
  JOIN LATERAL unnest(con.conkey,con.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord)
    ON key_pair.parent_attnum=parent_col.attnum
  JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
  JOIN pg_attribute child_col ON child_col.attrelid=child.oid AND child_col.attnum=key_pair.child_attnum
)
SELECT DISTINCT target_schema,target_table,target_column,mapping_table FROM domains;

DO $domains$
DECLARE ambiguous record;
BEGIN
  SELECT target_schema,target_table,target_column,count(DISTINCT mapping_table) mappings
  INTO ambiguous FROM festapp_a_mapping_domains
  GROUP BY target_schema,target_table,target_column HAVING count(DISTINCT mapping_table)>1 LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'ambiguous mapping domain for %.%.% (% candidates)',ambiguous.target_schema,ambiguous.target_table,ambiguous.target_column,ambiguous.mappings; END IF;
END
$domains$;

DO $import$
DECLARE
  import_run uuid;
  relation record;
  target_column record;
  source_rows bigint;
  before_rows bigint;
  after_rows bigint;
  expected_rows bigint;
  inserted_rows bigint;
  excluded_rows bigint := 0;
  excluded_tables integer := 0;
  column_list text;
  select_list text;
  expression text;
  mapping_table text;
  own_strict_mapping boolean;
  sequence_record record;
  foreign_key record;
  child_not_null text;
  join_expression text;
  orphan_rows bigint;
  collision_profiles bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias='a' AND status='prepared';
  SELECT count(*) INTO collision_profiles FROM festapp_merge.id_mappings
  WHERE run_id=import_run AND source_table='public.user_info';
  IF collision_profiles=0 THEN RAISE EXCEPTION 'source a has no approved collision profile mappings'; END IF;

  IF EXISTS (SELECT 1 FROM festapp_stage_a_eshop.planned_changes
    WHERE change_type NOT LIKE 'forms.%') THEN
    RAISE EXCEPTION 'planned_changes contains an unregistered polymorphic subject type';
  END IF;

  FOR relation IN
    SELECT foreign_table_schema source_schema,
      replace(foreign_table_schema,'festapp_stage_a_','') target_schema,
      foreign_table_name table_name
    FROM information_schema.foreign_tables
    WHERE foreign_table_schema IN ('festapp_stage_a_public','festapp_stage_a_eshop')
    ORDER BY foreign_table_schema,foreign_table_name
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.source_schema,relation.table_name) INTO source_rows;
    IF relation.target_schema='public' AND relation.table_name LIKE 'client_%' THEN
      excluded_rows:=excluded_rows+source_rows;
      excluded_tables:=excluded_tables+1;
      CONTINUE;
    END IF;

    EXECUTE format('SELECT count(*) FROM %I.%I',relation.target_schema,relation.table_name) INTO before_rows;
    column_list:='';
    select_list:='';
    FOR target_column IN
      SELECT column_name,ordinal_position,format_type(a.atttypid,a.atttypmod) sql_type
      FROM information_schema.columns c
      JOIN pg_class pc ON pc.relname=c.table_name
      JOIN pg_namespace pn ON pn.oid=pc.relnamespace AND pn.nspname=c.table_schema
      JOIN pg_attribute a ON a.attrelid=pc.oid AND a.attname=c.column_name
      WHERE c.table_schema=relation.target_schema AND c.table_name=relation.table_name
        AND c.is_generated='NEVER'
      ORDER BY c.ordinal_position
    LOOP
      mapping_table:=NULL;
      own_strict_mapping:=false;

      SELECT domain.mapping_table,
        (domain.mapping_table=relation.target_schema||'.'||relation.table_name AND target_column.sql_type IN ('smallint','integer','bigint'))
      INTO mapping_table,own_strict_mapping
      FROM festapp_a_mapping_domains domain
      WHERE domain.target_schema=relation.target_schema AND domain.target_table=relation.table_name
        AND domain.target_column=target_column.column_name;

      IF mapping_table IS NULL AND relation.target_schema||'.'||relation.table_name||'.'||target_column.column_name IN (
        'eshop.transaction_pairing_events.actor_id','public.account_deletion_requests.user_id',
        'public.client_commit_components.user_id','public.log_notifications.user_id',
        'public.news_notification_outbox.user_id','public.occasion_users.user',
        'public.reception_rate_limits.actor','public.user_companions.companion',
        'public.user_companions.user','public.user_login_qr_credentials.user','public.user_news.user'
      ) THEN
        mapping_table:='auth.users';
      END IF;

      IF mapping_table IS NULL THEN
        mapping_table:=CASE relation.target_schema||'.'||relation.table_name||'.'||target_column.column_name
          WHEN 'public.events.occasion' THEN 'public.occasions'
          WHEN 'public.email_templates.unit' THEN 'public.units'
          WHEN 'public.log_app_config.organization' THEN 'public.organizations'
          WHEN 'public.role_info.occasion' THEN 'public.occasions'
          ELSE NULL
        END;
      END IF;

      IF relation.target_schema='public' AND relation.table_name='organizations'
        AND target_column.column_name='data' THEN
        expression:=format($expression$
          (CASE WHEN s.data ? 'DEFAULT_OCCASION' THEN jsonb_set(
            CASE WHEN s.data ? 'REPRESENTATIVE_OCCASION' THEN jsonb_set(
              CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,
                '{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false)
              ELSE s.data END,
              '{REPRESENTATIVE_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'REPRESENTATIVE_OCCASION'),s.data->'REPRESENTATIVE_OCCASION'),false)
            ELSE CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,
              '{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false)
            ELSE s.data END END,
            '{DEFAULT_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'DEFAULT_OCCASION'),s.data->'DEFAULT_OCCASION'),false)
          ELSE CASE WHEN s.data ? 'REPRESENTATIVE_OCCASION' THEN jsonb_set(
            CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,
              '{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false)
            ELSE s.data END,
            '{REPRESENTATIVE_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'REPRESENTATIVE_OCCASION'),s.data->'REPRESENTATIVE_OCCASION'),false)
          ELSE CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,
            '{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false)
          ELSE s.data END END END) - 'ONESIGNAL_REST_API_KEY'
        $expression$,import_run);
      ELSIF relation.target_schema='eshop' AND relation.table_name='planned_changes'
        AND target_column.column_name='subject_id' THEN
        expression:=format('CASE WHEN s.change_type LIKE ''forms.%%'' THEN coalesce((SELECT m.target_id::bigint FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.forms'' AND m.source_id=s.subject_id::text),s.subject_id) ELSE s.subject_id END',import_run);
      ELSIF mapping_table IS NULL THEN
        expression:=format('s.%I',target_column.column_name);
      ELSIF own_strict_mapping THEN
        expression:=format('(SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=%L AND m.source_id=s.%I::text)',
          target_column.sql_type,import_run,mapping_table,target_column.column_name);
      ELSE
        expression:=format('coalesce((SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=%L AND m.source_id=s.%I::text),s.%I)',
          target_column.sql_type,import_run,mapping_table,target_column.column_name,target_column.column_name);
      END IF;
      column_list:=column_list||CASE WHEN column_list='' THEN '' ELSE ', ' END||format('%I',target_column.column_name);
      select_list:=select_list||CASE WHEN select_list='' THEN '' ELSE ', ' END||expression;
    END LOOP;

    IF relation.target_schema='public' AND relation.table_name='supabase_migrations' THEN
      EXECUTE format('SELECT count(*) FROM %I.%I s WHERE NOT EXISTS (SELECT 1 FROM public.supabase_migrations t WHERE t.version=s.version)',relation.source_schema,relation.table_name) INTO expected_rows;
      EXECUTE format('INSERT INTO public.supabase_migrations (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s WHERE NOT EXISTS (SELECT 1 FROM public.supabase_migrations t WHERE t.version=s.version)',
        column_list,select_list,relation.source_schema,relation.table_name);
      GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    ELSIF relation.target_schema='public' AND relation.table_name='user_info' THEN
      EXECUTE format('INSERT INTO public.user_info (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s WHERE NOT EXISTS (SELECT 1 FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.user_info'' AND m.source_id=s.id::text)',
        column_list,select_list,relation.source_schema,relation.table_name,import_run);
      expected_rows:=source_rows-collision_profiles;
      GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    ELSE
      EXECUTE format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s',
        relation.target_schema,relation.table_name,column_list,select_list,relation.source_schema,relation.table_name);
      expected_rows:=source_rows;
      GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    END IF;
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.target_schema,relation.table_name) INTO after_rows;
    IF inserted_rows<>expected_rows OR after_rows-before_rows<>expected_rows THEN
      RAISE EXCEPTION 'a row mismatch %.%: expected %, inserted %, delta %',relation.target_schema,relation.table_name,expected_rows,inserted_rows,after_rows-before_rows;
    END IF;
  END LOOP;

  INSERT INTO public.organization_notification_secrets(
    organization,
    onesignal_rest_api_key
  )
  SELECT mapping.target_id::bigint, source.data->>'ONESIGNAL_REST_API_KEY'
  FROM festapp_stage_a_public.organizations source
  JOIN festapp_merge.id_mappings mapping
    ON mapping.run_id=import_run
    AND mapping.source_table='public.organizations'
    AND mapping.source_id=source.id::text
  WHERE nullif(source.data->>'ONESIGNAL_REST_API_KEY', '') IS NOT NULL
  ON CONFLICT (organization) DO NOTHING;

  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.organizations source
    JOIN festapp_merge.id_mappings mapping
      ON mapping.run_id=import_run
      AND mapping.source_table='public.organizations'
      AND mapping.source_id=source.id::text
    WHERE nullif(source.data->>'ONESIGNAL_REST_API_KEY', '') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.organization_notification_secrets secret
        WHERE secret.organization=mapping.target_id::bigint
      )
  ) OR EXISTS (
    SELECT 1 FROM public.organizations
    WHERE data ? 'ONESIGNAL_REST_API_KEY'
  ) THEN
    RAISE EXCEPTION 'source a OneSignal credentials did not converge to server-only storage';
  END IF;

  INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason)
  SELECT import_run,'public.user_info',jsonb_build_object('id',s.id),to_jsonb(s),
    'identity-merged-default-profile-preferred-review-required'
  FROM festapp_stage_a_public.user_info s
  JOIN festapp_merge.id_mappings m ON m.run_id=import_run AND m.source_table='public.user_info' AND m.source_id=s.id::text;
  IF (SELECT count(*) FROM festapp_merge.quarantined_rows WHERE run_id=import_run AND source_table='public.user_info')<>collision_profiles THEN
    RAISE EXCEPTION 'collision profile preservation count mismatch';
  END IF;

  FOR foreign_key IN
    SELECT con.conname,child_ns.nspname child_schema,child.relname child_table,
      parent_ns.nspname parent_schema,parent.relname parent_table,con.conkey,con.confkey
    FROM pg_constraint con
    JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
    JOIN pg_class parent ON parent.oid=con.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
    WHERE con.contype='f' AND child_ns.nspname IN ('public','eshop')
      AND parent_ns.nspname IN ('public','eshop')
  LOOP
    SELECT string_agg(format('c.%I IS NOT NULL',child_col.attname),' AND ' ORDER BY key_pair.ord),
      string_agg(format('c.%I=p.%I',child_col.attname,parent_col.attname),' AND ' ORDER BY key_pair.ord)
    INTO child_not_null,join_expression
    FROM unnest(foreign_key.conkey,foreign_key.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord)
    JOIN pg_attribute child_col ON child_col.attrelid=(format('%I.%I',foreign_key.child_schema,foreign_key.child_table))::regclass AND child_col.attnum=key_pair.child_attnum
    JOIN pg_attribute parent_col ON parent_col.attrelid=(format('%I.%I',foreign_key.parent_schema,foreign_key.parent_table))::regclass AND parent_col.attnum=key_pair.parent_attnum;
    EXECUTE format('SELECT count(*) FROM %I.%I c WHERE %s AND NOT EXISTS (SELECT 1 FROM %I.%I p WHERE %s)',
      foreign_key.child_schema,foreign_key.child_table,child_not_null,foreign_key.parent_schema,foreign_key.parent_table,join_expression) INTO orphan_rows;
    IF orphan_rows<>0 THEN RAISE EXCEPTION 'foreign key % has % orphan rows',foreign_key.conname,orphan_rows; END IF;
  END LOOP;

  FOR sequence_record IN
    SELECT table_schema,table_name,column_name,pg_get_serial_sequence(format('%I.%I',table_schema,table_name),column_name) sequence_name
    FROM information_schema.columns WHERE table_schema IN ('public','eshop') AND (is_identity='YES' OR column_default LIKE 'nextval(%')
  LOOP
    IF sequence_record.sequence_name IS NOT NULL THEN
      EXECUTE format('SELECT setval(%L,coalesce(max(%I),1),max(%I) IS NOT NULL) FROM %I.%I',
        sequence_record.sequence_name,sequence_record.column_name,sequence_record.column_name,sequence_record.table_schema,sequence_record.table_name);
    END IF;
  END LOOP;

  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'a-relational-import','pass',jsonb_build_object(
      'source_tables',(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_a_public','festapp_stage_a_eshop')),
      'id_mappings',(SELECT count(*) FROM festapp_merge.id_mappings WHERE run_id=import_run),
      'excluded_derived_tables',excluded_tables,'excluded_derived_rows',excluded_rows,'application_foreign_key_orphans',0,'auth_foreign_keys_deferred',true)),
    (import_run,'a-identity-profile-review','blocked',jsonb_build_object('preserved_profiles',collision_profiles,'canonical_rule','default-profile-preferred')),
    (import_run,'a-client-derived-state-rebuild','blocked',jsonb_build_object('tables',excluded_tables,'rows',excluded_rows,'raw_snapshot_preserved',true,'requires_forced_full_sync',true)),
    (import_run,'a-auth-and-storage-import','blocked',jsonb_build_object('auth_users',0,'storage_objects',0));
  UPDATE festapp_merge.import_runs SET status='blocked' WHERE run_id=import_run;
END
$import$;

COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'status',status,
  'quarantined_profiles',(SELECT count(*) FROM festapp_merge.quarantined_rows WHERE run_id=import_runs.run_id AND source_table='public.user_info'),
  'validation_results',(SELECT jsonb_object_agg(check_name,status) FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id),
  'auth_users',(SELECT count(*) FROM auth.users),'storage_objects',(SELECT count(*) FROM storage.objects)
) FROM festapp_merge.import_runs WHERE source_alias='a'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Source a relational rehearsal import completed with profile and derived-state gates blocked."
echo "Evidence: $RUN_DIR"
