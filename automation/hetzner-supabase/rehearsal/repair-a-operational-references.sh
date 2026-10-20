#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "repair-a-operational-references-forward-only" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=repair-a-operational-references-forward-only"
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
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-embedded-payload-repair' AND v.status='pass'),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-operational-reference-repair'))")"
[[ "$STATE" == "1|1|0" ]] || fail "target is not the approved pre-repair state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-operational-reference-repair-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;

DO $repair$
DECLARE import_run uuid; changed_snapshots bigint; cron_active boolean;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='a' AND status='blocked';

  UPDATE eshop.transaction_pairing_events target
  SET transaction_snapshot_id=transaction_map.target_id::bigint
  FROM festapp_stage_a_eshop.transaction_pairing_events source
  JOIN festapp_merge.id_mappings self ON self.run_id=import_run
    AND self.source_table='eshop.transaction_pairing_events' AND self.source_id=source.id::text
  JOIN festapp_merge.id_mappings transaction_map ON transaction_map.run_id=import_run
    AND transaction_map.source_table='eshop.transactions' AND transaction_map.source_id=source.transaction_snapshot_id::text
  WHERE target.id=self.target_id::bigint
    AND target.transaction_snapshot_id IS DISTINCT FROM transaction_map.target_id::bigint;
  GET DIAGNOSTICS changed_snapshots=ROW_COUNT;

  IF EXISTS (
    SELECT 1 FROM festapp_stage_a_eshop.transaction_pairing_events source
    JOIN festapp_merge.id_mappings self ON self.run_id=import_run
      AND self.source_table='eshop.transaction_pairing_events' AND self.source_id=source.id::text
    LEFT JOIN festapp_merge.id_mappings transaction_map ON transaction_map.run_id=import_run
      AND transaction_map.source_table='eshop.transactions' AND transaction_map.source_id=source.transaction_snapshot_id::text
    JOIN eshop.transaction_pairing_events target ON target.id=self.target_id::bigint
    WHERE target.transaction_snapshot_id IS DISTINCT FROM
      coalesce(transaction_map.target_id::bigint,source.transaction_snapshot_id)
  ) THEN RAISE EXCEPTION 'transaction snapshot references did not converge'; END IF;

  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE command ~* ''sync_source_via_http|vstupenky_remote'')'
      INTO STRICT cron_active;
    IF cron_active THEN
      RAISE EXCEPTION 'inter-project external-sync cron remains active';
    END IF;
  END IF;
  REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text)
    FROM PUBLIC, anon, authenticated, service_role;
  REVOKE EXECUTE ON FUNCTION public.setup_external_source(text,text,text,text)
    FROM PUBLIC, anon, authenticated, service_role;

  IF has_function_privilege('service_role','public.sync_source_via_http(text)','EXECUTE')
    OR has_function_privilege('service_role','public.setup_external_source(text,text,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'service role can still activate inter-project sync'; END IF;

  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed) VALUES
    (import_run,'a-operational-reference-repair','pass',jsonb_build_object(
      'changed_transaction_snapshots',changed_snapshots,
      'external_sync_sources_preserved',(SELECT count(*) FROM public.external_sync_sources),
      'external_sync_maps_preserved',(SELECT count(*) FROM public.external_sync_maps),
      'external_sync_cache_rows_preserved',(SELECT count(*) FROM public.external_occasions_cache),
      'external_sync_cron_jobs',0,'service_role_external_sync_execute',false,
      'storage_objects_preserved',(SELECT count(*) FROM storage.objects),
      'storage_url_rewrite_deferred_to_api_hostname',true,
      'deleted_rows',0));
END
$repair$;

COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id)
WHERE r.source_alias='a' AND v.check_name='a-operational-reference-repair'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Operational references repaired and obsolete inter-project sync made inert; nothing was deleted."
echo "Evidence: $RUN_DIR"
