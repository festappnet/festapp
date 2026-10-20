#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "validate-a-reference-registry" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=validate-a-reference-registry"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_restore_[0-9]+$ ||
   "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "target database must be postgres or an isolated timestamped rehearsal/restore database"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-reference-registry-validation-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;

DO $validate$
DECLARE import_run uuid; mismatch_count bigint; legacy_storage_links bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='a' AND status='blocked';
  IF EXISTS (
    WITH required(check_name) AS (VALUES
      ('a-id-mapping-preparation'),('a-relational-import'),('a-identity-profile-review'),
      ('a-semantic-reference-repair'),('a-embedded-payload-repair'),('a-operational-reference-repair'),
      ('a-auth-import'),('a-storage-metadata-import'),('a-storage-object-payloads'),
      ('a-auth-and-storage-import'),('a-client-derived-state-rebuild')
    )
    SELECT 1 FROM required
    LEFT JOIN festapp_merge.validation_results v
      ON v.run_id=import_run AND v.check_name=required.check_name
    GROUP BY required.check_name
    HAVING count(v.check_name)<>1 OR count(*) FILTER (WHERE v.status='pass')<>1
  ) THEN RAISE EXCEPTION 'a required prerequisite reference validation is missing, duplicated, or not passing'; END IF;

  WITH checks AS (
    SELECT count(*) mismatches FROM festapp_stage_a_public.events source
      JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.events' AND self.source_id=source.id::text
      JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
      JOIN public.events target ON target.id=self.target_id::bigint WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM festapp_stage_a_public.email_templates source
      JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.email_templates' AND self.source_id=source.id::text
      JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.units' AND parent.source_id=source.unit::text
      JOIN public.email_templates target ON target.id=self.target_id::bigint WHERE target.unit IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM festapp_stage_a_public.log_app_config source
      JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.log_app_config' AND self.source_id=source.id::text
      JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.organizations' AND parent.source_id=source.organization::text
      JOIN public.log_app_config target ON target.id=self.target_id::bigint WHERE target.organization IS DISTINCT FROM parent.target_id::bigint
    UNION ALL SELECT count(*) FROM festapp_stage_a_public.role_info source
      JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.role_info' AND self.source_id=source.id::text
      JOIN festapp_merge.id_mappings parent ON parent.run_id=import_run AND parent.source_table='public.occasions' AND parent.source_id=source.occasion::text
      JOIN public.role_info target ON target.id=self.target_id::bigint WHERE target.occasion IS DISTINCT FROM parent.target_id::bigint
  ) SELECT sum(mismatches) INTO mismatch_count FROM checks;
  IF mismatch_count<>0 THEN RAISE EXCEPTION 'registered scalar references have % mismatches',mismatch_count; END IF;

  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_public.organizations source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run AND self.source_table='public.organizations' AND self.source_id=source.id::text
    JOIN public.organizations target ON target.id=self.target_id::bigint
    WHERE (target.data-'DEFAULT_UNIT'-'REPRESENTATIVE_OCCASION'-'DEFAULT_OCCASION'-'ONESIGNAL_REST_API_KEY')
      IS DISTINCT FROM (source.data-'DEFAULT_UNIT'-'REPRESENTATIVE_OCCASION'-'DEFAULT_OCCASION'-'ONESIGNAL_REST_API_KEY')
  ) THEN RAISE EXCEPTION 'organization JSON non-reference content changed'; END IF;

  SELECT count(*) INTO legacy_storage_links FROM public.images
  WHERE link LIKE '%supabase.co/storage/v1/object/public/%';
  IF (SELECT count(*) FROM public.images i JOIN storage.objects o
      ON o.bucket_id=split_part(split_part(i.link,'/storage/v1/object/public/',2),'/',1)
      AND o.name=substring(split_part(i.link,'/storage/v1/object/public/',2)
        from position('/' in split_part(i.link,'/storage/v1/object/public/',2))+1)
      WHERE i.link LIKE '%supabase.co/storage/v1/object/public/%')<>legacy_storage_links
  THEN RAISE EXCEPTION 'a legacy Storage URL does not have a copied recoverable object'; END IF;

  IF EXISTS (SELECT 1 FROM public.client_sync_public_heads WHERE head_json::text ~ 'kjdpmix|lwfpdj|supabase.co')
    OR EXISTS (SELECT 1 FROM public.client_sync_publications WHERE coalesce(artifact_url,'') ~ 'kjdpmix|lwfpdj|supabase.co')
    OR EXISTS (SELECT 1 FROM public.client_sync_release_manifests
      WHERE manifest::text ~ 'kjdpmix|lwfpdj|supabase.co' OR coalesce(artifact_url,'') ~ 'kjdpmix|lwfpdj|supabase.co')
  THEN RAISE EXCEPTION 'legacy backend URL remains in rebuilt client-sync state'; END IF;

  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'registry_version','2026-08-28.1','known_reference_mismatches',0,
    'required_inventory_families',7,'legacy_storage_links',legacy_storage_links,
    'legacy_storage_links_with_copied_objects',legacy_storage_links,
    'storage_url_rewrite_gate','api.festapp.net-cutover',
    'external_sync_runtime_inert',true,'deleted_rows',0)
  WHERE run_id=import_run AND check_name='a-reference-registry-completeness';
  IF NOT FOUND THEN RAISE EXCEPTION 'reference registry gate row missing'; END IF;

  IF EXISTS (SELECT 1 FROM festapp_merge.validation_results WHERE run_id=import_run AND status<>'pass') THEN
    RAISE EXCEPTION 'source-a validation still has a blocked or failed result';
  END IF;
  UPDATE festapp_merge.import_runs SET status='validated' WHERE run_id=import_run;
END
$validate$;

COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id)
WHERE r.source_alias='a' AND v.check_name='a-reference-registry-completeness'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Source-a reference registry validated for rehearsal; production hostname rewrite remains a cutover gate."
echo "Evidence: $RUN_DIR"
