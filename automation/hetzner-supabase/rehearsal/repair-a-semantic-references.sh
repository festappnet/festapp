#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "repair-a-registered-semantic-references-forward-only" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=repair-a-registered-semantic-references-forward-only"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_restore_[0-9]+$ ||
   "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "target database must be postgres or an isolated timestamped rehearsal/restore database"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-semantic-reference-repair'))")"
[[ "$STATE" == "1|0" ]] || fail "target is not the approved pre-repair state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-semantic-reference-repair-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;

DO $repair$
DECLARE import_run uuid; changed bigint; expected bigint; row_changed bigint; source_record record;
  transformed_data jsonb; mapped_value jsonb;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='a' AND status='blocked';

  SELECT count(*) INTO expected FROM festapp_stage_a_public.events source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.events' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
  JOIN public.events target ON target.id=self.target_id::bigint WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint;
  UPDATE public.events target SET occasion=parent.target_id::bigint
  FROM festapp_stage_a_public.events source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.events' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
  WHERE target.id=self.target_id::bigint AND target.occasion IS DISTINCT FROM parent.target_id::bigint;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>expected THEN RAISE EXCEPTION 'expected % event occasion repairs, got %',expected,changed; END IF;

  SELECT count(*) INTO expected FROM festapp_stage_a_public.email_templates source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.email_templates' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.units' AND parent.source_id=source.unit::text
  JOIN public.email_templates target ON target.id=self.target_id::bigint WHERE target.unit IS DISTINCT FROM parent.target_id::bigint;
  UPDATE public.email_templates target SET unit=parent.target_id::bigint
  FROM festapp_stage_a_public.email_templates source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.email_templates' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.units' AND parent.source_id=source.unit::text
  WHERE target.id=self.target_id::bigint AND target.unit IS DISTINCT FROM parent.target_id::bigint;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>expected THEN RAISE EXCEPTION 'expected % email-template unit repairs, got %',expected,changed; END IF;

  SELECT count(*) INTO expected FROM festapp_stage_a_public.log_app_config source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.log_app_config' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.organizations' AND parent.source_id=source.organization::text
  JOIN public.log_app_config target ON target.id=self.target_id::bigint WHERE target.organization IS DISTINCT FROM parent.target_id::bigint;
  UPDATE public.log_app_config target SET organization=parent.target_id::bigint
  FROM festapp_stage_a_public.log_app_config source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.log_app_config' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.organizations' AND parent.source_id=source.organization::text
  WHERE target.id=self.target_id::bigint AND target.organization IS DISTINCT FROM parent.target_id::bigint;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>expected THEN RAISE EXCEPTION 'expected % app-config log organization repairs, got %',expected,changed; END IF;

  SELECT count(*) INTO expected FROM festapp_stage_a_public.role_info source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.role_info' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
  JOIN public.role_info target ON target.id=self.target_id::bigint WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint;
  UPDATE public.role_info target SET occasion=parent.target_id::bigint
  FROM festapp_stage_a_public.role_info source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.role_info' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
  WHERE target.id=self.target_id::bigint AND target.occasion IS DISTINCT FROM parent.target_id::bigint;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>expected THEN RAISE EXCEPTION 'expected % role occasion repairs, got %',expected,changed; END IF;

  SELECT count(*) INTO expected FROM festapp_stage_a_eshop.planned_changes source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.planned_changes' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings form_map ON form_map.run_id=import_run AND form_map.source_table='public.forms' AND form_map.source_id=source.subject_id::text
  JOIN eshop.planned_changes target ON target.id=self.target_id::bigint
  WHERE source.change_type LIKE 'forms.%' AND target.subject_id IS DISTINCT FROM form_map.target_id::bigint;
  UPDATE eshop.planned_changes target SET subject_id=form_map.target_id::bigint
  FROM festapp_stage_a_eshop.planned_changes source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.planned_changes' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings form_map ON form_map.run_id=import_run AND form_map.source_table='public.forms' AND form_map.source_id=source.subject_id::text
  WHERE source.change_type LIKE 'forms.%' AND target.id=self.target_id::bigint
    AND target.subject_id IS DISTINCT FROM form_map.target_id::bigint;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>expected THEN RAISE EXCEPTION 'expected % planned-change subject repairs, got %',expected,changed; END IF;

  changed:=0;
  FOR source_record IN
    SELECT source.data,self.target_id::bigint target_id
    FROM festapp_stage_a_public.organizations source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run
      AND self.source_table='public.organizations' AND self.source_id=source.id::text
  LOOP
    transformed_data:=source_record.data - 'ONESIGNAL_REST_API_KEY';
    IF transformed_data ? 'DEFAULT_UNIT' THEN
      SELECT to_jsonb(target_id::bigint) INTO STRICT mapped_value FROM festapp_merge.id_mappings
      WHERE run_id=import_run AND source_table='public.units' AND source_id=transformed_data->>'DEFAULT_UNIT';
      transformed_data:=jsonb_set(transformed_data,'{DEFAULT_UNIT}',mapped_value,false);
    END IF;
    IF transformed_data ? 'REPRESENTATIVE_OCCASION' THEN
      SELECT to_jsonb(target_id::bigint) INTO STRICT mapped_value FROM festapp_merge.id_mappings
      WHERE run_id=import_run AND source_table='public.occasions' AND source_id=transformed_data->>'REPRESENTATIVE_OCCASION';
      transformed_data:=jsonb_set(transformed_data,'{REPRESENTATIVE_OCCASION}',mapped_value,false);
    END IF;
    IF transformed_data ? 'DEFAULT_OCCASION' THEN
      SELECT to_jsonb(target_id::bigint) INTO STRICT mapped_value FROM festapp_merge.id_mappings
      WHERE run_id=import_run AND source_table='public.occasions' AND source_id=transformed_data->>'DEFAULT_OCCASION';
      transformed_data:=jsonb_set(transformed_data,'{DEFAULT_OCCASION}',mapped_value,false);
    END IF;
    UPDATE public.organizations SET data=transformed_data
    WHERE id=source_record.target_id AND data IS DISTINCT FROM transformed_data;
    GET DIAGNOSTICS row_changed=ROW_COUNT;
    changed:=changed+row_changed;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.organizations source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.organizations' AND self.source_id=source.id::text
    JOIN public.organizations target ON target.id=self.target_id::bigint
    LEFT JOIN festapp_merge.id_mappings unit_map ON unit_map.run_id=import_run AND unit_map.source_table='public.units' AND unit_map.source_id=source.data->>'DEFAULT_UNIT'
    LEFT JOIN festapp_merge.id_mappings representative_map ON representative_map.run_id=import_run AND representative_map.source_table='public.occasions' AND representative_map.source_id=source.data->>'REPRESENTATIVE_OCCASION'
    LEFT JOIN festapp_merge.id_mappings occasion_map ON occasion_map.run_id=import_run AND occasion_map.source_table='public.occasions' AND occasion_map.source_id=source.data->>'DEFAULT_OCCASION'
    WHERE (source.data ? 'DEFAULT_UNIT' AND target.data->>'DEFAULT_UNIT' IS DISTINCT FROM unit_map.target_id)
       OR (source.data ? 'REPRESENTATIVE_OCCASION' AND target.data->>'REPRESENTATIVE_OCCASION' IS DISTINCT FROM representative_map.target_id)
       OR (source.data ? 'DEFAULT_OCCASION' AND target.data->>'DEFAULT_OCCASION' IS DISTINCT FROM occasion_map.target_id)
  ) THEN RAISE EXCEPTION 'organization JSON reference repair did not converge'; END IF;

  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.events source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.events' AND self.source_id=source.id::text
    JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
    JOIN public.events target ON target.id=self.target_id::bigint
    WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint
  ) THEN RAISE EXCEPTION 'event occasion repair did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.email_templates source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.email_templates' AND self.source_id=source.id::text
    JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.units' AND parent.source_id=source.unit::text
    JOIN public.email_templates target ON target.id=self.target_id::bigint
    WHERE target.unit IS DISTINCT FROM parent.target_id::bigint
  ) THEN RAISE EXCEPTION 'email-template unit repair did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.log_app_config source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.log_app_config' AND self.source_id=source.id::text
    JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.organizations' AND parent.source_id=source.organization::text
    JOIN public.log_app_config target ON target.id=self.target_id::bigint
    WHERE target.organization IS DISTINCT FROM parent.target_id::bigint
  ) THEN RAISE EXCEPTION 'app-config organization repair did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.role_info source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.role_info' AND self.source_id=source.id::text
    JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
    JOIN public.role_info target ON target.id=self.target_id::bigint
    WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint
  ) THEN RAISE EXCEPTION 'role occasion repair did not converge'; END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_eshop.planned_changes source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='eshop.planned_changes' AND self.source_id=source.id::text
    JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.forms' AND parent.source_id=source.subject_id::text
    JOIN eshop.planned_changes target ON target.id=self.target_id::bigint
    WHERE source.change_type LIKE 'forms.%' AND target.subject_id IS DISTINCT FROM parent.target_id::bigint
  ) THEN RAISE EXCEPTION 'planned-change subject repair did not converge'; END IF;

  UPDATE public.client_aggregate_versions aggregate SET scope_id=e.occasion,updated_at=clock_timestamp()
  FROM public.events e WHERE aggregate.aggregate_type='event' AND aggregate.scope_type='occasion'
    AND aggregate.aggregate_id=e.id::text AND aggregate.scope_id IS DISTINCT FROM e.occasion;

  CREATE TEMP TABLE repaired_occasions ON COMMIT DROP AS
  SELECT target_id::bigint occasion FROM festapp_merge.id_mappings
  WHERE run_id=import_run AND source_table='public.occasions';
  CREATE TEMP TABLE repair_commits(occasion bigint PRIMARY KEY,commit_id uuid NOT NULL) ON COMMIT DROP;
  WITH inserted AS (
    INSERT INTO public.client_commits(occasion,actor_kind,source,change_class,reason)
    SELECT occasion,'system','migration.merge.semantic-reference-repair','migration',
      'forward-only repair of registered undeclared and embedded references'
    FROM repaired_occasions RETURNING occasion,commit_id
  ) INSERT INTO repair_commits SELECT occasion,commit_id FROM inserted;

  UPDATE public.client_sync_scopes scope SET source_revision=scope.source_revision+1,updated_at=now()
  FROM repaired_occasions repaired WHERE scope.scope_type='occasion' AND scope.scope_id=repaired.occasion;
  INSERT INTO public.client_projection_dirty_keys(component,scope_type,scope_id,entity_id,source_revision)
  SELECT scope.component,scope.scope_type,scope.scope_id,0,scope.source_revision
  FROM public.client_sync_scopes scope JOIN repaired_occasions repaired ON repaired.occasion=scope.scope_id
  JOIN public.occasions o ON o.id=scope.scope_id WHERE NOT o.is_hidden
  ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
    source_revision=EXCLUDED.source_revision,dirty_since=now(),claimed_at=NULL,claim_token=NULL;
  UPDATE public.client_sync_private_scopes scope SET source_revision=scope.source_revision+1,updated_at=now()
  FROM repaired_occasions repaired WHERE scope.occasion=repaired.occasion;

  INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision)
  SELECT commits.commit_id,scope.component,scope.scope_type,scope.scope_id,NULL,scope.source_revision
  FROM repair_commits commits JOIN public.client_sync_scopes scope ON scope.scope_type='occasion' AND scope.scope_id=commits.occasion;
  INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision)
  SELECT commits.commit_id,scope.component,'occasion',scope.occasion,scope.user_id,scope.source_revision
  FROM repair_commits commits JOIN public.client_sync_private_scopes scope ON scope.occasion=commits.occasion;

  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'a-semantic-reference-repair','pass',jsonb_build_object(
      'organization_json_rows_changed',changed,
      'scalar_reference_validation','dynamic-source-map-comparison',
      'strategy','registered-forward-only-repair-v1','deleted_rows',0)),
    (import_run,'a-reference-registry-completeness','blocked',jsonb_build_object(
      'registry_status','draft-blocking',
      'reason','known undeclared references repaired; required inventory families not yet closed',
      'deleted_rows',0));
  UPDATE festapp_merge.import_runs SET status='blocked' WHERE run_id=import_run;
END
$repair$;

COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id)
WHERE r.source_alias='a' AND v.check_name='a-semantic-reference-repair'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Registered source-a semantic references repaired forward-only; nothing was deleted."
echo "Evidence: $RUN_DIR"
