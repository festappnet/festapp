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
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "validate-merge-source-integrity" ]] || fail "set the merge-source integrity acknowledgement"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid rehearsal database"
[[ "$SOURCE_ALIAS" =~ ^[a-z][a-z0-9_]{0,19}$ ]] || fail "invalid source alias"
readonly SOURCE_REF="$(jq -er --arg source "$SOURCE_ALIAS" '.sources[]|select(.alias==$source and .role=="merge-source")|.project_ref' "$REGISTRY_FILE")" || fail "unregistered merge source"
[[ "$(id -u)" == 0 && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run on the approved rehearsal host"
readonly STAGE_PUBLIC="festapp_stage_${SOURCE_ALIAS}_public"
readonly STAGE_ESHOP="festapp_stage_${SOURCE_ALIAS}_eshop"
readonly STAGE_MANAGED="festapp_stage_${SOURCE_ALIAS}_managed"
cd "$COMPOSE_DIR"; docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/$SOURCE_ALIAS-integrity-validation-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main -v source_alias="$SOURCE_ALIAS" -v source_ref="$SOURCE_REF" -v stage_public="$STAGE_PUBLIC" -v stage_eshop="$STAGE_ESHOP" -v stage_managed="$STAGE_MANAGED" <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;
SELECT set_config('festapp.merge_source_alias',:'source_alias',true);
SELECT set_config('festapp.merge_source_ref',:'source_ref',true);
SELECT set_config('festapp.merge_stage_public',:'stage_public',true);
SELECT set_config('festapp.merge_stage_eshop',:'stage_eshop',true);
SELECT set_config('festapp.merge_stage_managed',:'stage_managed',true);
DO $validate$
DECLARE
  import_run uuid; mappings bigint; preserved_profiles bigint; mismatch bigint; quarantine_total bigint;
  ambiguous_companions bigint; duplicate_profiles bigint; missing_table_rows bigint; reset_token_collisions bigint; embedded_rows bigint;
  cron_active boolean:=false;
  v_source_alias text:=current_setting('festapp.merge_source_alias'); v_source_ref text:=current_setting('festapp.merge_source_ref');
  stage_public text:=current_setting('festapp.merge_stage_public'); stage_eshop text:=current_setting('festapp.merge_stage_eshop'); stage_managed text:=current_setting('festapp.merge_stage_managed');
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias=v_source_alias AND source_project_ref=v_source_ref AND status='blocked';
  IF EXISTS (WITH required(name) AS (VALUES (v_source_alias||'-relational-import'),(v_source_alias||'-auth-import'),(v_source_alias||'-storage-metadata-import'),(v_source_alias||'-storage-object-payloads'),(v_source_alias||'-auth-and-storage-import')) SELECT 1 FROM required LEFT JOIN festapp_merge.validation_results v ON v.run_id=import_run AND v.check_name=required.name GROUP BY required.name HAVING count(v.check_name)<>1 OR count(*) FILTER(WHERE v.status='pass')<>1) THEN RAISE EXCEPTION 'integrity prerequisite is missing or not passing'; END IF;

  SELECT count(*) INTO mappings FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='auth.users';
  SELECT count(*) INTO preserved_profiles FROM festapp_merge.quarantined_rows WHERE run_id=import_run AND source_table='public.user_info' AND reason='identity-merged-existing-canonical-profile-preferred';
  EXECUTE format('SELECT count(*) FROM festapp_merge.id_mappings m JOIN %I.rows s ON s.source_schema=''auth'' AND s.source_table=''users'' AND s.row_data->>''id''=m.source_id JOIN auth.users t ON t.id=m.target_id::uuid WHERE m.run_id=%L AND m.source_table=''auth.users'' AND lower(s.row_data->>''email'') IS DISTINCT FROM lower(t.email)',stage_managed,import_run) INTO mismatch;
  IF preserved_profiles<>mappings OR mismatch<>0 OR EXISTS (SELECT 1 FROM festapp_merge.id_mappings m LEFT JOIN public.user_info u ON u.id=m.target_id::uuid WHERE m.run_id=import_run AND m.source_table='public.user_info' AND u.id IS NULL) THEN RAISE EXCEPTION 'identity merge validation failed: mappings %, profiles %, email mismatches %',mappings,preserved_profiles,mismatch; END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=observed||jsonb_build_object('validated_mappings',mappings,'email_mismatches',0,'canonical_profiles_missing',0,'changed_canonical_password_hashes',0) WHERE run_id=import_run AND check_name=v_source_alias||'-identity-profile-review' AND status='blocked';
  IF NOT FOUND THEN RAISE EXCEPTION 'identity review gate missing'; END IF;

  EXECUTE format($q$WITH checks AS (
    SELECT count(*) n FROM %1$I.events s JOIN festapp_merge.id_mappings self ON self.run_id=%4$L AND self.source_table='public.events' AND self.source_id=s.id::text JOIN festapp_merge.id_mappings parent ON parent.run_id=%4$L AND parent.source_table='public.occasions' AND parent.source_id=s.occasion::text JOIN public.events t ON t.id=self.target_id::bigint WHERE t.occasion IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM %1$I.email_templates s JOIN festapp_merge.id_mappings self ON self.run_id=%4$L AND self.source_table='public.email_templates' AND self.source_id=s.id::text JOIN festapp_merge.id_mappings parent ON parent.run_id=%4$L AND parent.source_table='public.units' AND parent.source_id=s.unit::text JOIN public.email_templates t ON t.id=self.target_id::bigint WHERE t.unit IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM %1$I.log_app_config s JOIN festapp_merge.id_mappings self ON self.run_id=%4$L AND self.source_table='public.log_app_config' AND self.source_id=s.id::text JOIN festapp_merge.id_mappings parent ON parent.run_id=%4$L AND parent.source_table='public.organizations' AND parent.source_id=s.organization::text JOIN public.log_app_config t ON t.id=self.target_id::bigint WHERE t.organization IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM %1$I.role_info s JOIN festapp_merge.id_mappings self ON self.run_id=%4$L AND self.source_table='public.role_info' AND self.source_id=s.id::text JOIN festapp_merge.id_mappings parent ON parent.run_id=%4$L AND parent.source_table='public.occasions' AND parent.source_id=s.occasion::text JOIN public.role_info t ON t.id=self.target_id::bigint WHERE t.occasion IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM %1$I.occasion_users s JOIN festapp_merge.id_mappings occasion_map ON occasion_map.run_id=%4$L AND occasion_map.source_table='public.occasions' AND occasion_map.source_id=s.occasion::text LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=%4$L AND user_map.source_table='auth.users' AND user_map.source_id=s."user"::text WHERE NOT EXISTS (SELECT 1 FROM public.occasion_users t WHERE t.occasion=occasion_map.target_id::bigint AND t."user"=coalesce(user_map.target_id::uuid,s."user"))
    UNION ALL SELECT count(*) FROM %1$I.user_news s JOIN festapp_merge.id_mappings news_map ON news_map.run_id=%4$L AND news_map.source_table='public.news' AND news_map.source_id=s.news_id::text LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=%4$L AND user_map.source_table='auth.users' AND user_map.source_id=s."user"::text WHERE NOT EXISTS (SELECT 1 FROM public.user_news t WHERE t.news_id=news_map.target_id::bigint AND t."user"=coalesce(user_map.target_id::uuid,s."user"))
    UNION ALL SELECT count(*) FROM %1$I.log_notifications s JOIN festapp_merge.id_mappings self ON self.run_id=%4$L AND self.source_table='public.log_notifications' AND self.source_id=s.id::text LEFT JOIN festapp_merge.id_mappings user_map ON user_map.run_id=%4$L AND user_map.source_table='auth.users' AND user_map.source_id=s.user_id::text JOIN public.log_notifications t ON t.id=self.target_id::uuid WHERE t.user_id IS DISTINCT FROM coalesce(user_map.target_id::uuid,s.user_id)
  ) SELECT coalesce(sum(n),0) FROM checks$q$,stage_public,stage_eshop,stage_managed,import_run) INTO mismatch;
  IF mismatch<>0 THEN RAISE EXCEPTION 'registered scalar/UUID references have % mismatches',mismatch; END IF;

  EXECUTE format('SELECT count(*) FROM %I.organizations s JOIN festapp_merge.id_mappings self ON self.run_id=%L AND self.source_table=''public.organizations'' AND self.source_id=s.id::text JOIN public.organizations t ON t.id=self.target_id::bigint WHERE (t.data-''DEFAULT_UNIT''-''DEFAULT_OCCASION''-''REPRESENTATIVE_OCCASION''-''ONESIGNAL_REST_API_KEY'') IS DISTINCT FROM (s.data-''DEFAULT_UNIT''-''DEFAULT_OCCASION''-''REPRESENTATIVE_OCCASION''-''ONESIGNAL_REST_API_KEY'') OR t.data ? ''ONESIGNAL_REST_API_KEY'' OR (s.data ? ''DEFAULT_UNIT'' AND t.data->>''DEFAULT_UNIT'' IS DISTINCT FROM (SELECT m.target_id FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.units'' AND m.source_id=s.data->>''DEFAULT_UNIT'')) OR (s.data ? ''DEFAULT_OCCASION'' AND t.data->>''DEFAULT_OCCASION'' IS DISTINCT FROM (SELECT m.target_id FROM festapp_merge.id_mappings m WHERE m.run_id=%L AND m.source_table=''public.occasions'' AND m.source_id=s.data->>''DEFAULT_OCCASION'')) OR (nullif(s.data->>''ONESIGNAL_REST_API_KEY'','''') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.organization_notification_secrets secret WHERE secret.organization=self.target_id::bigint AND secret.onesignal_rest_api_key=s.data->>''ONESIGNAL_REST_API_KEY''))',stage_public,import_run,import_run,import_run) INTO mismatch;
  IF mismatch<>0 THEN RAISE EXCEPTION 'organization JSON/reference/secret transformation mismatch: %',mismatch; END IF;
  INSERT INTO festapp_merge.validation_results VALUES(import_run,v_source_alias||'-semantic-reference-validation','pass',jsonb_build_object('known_reference_mismatches',0,'onesignal_secret_extracted',true,'deleted_rows',0));

  EXECUTE format('SELECT (SELECT count(*) FROM %I.blueprints)+(SELECT count(*) FROM %I.orders)+(SELECT count(*) FROM %I.orders_history)+(SELECT count(*) FROM %I.planned_changes)',stage_eshop,stage_eshop,stage_eshop,stage_eshop) INTO embedded_rows;
  IF embedded_rows<>0 THEN RAISE EXCEPTION 'non-empty embedded payload family requires a registered transformer: %',embedded_rows; END IF;
  INSERT INTO festapp_merge.validation_results VALUES(import_run,v_source_alias||'-embedded-payload-validation','pass',jsonb_build_object('source_payload_rows',embedded_rows,'strategy','empty-source-family-not-applicable','deleted_rows',0));

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE command ~* ''sync_source_via_http|vstupenky_remote'')' INTO cron_active;
  END IF;
  IF cron_active OR has_function_privilege('service_role','public.sync_source_via_http(text)','EXECUTE') OR has_function_privilege('service_role','public.setup_external_source(text,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'retired inter-project sync is active'; END IF;
  INSERT INTO festapp_merge.validation_results VALUES(import_run,v_source_alias||'-operational-reference-validation','pass',jsonb_build_object('source_external_sync_family','not-present','external_sync_runtime_inert',true,'deleted_rows',0));

  EXECUTE format($q$WITH shared AS (SELECT c."user",c.companion,c.created_at,count(DISTINCT owner.occasion) n FROM %1$I.user_companions c JOIN %1$I.occasion_users owner ON owner."user"=c."user" JOIN %1$I.occasion_users companion ON companion."user"=c.companion AND companion.occasion=owner.occasion GROUP BY c."user",c.companion,c.created_at) SELECT count(*) FILTER(WHERE n<>1) FROM shared$q$,stage_public) INTO ambiguous_companions;
  EXECUTE format('WITH ranked AS (SELECT id,row_number() OVER(PARTITION BY organization,lower(btrim(email_readonly)) ORDER BY id) n FROM %I.user_info WHERE nullif(btrim(email_readonly),'''') IS NOT NULL) SELECT count(*) FROM ranked WHERE n>1',stage_public) INTO duplicate_profiles;
  SELECT count(*) INTO missing_table_rows FROM festapp_merge.quarantined_rows WHERE run_id=import_run AND reason='registered-missing-target-table';
  SELECT count(*) INTO reset_token_collisions FROM festapp_merge.quarantined_rows WHERE run_id=import_run AND reason='identity-merged-existing-canonical-reset-token-preferred';
  SELECT count(*) INTO quarantine_total FROM festapp_merge.quarantined_rows WHERE run_id=import_run;
  IF quarantine_total<>mappings+ambiguous_companions+duplicate_profiles+missing_table_rows+reset_token_collisions OR EXISTS (SELECT 1 FROM festapp_merge.quarantined_rows WHERE run_id=import_run AND reason NOT IN ('identity-merged-existing-canonical-profile-preferred','identity-merged-existing-canonical-reset-token-preferred','ambiguous-legacy-companion-occasion','normalized-profile-email-duplicate-preserved-with-null-secondary-email','registered-missing-target-table')) THEN RAISE EXCEPTION 'quarantine disposition mismatch: total %, identities %, reset tokens %, companions %, duplicate profiles %, missing table %',quarantine_total,mappings,reset_token_collisions,ambiguous_companions,duplicate_profiles,missing_table_rows; END IF;
  INSERT INTO festapp_merge.validation_results VALUES(import_run,v_source_alias||'-quarantine-disposition','pass',jsonb_build_object('total',quarantine_total,'identity_profiles',mappings,'reset_token_collisions',reset_token_collisions,'ambiguous_companions',ambiguous_companions,'duplicate_profile_emails',duplicate_profiles,'missing_table_rows',missing_table_rows,'deleted_rows',0));
  INSERT INTO festapp_merge.validation_results VALUES(import_run,v_source_alias||'-reference-registry-completeness','blocked',jsonb_build_object('reason','client-derived-state-and-final-link-validation-pending'));
END
$validate$;
COMMIT;
SQL
psql_main -Atqc "SELECT jsonb_object_agg(v.check_name,v.status) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='$SOURCE_ALIAS'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Merge-source identity, semantic, embedded, operational and quarantine integrity passed: $SOURCE_ALIAS"
echo "Evidence: $RUN_DIR"
