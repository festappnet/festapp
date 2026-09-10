#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly SOURCE_REF="kjdpmixlnhntmxjedpxh"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "import-default-with-quarantine-ledger" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=import-default-with-quarantine-ledger"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|', split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM auth.users),(SELECT count(*) FROM storage.objects),
  (SELECT count(*) FROM festapp_merge.import_runs),(SELECT count(*) FROM festapp_merge.quarantined_rows),
  (SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN
    ('festapp_stage_default_public','festapp_stage_default_eshop','festapp_stage_a_public','festapp_stage_a_eshop')),
  (SELECT count(*)=1 FROM festapp_stage_default_managed.provenance
    WHERE source_alias='default' AND source_project_ref='$SOURCE_REF'),
  (SELECT managed_rows=(SELECT count(*) FROM festapp_stage_default_managed.rows)
    FROM festapp_stage_default_managed.provenance),
  (SELECT count(*) FROM public.client_sync_component_sources))")"
[[ "$STATE" == "17|0|0|0|0|170|t|t|1" ]] || fail "canonical target is not approved empty default-import state ($STATE)"

readonly REQUIRED_GAPS="$(psql_main -Atqc "WITH source_columns AS (
  SELECT replace(table_schema, 'festapp_stage_default_', '') AS target_schema, table_name, column_name
  FROM information_schema.columns WHERE table_schema IN ('festapp_stage_default_public','festapp_stage_default_eshop')
) SELECT count(*) FROM information_schema.columns target
LEFT JOIN source_columns source ON source.target_schema=target.table_schema AND source.table_name=target.table_name AND source.column_name=target.column_name
WHERE target.table_schema IN ('public','eshop') AND target.table_name IN (
  SELECT foreign_table_name FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_default_public','festapp_stage_default_eshop')
) AND target.table_name <> 'user_companions' AND target.is_nullable='NO' AND target.column_default IS NULL
  AND target.is_identity='NO' AND target.is_generated='NEVER' AND source.column_name IS NULL")"
[[ "$REQUIRED_GAPS" == "0" ]] || fail "default import has $REQUIRED_GAPS unresolved required target columns"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/default-canonical-import-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"
psql_main -Atqc "SELECT jsonb_build_object('canonical_auth_users',(SELECT count(*) FROM auth.users),'canonical_storage_objects',(SELECT count(*) FROM storage.objects),'source_tables',(SELECT count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema IN ('festapp_stage_default_public','festapp_stage_default_eshop')))" >"$RUN_DIR/preflight.json"
chmod 0600 "$RUN_DIR/preflight.json"

psql_main <<SQL
BEGIN;
SET LOCAL session_replication_role = replica;
SET LOCAL statement_timeout = 0;

DO \$import\$
DECLARE
  import_run uuid;
  relation record;
  column_list text;
  select_list text;
  source_rows bigint;
  target_rows bigint;
  source_companions bigint;
  imported_companions bigint;
  quarantined_companions bigint;
  sequence_record record;
BEGIN
  INSERT INTO festapp_merge.import_runs(
    source_alias, source_project_ref, snapshot_at, source_schema_fingerprint,
    transformation_version, status
  ) SELECT
    'default', source_project_ref, raw_snapshot_at, raw_schema_sha256,
    'default-import-2026-08-27.2', 'prepared'
  FROM festapp_stage_default_managed.provenance
  WHERE source_alias='default' AND source_project_ref='$SOURCE_REF'
  RETURNING run_id INTO import_run;

  FOR relation IN
    SELECT foreign_table_schema AS source_schema,
      replace(foreign_table_schema, 'festapp_stage_default_', '') AS target_schema,
      foreign_table_name AS table_name
    FROM information_schema.foreign_tables
    WHERE foreign_table_schema IN ('festapp_stage_default_public','festapp_stage_default_eshop')
      AND foreign_table_name <> 'user_companions'
    ORDER BY foreign_table_schema, foreign_table_name
  LOOP
    SELECT string_agg(format('%I', target.column_name), ', ' ORDER BY target.ordinal_position),
      string_agg(CASE
        WHEN relation.target_schema='public' AND relation.table_name='organizations'
          AND target.column_name='data' THEN 'data-''ONESIGNAL_REST_API_KEY'''
        ELSE format('%I', target.column_name)
      END, ', ' ORDER BY target.ordinal_position)
    INTO column_list, select_list
    FROM information_schema.columns target
    JOIN information_schema.columns source
      ON source.table_schema=relation.source_schema
      AND source.table_name=relation.table_name
      AND source.column_name=target.column_name
    WHERE target.table_schema=relation.target_schema
      AND target.table_name=relation.table_name
      AND target.is_generated='NEVER';
    IF column_list IS NULL THEN
      RAISE EXCEPTION 'no common import columns for %.%', relation.target_schema, relation.table_name;
    END IF;
    EXECUTE format(
      'INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM %I.%I',
      relation.target_schema, relation.table_name, column_list, select_list,
      relation.source_schema, relation.table_name
    );
    EXECUTE format('SELECT count(*) FROM %I.%I', relation.source_schema, relation.table_name) INTO source_rows;
    EXECUTE format('SELECT count(*) FROM %I.%I', relation.target_schema, relation.table_name) INTO target_rows;
    IF source_rows <> target_rows THEN
      RAISE EXCEPTION 'row mismatch for %.%: source %, target %', relation.target_schema, relation.table_name, source_rows, target_rows;
    END IF;
  END LOOP;

  INSERT INTO public.organization_notification_secrets(
    organization,
    onesignal_rest_api_key
  )
  SELECT id, data->>'ONESIGNAL_REST_API_KEY'
  FROM festapp_stage_default_public.organizations
  WHERE nullif(data->>'ONESIGNAL_REST_API_KEY', '') IS NOT NULL
  ON CONFLICT (organization) DO NOTHING;

  IF EXISTS (
    SELECT 1 FROM festapp_stage_default_public.organizations source
    WHERE nullif(source.data->>'ONESIGNAL_REST_API_KEY', '') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.organization_notification_secrets secret
        WHERE secret.organization=source.id
      )
  ) OR EXISTS (
    SELECT 1 FROM public.organizations
    WHERE data ? 'ONESIGNAL_REST_API_KEY'
  ) THEN
    RAISE EXCEPTION 'default OneSignal credentials did not converge to server-only storage';
  END IF;

  WITH shared AS (
    SELECT companion_row.*,
      array_agg(owner_membership.occasion ORDER BY owner_membership.occasion)
        FILTER (WHERE companion_membership.occasion IS NOT NULL) AS common_occasions
    FROM festapp_stage_default_public.user_companions companion_row
    LEFT JOIN festapp_stage_default_public.occasion_users owner_membership
      ON owner_membership."user"=companion_row."user"
    LEFT JOIN festapp_stage_default_public.occasion_users companion_membership
      ON companion_membership."user"=companion_row.companion
      AND companion_membership.occasion=owner_membership.occasion
    GROUP BY companion_row."user", companion_row.companion, companion_row.created_at
  )
  INSERT INTO public.user_companions("user", companion, created_at, occasion, origin, created_by)
  SELECT "user", companion, created_at, common_occasions[1], 'self_created', "user"
  FROM shared WHERE cardinality(common_occasions)=1;

  WITH shared AS (
    SELECT companion_row.*,
      array_agg(owner_membership.occasion ORDER BY owner_membership.occasion)
        FILTER (WHERE companion_membership.occasion IS NOT NULL) AS common_occasions
    FROM festapp_stage_default_public.user_companions companion_row
    LEFT JOIN festapp_stage_default_public.occasion_users owner_membership
      ON owner_membership."user"=companion_row."user"
    LEFT JOIN festapp_stage_default_public.occasion_users companion_membership
      ON companion_membership."user"=companion_row.companion
      AND companion_membership.occasion=owner_membership.occasion
    GROUP BY companion_row."user", companion_row.companion, companion_row.created_at
  )
  INSERT INTO festapp_merge.quarantined_rows(
    run_id, source_table, source_primary_key, source_row, reason
  )
  SELECT import_run, 'public.user_companions',
    jsonb_build_object('user', "user", 'companion', companion), to_jsonb(shared),
    'zero-common-occasion-legacy-orphan'
  FROM shared WHERE coalesce(cardinality(common_occasions),0) <> 1;

  SELECT count(*) INTO imported_companions FROM public.user_companions;
  SELECT count(*) INTO source_companions FROM festapp_stage_default_public.user_companions;
  SELECT count(*) INTO quarantined_companions FROM festapp_merge.quarantined_rows WHERE run_id=import_run;
  IF imported_companions + quarantined_companions <> source_companions THEN
    RAISE EXCEPTION 'companion disposition mismatch: source %, imported %, quarantined %',
      source_companions, imported_companions, quarantined_companions;
  END IF;

  FOR sequence_record IN
    SELECT table_schema, table_name, column_name,
      pg_get_serial_sequence(format('%I.%I', table_schema, table_name), column_name) AS sequence_name
    FROM information_schema.columns
    WHERE table_schema IN ('public','eshop')
      AND (is_identity='YES' OR column_default LIKE 'nextval(%')
  LOOP
    IF sequence_record.sequence_name IS NOT NULL THEN
      EXECUTE format(
        'SELECT setval(%L, coalesce(max(%I),1), max(%I) IS NOT NULL) FROM %I.%I',
        sequence_record.sequence_name, sequence_record.column_name, sequence_record.column_name,
        sequence_record.table_schema, sequence_record.table_name
      );
    END IF;
  END LOOP;

  INSERT INTO festapp_merge.validation_results(run_id, check_name, status, observed)
  VALUES
    (import_run, 'default-table-counts', 'pass', jsonb_build_object(
      'source_tables',(SELECT count(*) FROM information_schema.foreign_tables
        WHERE foreign_table_schema IN ('festapp_stage_default_public','festapp_stage_default_eshop')),
      'raw_artifact_sha256',(SELECT raw_artifact_sha256 FROM festapp_stage_default_managed.provenance),
      'raw_manifest_sha256',(SELECT raw_manifest_sha256 FROM festapp_stage_default_managed.provenance),
      'managed_artifact_sha256',(SELECT managed_artifact_sha256 FROM festapp_stage_default_managed.provenance),
      'managed_manifest_sha256',(SELECT managed_manifest_sha256 FROM festapp_stage_default_managed.provenance),
      'source_companion_rows',source_companions,
      'imported_companion_rows',imported_companions)),
    (import_run, 'default-companion-orphans',
      CASE WHEN quarantined_companions=0 THEN 'pass' ELSE 'blocked' END,
      jsonb_build_object('quarantined',quarantined_companions)),
    (import_run, 'auth-and-storage-import', 'blocked', jsonb_build_object('auth_users',0,'storage_objects',0));
  UPDATE festapp_merge.import_runs SET status='blocked' WHERE run_id=import_run;
END
\$import\$;

COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'import_runs',(SELECT count(*) FROM festapp_merge.import_runs),
  'run_status',(SELECT status FROM festapp_merge.import_runs WHERE source_alias='default'),
  'quarantined_rows',(SELECT count(*) FROM festapp_merge.quarantined_rows),
  'imported_companions',(SELECT count(*) FROM public.user_companions),
  'auth_users',(SELECT count(*) FROM auth.users),
  'storage_objects',(SELECT count(*) FROM storage.objects),
  'validation_results',(SELECT count(*) FROM festapp_merge.validation_results)
)" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Default canonical rehearsal import completed in blocked quarantine state."
echo "Evidence: $RUN_DIR"
