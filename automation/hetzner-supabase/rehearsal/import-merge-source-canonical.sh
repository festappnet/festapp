#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_FILE="${FESTAPP_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly DRIFT_POLICY_FILE="${FESTAPP_SOURCE_DRIFT_POLICY:-$SCRIPT_DIR/../merge/source-schema-drift-policy.json}"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly SOURCE_ALIAS="${FESTAPP_MERGE_SOURCE_ALIAS:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-merge-source-relational-data-with-derived-state-blocked" ]] || fail "set the merge-source relational import acknowledgement"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$SOURCE_ALIAS" =~ ^[a-z][a-z0-9_]{0,19}$ ]] || fail "invalid merge source alias"
[[ -f "$REGISTRY_FILE" && "$(jq -r --arg source "$SOURCE_ALIAS" '.sources[]|select(.alias==$source)|.role' "$REGISTRY_FILE")" == "merge-source" ]] || fail "source is not a registered merge source"
[[ -f "$DRIFT_POLICY_FILE" ]] || fail "source schema-drift policy is missing"
readonly POLICY_JSON="$(jq -cer --arg source "$SOURCE_ALIAS" '.sources[$source] | select(.source_schema_sha256|test("^[0-9a-f]{64}$"))' "$DRIFT_POLICY_FILE")"
readonly POLICY_SHA256="$(sha256sum "$DRIFT_POLICY_FILE" | awk '{print $1}')"
readonly SOURCE_REF="$(jq -r --arg source "$SOURCE_ALIAS" '.sources[]|select(.alias==$source)|.project_ref' "$REGISTRY_FILE")"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run as root on the approved rehearsal host"

readonly STAGE_PUBLIC="festapp_stage_${SOURCE_ALIAS}_public"
readonly STAGE_ESHOP="festapp_stage_${SOURCE_ALIAS}_eshop"
readonly STAGE_MANAGED="festapp_stage_${SOURCE_ALIAS}_managed"
cd "$COMPOSE_DIR"
docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }

readonly MAPPING_COUNT="$(psql_main -Atqc "SELECT count(*) FROM festapp_merge.id_mappings m JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='$SOURCE_ALIAS' AND r.status='prepared'")"
[[ "$MAPPING_COUNT" =~ ^[1-9][0-9]*$ ]] || fail "merge-source mapping set is empty or invalid ($MAPPING_COUNT)"
readonly SOURCE_TABLES="$(psql_main -Atqc "SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('$STAGE_PUBLIC','$STAGE_ESHOP')")"
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),(SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS' AND status='prepared'),(SELECT count(*) FROM festapp_merge.quarantined_rows q JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='$SOURCE_ALIAS'),(SELECT source_schema_fingerprint=(('$POLICY_JSON'::jsonb)->>'source_schema_sha256') FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS'),(SELECT count(*) FROM $STAGE_MANAGED.provenance WHERE source_alias='$SOURCE_ALIAS' AND source_project_ref='$SOURCE_REF'))")"
[[ "$STATE" == "17|1|0|t|1" && "$SOURCE_TABLES" =~ ^[1-9][0-9]*$ ]] || fail "target is not an approved merge-source import state ($STATE tables=$SOURCE_TABLES)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/$SOURCE_ALIAS-canonical-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
psql_main -Atqc "SELECT jsonb_build_object('source_alias','$SOURCE_ALIAS','source_tables',$SOURCE_TABLES,'id_mappings',$MAPPING_COUNT,'auth_users',(SELECT count(*) FROM auth.users),'storage_objects',(SELECT count(*) FROM storage.objects),'drift_policy_sha256','$POLICY_SHA256')" >"$RUN_DIR/preflight.json"
chmod 0600 "$RUN_DIR/preflight.json"

psql_main -v source_alias="$SOURCE_ALIAS" -v stage_public="$STAGE_PUBLIC" -v stage_eshop="$STAGE_ESHOP" -v policy_json="$POLICY_JSON" -v policy_sha="$POLICY_SHA256" <<'SQL'
BEGIN;
SET LOCAL session_replication_role=replica;
SET LOCAL statement_timeout=0;

CREATE TEMP TABLE merge_source_missing_tables AS
SELECT split_part("table",'.',1) target_schema,split_part("table",'.',2) table_name,expected_rows,disposition
FROM jsonb_to_recordset(:'policy_json'::jsonb->'missing_target_tables') AS p("table" text,expected_rows bigint,disposition text);
CREATE TEMP TABLE merge_source_only_columns AS
SELECT split_part("table",'.',1) target_schema,split_part("table",'.',2) table_name,"column" column_name,expected_non_null_rows,disposition
FROM jsonb_to_recordset(:'policy_json'::jsonb->'source_only_columns') AS p("table" text,"column" text,expected_non_null_rows bigint,disposition text);
CREATE TEMP TABLE merge_source_zero_shape AS
SELECT split_part("table",'.',1) target_schema,split_part("table",'.',2) table_name,expected_rows,disposition
FROM jsonb_to_recordset(:'policy_json'::jsonb->'zero_row_shape_exceptions') AS p("table" text,expected_rows bigint,disposition text);
CREATE TEMP TABLE merge_source_row_transforms AS
SELECT split_part("table",'.',1) target_schema,split_part("table",'.',2) table_name,transform,unambiguous_disposition,ambiguous_disposition
FROM jsonb_to_recordset(:'policy_json'::jsonb->'row_transforms') AS p("table" text,transform text,unambiguous_disposition text,ambiguous_disposition text);
CREATE TEMP TABLE merge_source_profile_dedup_policy AS
SELECT split_part("table",'.',1) target_schema,split_part("table",'.',2) table_name,transform,expected_groups,expected_rows,secondary_disposition
FROM jsonb_to_recordset(:'policy_json'::jsonb->'profile_email_deduplication') AS p("table" text,transform text,expected_groups bigint,expected_rows bigint,secondary_disposition text);
CREATE TEMP TABLE merge_source_profile_email_decisions(source_id uuid PRIMARY KEY,keep_email boolean NOT NULL);

CREATE TEMP TABLE merge_source_mapping_domains AS
WITH RECURSIVE import_run AS (
  SELECT run_id FROM festapp_merge.import_runs WHERE source_alias=:'source_alias' AND status='prepared'
), domains(target_schema,target_table,target_column,mapping_table) AS (
  SELECT n.nspname,c.relname,a.attname,CASE WHEN n.nspname='public' AND c.relname='user_info' THEN 'auth.users' ELSE n.nspname||'.'||c.relname END
  FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN LATERAL unnest(con.conkey) k(attnum) ON true JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum
  WHERE con.contype='p' AND cardinality(con.conkey)=1 AND n.nspname IN ('public','eshop')
    AND EXISTS (SELECT 1 FROM festapp_merge.id_mappings m,import_run r WHERE m.run_id=r.run_id AND m.source_table=n.nspname||'.'||c.relname)
  UNION
  SELECT child_ns.nspname,child.relname,child_col.attname,parent_domain.mapping_table
  FROM domains parent_domain
  JOIN pg_namespace parent_ns ON parent_ns.nspname=parent_domain.target_schema
  JOIN pg_class parent ON parent.relnamespace=parent_ns.oid AND parent.relname=parent_domain.target_table
  JOIN pg_attribute parent_col ON parent_col.attrelid=parent.oid AND parent_col.attname=parent_domain.target_column
  JOIN pg_constraint con ON con.contype='f' AND con.confrelid=parent.oid
  JOIN LATERAL unnest(con.conkey,con.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord) ON key_pair.parent_attnum=parent_col.attnum
  JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
  JOIN pg_attribute child_col ON child_col.attrelid=child.oid AND child_col.attnum=key_pair.child_attnum
)
SELECT DISTINCT target_schema,target_table,target_column,mapping_table FROM domains;

SELECT set_config('festapp.merge_source_alias',:'source_alias',true);
SELECT set_config('festapp.merge_stage_public',:'stage_public',true);
SELECT set_config('festapp.merge_stage_eshop',:'stage_eshop',true);
SELECT set_config('festapp.merge_policy_sha',:'policy_sha',true);

DO $import$
DECLARE
  import_run uuid; relation record; target_column record; policy_record record; source_rows bigint;
  before_rows bigint; after_rows bigint; expected_rows bigint; inserted_rows bigint; excluded_rows bigint:=0;
  excluded_tables integer:=0; quarantined_drift bigint:=0; column_list text; select_list text; expression text;
  mapping_table text; own_strict_mapping boolean; sequence_record record; foreign_key record;
  child_not_null text; join_expression text; orphan_rows bigint; collision_profiles bigint;
  reset_token_collisions bigint:=0; actual text; expected text;
  v_source_alias text:=current_setting('festapp.merge_source_alias');
  stage_public text:=current_setting('festapp.merge_stage_public');
  stage_eshop text:=current_setting('festapp.merge_stage_eshop');
  policy_sha text:=current_setting('festapp.merge_policy_sha');
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE import_runs.source_alias=v_source_alias AND status='prepared';
  SELECT count(*) INTO collision_profiles FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='public.user_info';

  SELECT coalesce(string_agg(source_schema||'.'||foreign_table_name,',' ORDER BY source_schema,foreign_table_name),'') INTO actual
  FROM (SELECT replace(foreign_table_schema,'festapp_stage_'||v_source_alias||'_','') source_schema,foreign_table_name
    FROM information_schema.foreign_tables f WHERE foreign_table_schema IN (stage_public,stage_eshop)
      AND to_regclass(replace(foreign_table_schema,'festapp_stage_'||v_source_alias||'_','')||'.'||quote_ident(foreign_table_name)) IS NULL) missing;
  SELECT coalesce(string_agg(target_schema||'.'||table_name,',' ORDER BY target_schema,table_name),'') INTO expected FROM merge_source_missing_tables;
  IF actual<>expected THEN RAISE EXCEPTION 'unregistered missing-target table drift: actual %, expected %',actual,expected; END IF;

  SELECT coalesce(string_agg(source_schema||'.'||table_name||'.'||column_name,',' ORDER BY source_schema,table_name,column_name),'') INTO actual
  FROM (SELECT replace(c.table_schema,'festapp_stage_'||v_source_alias||'_','') source_schema,c.table_name,c.column_name
    FROM information_schema.columns c WHERE c.table_schema IN (stage_public,stage_eshop)
      AND to_regclass(replace(c.table_schema,'festapp_stage_'||v_source_alias||'_','')||'.'||quote_ident(c.table_name)) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM information_schema.columns t WHERE t.table_schema=replace(c.table_schema,'festapp_stage_'||v_source_alias||'_','') AND t.table_name=c.table_name AND t.column_name=c.column_name)) drift;
  SELECT coalesce(string_agg(target_schema||'.'||table_name||'.'||column_name,',' ORDER BY target_schema,table_name,column_name),'') INTO expected FROM merge_source_only_columns;
  IF actual<>expected THEN RAISE EXCEPTION 'unregistered source-only column drift: actual %, expected %',actual,expected; END IF;

  FOR policy_record IN SELECT * FROM merge_source_missing_tables LOOP
    EXECUTE format('SELECT count(*) FROM festapp_stage_%I_%I.%I',v_source_alias,policy_record.target_schema,policy_record.table_name) INTO source_rows;
    IF source_rows<>policy_record.expected_rows OR policy_record.disposition<>'quarantine-source-row' THEN RAISE EXCEPTION 'missing-table policy mismatch %.%: %/%',policy_record.target_schema,policy_record.table_name,source_rows,policy_record.expected_rows; END IF;
    EXECUTE format('INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason) SELECT %L,%L,coalesce(jsonb_build_object(''id'',to_jsonb(s)->''id''),to_jsonb(s)),to_jsonb(s),%L FROM festapp_stage_%I_%I.%I s',import_run,policy_record.target_schema||'.'||policy_record.table_name,'registered-missing-target-table',v_source_alias,policy_record.target_schema,policy_record.table_name);
    GET DIAGNOSTICS inserted_rows=ROW_COUNT; quarantined_drift:=quarantined_drift+inserted_rows;
  END LOOP;

  IF EXISTS (SELECT 1 FROM merge_source_profile_dedup_policy WHERE target_schema='public' AND table_name='user_info' AND transform='preserve-accounts-null-secondary-profile-email-v1' AND secondary_disposition='quarantine-source-row') THEN
    EXECUTE format($sql$
      INSERT INTO merge_source_profile_email_decisions(source_id,keep_email)
      WITH duplicate_profiles AS (
        SELECT u.id,u.organization,lower(btrim(u.email_readonly)) normalized_email,u.created_at,
          (SELECT count(*) FROM festapp_stage_%1$I_public.event_users e WHERE e."user"=u.id) +
          (SELECT count(*) FROM festapp_stage_%1$I_public.event_users_saved e WHERE e."user"=u.id) activity_rows,
          nullif(auth.row_data->>'last_sign_in_at','')::timestamptz last_sign_in_at
        FROM festapp_stage_%1$I_public.user_info u
        JOIN festapp_stage_%1$I_managed.rows auth ON auth.source_schema='auth' AND auth.source_table='users' AND auth.row_data->>'id'=u.id::text
        WHERE u.email_readonly IS NOT NULL AND EXISTS (
          SELECT 1 FROM festapp_stage_%1$I_public.user_info other
          WHERE other.organization=u.organization AND other.id<>u.id
            AND lower(btrim(other.email_readonly))=lower(btrim(u.email_readonly)))
      ), ranked AS (
        SELECT id,row_number() OVER (PARTITION BY organization,normalized_email ORDER BY activity_rows DESC,last_sign_in_at DESC NULLS LAST,created_at,id) email_rank
        FROM duplicate_profiles
      ) SELECT id,email_rank=1 FROM ranked
    $sql$,v_source_alias);
    EXECUTE format('SELECT count(*),count(DISTINCT (organization,lower(btrim(email_readonly)))) FROM festapp_stage_%I_public.user_info WHERE id IN (SELECT source_id FROM merge_source_profile_email_decisions)',v_source_alias) INTO source_rows,expected_rows;
    SELECT p.expected_rows,p.expected_groups INTO before_rows,after_rows FROM merge_source_profile_dedup_policy p;
    IF source_rows<>before_rows OR expected_rows<>after_rows OR (SELECT count(*) FROM merge_source_profile_email_decisions WHERE keep_email)<>after_rows THEN
      RAISE EXCEPTION 'profile e-mail deduplication policy mismatch: rows %/%, groups %/%',source_rows,before_rows,expected_rows,after_rows;
    END IF;
    EXECUTE format('INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason) SELECT %L,''public.user_info'',jsonb_build_object(''id'',s.id),to_jsonb(s),''normalized-profile-email-duplicate-preserved-with-null-secondary-email'' FROM festapp_stage_%I_public.user_info s JOIN merge_source_profile_email_decisions d ON d.source_id=s.id WHERE NOT d.keep_email',import_run,v_source_alias);
    GET DIAGNOSTICS inserted_rows=ROW_COUNT; quarantined_drift:=quarantined_drift+inserted_rows;
    IF inserted_rows<>source_rows-expected_rows THEN RAISE EXCEPTION 'profile e-mail secondary quarantine mismatch'; END IF;
  END IF;
  FOR policy_record IN SELECT * FROM merge_source_only_columns LOOP
    EXECUTE format('SELECT count(*) FROM festapp_stage_%I_%I.%I WHERE %I IS NOT NULL',v_source_alias,policy_record.target_schema,policy_record.table_name,policy_record.column_name) INTO source_rows;
    IF source_rows<>policy_record.expected_non_null_rows OR policy_record.disposition NOT IN ('quarantine-source-row','omit-empty-column-drift') OR (policy_record.disposition='omit-empty-column-drift' AND source_rows<>0) THEN RAISE EXCEPTION 'source-only column policy mismatch %.%.%: %/%',policy_record.target_schema,policy_record.table_name,policy_record.column_name,source_rows,policy_record.expected_non_null_rows; END IF;
    IF policy_record.disposition='quarantine-source-row' THEN
      EXECUTE format('INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason) SELECT %L,%L,jsonb_build_object(''id'',to_jsonb(s)->''id''),jsonb_build_object(''id'',to_jsonb(s)->''id'',%L,to_jsonb(s)->%L),%L FROM festapp_stage_%I_%I.%I s WHERE %I IS NOT NULL',import_run,policy_record.target_schema||'.'||policy_record.table_name,policy_record.column_name,policy_record.column_name,'registered-source-only-column',v_source_alias,policy_record.target_schema,policy_record.table_name,policy_record.column_name);
      GET DIAGNOSTICS inserted_rows=ROW_COUNT; quarantined_drift:=quarantined_drift+inserted_rows;
    END IF;
  END LOOP;

  IF EXISTS (SELECT 1 FROM merge_source_row_transforms WHERE target_schema='public' AND table_name='user_companions' AND transform='shared-occasion-companion-v1' AND unambiguous_disposition='import-with-canonical-columns' AND ambiguous_disposition='quarantine-source-row') THEN
    EXECUTE format($sql$
      WITH shared AS (
        SELECT c."user",c.companion,c.created_at,count(DISTINCT owner.occasion) shared_occasions,min(owner.occasion) source_occasion
        FROM festapp_stage_%1$I_public.user_companions c
        JOIN festapp_stage_%1$I_public.occasion_users owner ON owner."user"=c."user"
        JOIN festapp_stage_%1$I_public.occasion_users companion ON companion."user"=c.companion AND companion.occasion=owner.occasion
        GROUP BY c."user",c.companion,c.created_at
      ), mapped AS (
        SELECT coalesce(owner_map.target_id::uuid,s."user") owner,coalesce(companion_map.target_id::uuid,s.companion) companion,
          occasion_map.target_id::bigint occasion,s.created_at
        FROM shared s
        LEFT JOIN festapp_merge.id_mappings owner_map ON owner_map.run_id=%2$L AND owner_map.source_table='auth.users' AND owner_map.source_id=s."user"::text
        LEFT JOIN festapp_merge.id_mappings companion_map ON companion_map.run_id=%2$L AND companion_map.source_table='auth.users' AND companion_map.source_id=s.companion::text
        JOIN festapp_merge.id_mappings occasion_map ON occasion_map.run_id=%2$L AND occasion_map.source_table='public.occasions' AND occasion_map.source_id=s.source_occasion::text
        WHERE s.shared_occasions=1
      ) INSERT INTO public.user_companions("user",created_at,companion,occasion,origin,created_by)
        SELECT owner,created_at,companion,occasion,'self_created',owner FROM mapped
    $sql$,v_source_alias,import_run);
    GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    EXECUTE format($sql$
      WITH shared AS (
        SELECT c."user",c.companion,c.created_at,count(DISTINCT owner.occasion) shared_occasions
        FROM festapp_stage_%1$I_public.user_companions c
        JOIN festapp_stage_%1$I_public.occasion_users owner ON owner."user"=c."user"
        JOIN festapp_stage_%1$I_public.occasion_users companion ON companion."user"=c.companion AND companion.occasion=owner.occasion
        GROUP BY c."user",c.companion,c.created_at
      ) INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason)
        SELECT %2$L,'public.user_companions',jsonb_build_object('user',"user",'companion',companion),
          jsonb_build_object('user',"user",'companion',companion,'created_at',created_at,'shared_occasion_count',shared_occasions),
          'ambiguous-legacy-companion-occasion' FROM shared WHERE shared_occasions<>1
    $sql$,v_source_alias,import_run);
    GET DIAGNOSTICS expected_rows=ROW_COUNT; quarantined_drift:=quarantined_drift+expected_rows;
    EXECUTE format('SELECT count(*) FROM festapp_stage_%I_public.user_companions',v_source_alias) INTO source_rows;
    IF inserted_rows+expected_rows<>source_rows THEN RAISE EXCEPTION 'legacy companion disposition mismatch: source %, imported %, quarantined %',source_rows,inserted_rows,expected_rows; END IF;
  END IF;
  FOR policy_record IN SELECT * FROM merge_source_zero_shape LOOP
    EXECUTE format('SELECT count(*) FROM festapp_stage_%I_%I.%I',v_source_alias,policy_record.target_schema,policy_record.table_name) INTO source_rows;
    IF source_rows<>0 OR source_rows<>policy_record.expected_rows OR policy_record.disposition<>'omit-empty-shape-drift' THEN RAISE EXCEPTION 'zero-row shape exception is no longer empty: %.%',policy_record.target_schema,policy_record.table_name; END IF;
  END LOOP;

  EXECUTE format('SELECT EXISTS (SELECT 1 FROM festapp_stage_%I_eshop.planned_changes WHERE change_type NOT LIKE ''forms.%%'')',v_source_alias) INTO own_strict_mapping;
  IF own_strict_mapping THEN RAISE EXCEPTION 'planned_changes contains an unregistered polymorphic subject type'; END IF;

  FOR relation IN
    SELECT foreign_table_schema source_schema,replace(foreign_table_schema,'festapp_stage_'||v_source_alias||'_','') target_schema,foreign_table_name table_name
    FROM information_schema.foreign_tables WHERE foreign_table_schema IN (stage_public,stage_eshop) ORDER BY foreign_table_schema,foreign_table_name
  LOOP
    IF EXISTS (SELECT 1 FROM merge_source_missing_tables p WHERE p.target_schema=relation.target_schema AND p.table_name=relation.table_name) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM merge_source_zero_shape p WHERE p.target_schema=relation.target_schema AND p.table_name=relation.table_name) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM merge_source_row_transforms p WHERE p.target_schema=relation.target_schema AND p.table_name=relation.table_name) THEN CONTINUE; END IF;
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.source_schema,relation.table_name) INTO source_rows;
    IF relation.target_schema='public' AND relation.table_name LIKE 'client_%' THEN excluded_rows:=excluded_rows+source_rows; excluded_tables:=excluded_tables+1; CONTINUE; END IF;
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.target_schema,relation.table_name) INTO before_rows;
    column_list:=''; select_list:='';
    FOR target_column IN
      SELECT c.column_name,c.ordinal_position,format_type(a.atttypid,a.atttypmod) sql_type
      FROM information_schema.columns c JOIN pg_class pc ON pc.relname=c.table_name JOIN pg_namespace pn ON pn.oid=pc.relnamespace AND pn.nspname=c.table_schema JOIN pg_attribute a ON a.attrelid=pc.oid AND a.attname=c.column_name
      WHERE c.table_schema=relation.target_schema AND c.table_name=relation.table_name AND c.is_generated='NEVER'
        AND EXISTS (SELECT 1 FROM information_schema.columns s WHERE s.table_schema=relation.source_schema AND s.table_name=relation.table_name AND s.column_name=c.column_name)
      ORDER BY c.ordinal_position
    LOOP
      mapping_table:=NULL; own_strict_mapping:=false;
      SELECT domain.mapping_table,(domain.mapping_table=relation.target_schema||'.'||relation.table_name AND target_column.sql_type IN ('smallint','integer','bigint')) INTO mapping_table,own_strict_mapping FROM merge_source_mapping_domains domain WHERE domain.target_schema=relation.target_schema AND domain.target_table=relation.table_name AND domain.target_column=target_column.column_name;
      IF mapping_table IS NULL AND relation.target_schema||'.'||relation.table_name||'.'||target_column.column_name IN ('eshop.transaction_pairing_events.actor_id','public.account_deletion_requests.user_id','public.client_commit_components.user_id','public.log_notifications.user_id','public.news_notification_outbox.user_id','public.occasion_users.user','public.reception_rate_limits.actor','public.user_companions.companion','public.user_companions.user','public.user_login_qr_credentials.user','public.user_news.user') THEN mapping_table:='auth.users'; END IF;
      IF mapping_table IS NULL THEN mapping_table:=CASE relation.target_schema||'.'||relation.table_name||'.'||target_column.column_name WHEN 'public.events.occasion' THEN 'public.occasions' WHEN 'public.email_templates.unit' THEN 'public.units' WHEN 'public.log_app_config.organization' THEN 'public.organizations' WHEN 'public.role_info.occasion' THEN 'public.occasions' ELSE NULL END; END IF;
      IF relation.target_schema='public' AND relation.table_name='user_info' AND target_column.column_name='email_readonly' THEN
        expression:='CASE WHEN EXISTS (SELECT 1 FROM merge_source_profile_email_decisions d WHERE d.source_id=s.id AND NOT d.keep_email) THEN NULL ELSE s.email_readonly END';
      ELSIF relation.target_schema='public' AND relation.table_name='organizations' AND target_column.column_name='data' THEN
        expression:=format($expression$
          (CASE WHEN s.data ? 'DEFAULT_OCCASION' THEN jsonb_set(
            CASE WHEN s.data ? 'REPRESENTATIVE_OCCASION' THEN jsonb_set(
              CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,
                '{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false)
              ELSE s.data END,
              '{REPRESENTATIVE_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'REPRESENTATIVE_OCCASION'),s.data->'REPRESENTATIVE_OCCASION'),false)
            ELSE CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,'{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false) ELSE s.data END END,
            '{DEFAULT_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'DEFAULT_OCCASION'),s.data->'DEFAULT_OCCASION'),false)
          ELSE CASE WHEN s.data ? 'REPRESENTATIVE_OCCASION' THEN jsonb_set(
            CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,'{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false) ELSE s.data END,
            '{REPRESENTATIVE_OCCASION}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.occasions' AND m.source_id=s.data->>'REPRESENTATIVE_OCCASION'),s.data->'REPRESENTATIVE_OCCASION'),false)
          ELSE CASE WHEN s.data ? 'DEFAULT_UNIT' THEN jsonb_set(s.data,'{DEFAULT_UNIT}',coalesce((SELECT to_jsonb(m.target_id::bigint) FROM festapp_merge.id_mappings m WHERE m.run_id=%1$L AND m.source_table='public.units' AND m.source_id=s.data->>'DEFAULT_UNIT'),s.data->'DEFAULT_UNIT'),false) ELSE s.data END END END) - 'ONESIGNAL_REST_API_KEY'
        $expression$,import_run);
      ELSIF relation.target_schema='eshop' AND relation.table_name='planned_changes' AND target_column.column_name='subject_id' THEN
        expression:=format('CASE WHEN s.change_type LIKE ''forms.%%'' THEN coalesce((SELECT m.target_id::bigint FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.forms'' AND m.source_id=s.subject_id::text),s.subject_id) ELSE s.subject_id END',import_run);
      ELSIF mapping_table IS NULL THEN expression:=format('s.%I',target_column.column_name);
      ELSIF own_strict_mapping THEN expression:=format('(SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=%L AND m.source_id=s.%I::text)',target_column.sql_type,import_run,mapping_table,target_column.column_name);
      ELSE expression:=format('coalesce((SELECT m.target_id::%s FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=%L AND m.source_id=s.%I::text),s.%I)',target_column.sql_type,import_run,mapping_table,target_column.column_name,target_column.column_name); END IF;
      column_list:=column_list||CASE WHEN column_list='' THEN '' ELSE ', ' END||format('%I',target_column.column_name);
      select_list:=select_list||CASE WHEN select_list='' THEN '' ELSE ', ' END||expression;
    END LOOP;
    IF relation.target_schema='public' AND relation.table_name='user_info' THEN
      EXECUTE format('INSERT INTO public.user_info (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s WHERE NOT EXISTS (SELECT 1 FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.user_info'' AND m.source_id=s.id::text)',column_list,select_list,relation.source_schema,relation.table_name,import_run);
      expected_rows:=source_rows-collision_profiles; GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    ELSIF relation.target_schema='public' AND relation.table_name='user_reset_token' THEN
      EXECUTE format('INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason) SELECT %L,''public.user_reset_token'',jsonb_build_object(''user'',s."user"),jsonb_build_object(''user'',s."user",''created_at'',s.created_at,''token_redacted'',true),''identity-merged-existing-canonical-reset-token-preferred'' FROM %I.%I s WHERE EXISTS (SELECT 1 FROM public.user_reset_token t WHERE t."user"=coalesce((SELECT m.target_id::uuid FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s."user"::text),s."user"))',import_run,relation.source_schema,relation.table_name,import_run);
      GET DIAGNOSTICS reset_token_collisions=ROW_COUNT;
      EXECUTE format('INSERT INTO public.user_reset_token (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s WHERE NOT EXISTS (SELECT 1 FROM public.user_reset_token t WHERE t."user"=coalesce((SELECT m.target_id::uuid FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''auth.users'' AND m.source_id=s."user"::text),s."user"))',column_list,select_list,relation.source_schema,relation.table_name,import_run);
      expected_rows:=source_rows-reset_token_collisions; GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    ELSE
      EXECUTE format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I s',relation.target_schema,relation.table_name,column_list,select_list,relation.source_schema,relation.table_name);
      expected_rows:=source_rows; GET DIAGNOSTICS inserted_rows=ROW_COUNT;
    END IF;
    EXECUTE format('SELECT count(*) FROM %I.%I',relation.target_schema,relation.table_name) INTO after_rows;
    IF inserted_rows<>expected_rows OR after_rows-before_rows<>expected_rows THEN RAISE EXCEPTION 'merge-source row mismatch %.%: expected %, inserted %, delta %',relation.target_schema,relation.table_name,expected_rows,inserted_rows,after_rows-before_rows; END IF;
  END LOOP;

  EXECUTE format('INSERT INTO public.organization_notification_secrets(organization,onesignal_rest_api_key) SELECT m.target_id::bigint,s.data->>''ONESIGNAL_REST_API_KEY'' FROM festapp_stage_%I_public.organizations s JOIN festapp_merge.id_mappings m ON m.run_id=%L AND m.source_table=''public.organizations'' AND m.source_id=s.id::text WHERE nullif(s.data->>''ONESIGNAL_REST_API_KEY'','''') IS NOT NULL ON CONFLICT (organization) DO NOTHING',v_source_alias,import_run);
  IF EXISTS (SELECT 1 FROM public.organizations WHERE data ? 'ONESIGNAL_REST_API_KEY') THEN RAISE EXCEPTION 'OneSignal credentials remain in client-visible organization JSON'; END IF;
  EXECUTE format('INSERT INTO festapp_merge.quarantined_rows(run_id,source_table,source_primary_key,source_row,reason) SELECT %L,''public.user_info'',jsonb_build_object(''id'',s.id),to_jsonb(s),''identity-merged-existing-canonical-profile-preferred'' FROM festapp_stage_%I_public.user_info s JOIN festapp_merge.id_mappings m ON m.run_id=%L AND m.source_table=''public.user_info'' AND m.source_id=s.id::text',import_run,v_source_alias,import_run);
  GET DIAGNOSTICS inserted_rows=ROW_COUNT;
  IF inserted_rows<>collision_profiles THEN RAISE EXCEPTION 'collision profile quarantine count mismatch'; END IF;

  FOR foreign_key IN SELECT con.conname,child_ns.nspname child_schema,child.relname child_table,parent_ns.nspname parent_schema,parent.relname parent_table,con.conkey,con.confkey FROM pg_constraint con JOIN pg_class child ON child.oid=con.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace JOIN pg_class parent ON parent.oid=con.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace WHERE con.contype='f' AND child_ns.nspname IN ('public','eshop') AND parent_ns.nspname IN ('public','eshop') LOOP
    SELECT string_agg(format('c.%I IS NOT NULL',child_col.attname),' AND ' ORDER BY key_pair.ord),string_agg(format('c.%I=p.%I',child_col.attname,parent_col.attname),' AND ' ORDER BY key_pair.ord) INTO child_not_null,join_expression FROM unnest(foreign_key.conkey,foreign_key.confkey) WITH ORDINALITY key_pair(child_attnum,parent_attnum,ord) JOIN pg_attribute child_col ON child_col.attrelid=(format('%I.%I',foreign_key.child_schema,foreign_key.child_table))::regclass AND child_col.attnum=key_pair.child_attnum JOIN pg_attribute parent_col ON parent_col.attrelid=(format('%I.%I',foreign_key.parent_schema,foreign_key.parent_table))::regclass AND parent_col.attnum=key_pair.parent_attnum;
    EXECUTE format('SELECT count(*) FROM %I.%I c WHERE %s AND NOT EXISTS (SELECT 1 FROM %I.%I p WHERE %s)',foreign_key.child_schema,foreign_key.child_table,child_not_null,foreign_key.parent_schema,foreign_key.parent_table,join_expression) INTO orphan_rows;
    IF orphan_rows<>0 THEN RAISE EXCEPTION 'foreign key % has % orphan rows',foreign_key.conname,orphan_rows; END IF;
  END LOOP;
  FOR sequence_record IN SELECT table_schema,table_name,column_name,pg_get_serial_sequence(format('%I.%I',table_schema,table_name),column_name) sequence_name FROM information_schema.columns WHERE table_schema IN ('public','eshop') AND (is_identity='YES' OR column_default LIKE 'nextval(%') LOOP
    IF sequence_record.sequence_name IS NOT NULL THEN EXECUTE format('SELECT setval(%L,coalesce(max(%I),1),max(%I) IS NOT NULL) FROM %I.%I',sequence_record.sequence_name,sequence_record.column_name,sequence_record.column_name,sequence_record.table_schema,sequence_record.table_name); END IF;
  END LOOP;
  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,v_source_alias||'-relational-import','pass',jsonb_build_object('source_tables',(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN (stage_public,stage_eshop)),'id_mappings',(SELECT count(*) FROM festapp_merge.id_mappings WHERE run_id=import_run),'excluded_derived_tables',excluded_tables,'excluded_derived_rows',excluded_rows,'quarantined_schema_drift_rows',quarantined_drift,'quarantined_reset_token_collisions',reset_token_collisions,'schema_drift_policy_sha256',policy_sha,'application_foreign_key_orphans',0,'auth_foreign_keys_deferred',true)),
    (import_run,v_source_alias||'-identity-profile-review','blocked',jsonb_build_object('preserved_profiles',collision_profiles,'canonical_rule','existing-canonical-profile-preferred')),
    (import_run,v_source_alias||'-client-derived-state-rebuild','blocked',jsonb_build_object('tables',excluded_tables,'rows',excluded_rows,'raw_snapshot_preserved',true,'requires_forced_full_sync',true)),
    (import_run,v_source_alias||'-auth-and-storage-import','blocked',jsonb_build_object('auth_users',0,'storage_objects',0));
  UPDATE festapp_merge.import_runs SET status='blocked' WHERE run_id=import_run;
END
$import$;
COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object('status',status,'source_alias',source_alias,'quarantined_rows',(SELECT count(*) FROM festapp_merge.quarantined_rows WHERE run_id=import_runs.run_id),'validation_results',(SELECT jsonb_object_agg(check_name,status) FROM festapp_merge.validation_results WHERE run_id=import_runs.run_id),'auth_users',(SELECT count(*) FROM auth.users),'storage_objects',(SELECT count(*) FROM storage.objects)) FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Merge-source relational import completed with identity and derived-state gates blocked: $SOURCE_ALIAS"
echo "Evidence: $RUN_DIR"
