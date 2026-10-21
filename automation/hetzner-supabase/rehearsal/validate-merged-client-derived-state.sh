#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "validate-merged-client-derived-state" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=validate-merged-client-derived-state"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/merged-client-derived-validation-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;

CREATE TEMP TABLE measured_components ON COMMIT DROP AS
SELECT o.id occasion,s.component,
  octet_length(public.get_public_client_sync_component_v1(s.component,s.scope_type,s.scope_id)::text) bytes,
  COALESCE((o.data->>'client_sync_v1')::boolean,false) enabled
FROM public.client_sync_scopes s JOIN public.occasions o ON o.id=s.scope_id
WHERE s.scope_type='occasion' AND NOT o.is_hidden;

DO $validate$
DECLARE import_run uuid; enabled_occasion bigint; invalid_enabled integer;
  expected_private bigint; actual_private bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='a' AND status='validated';
  SELECT id INTO STRICT enabled_occasion FROM public.occasions
  WHERE COALESCE((data->>'client_sync_v1')::boolean,false);

  SELECT count(*) INTO invalid_enabled FROM measured_components
  WHERE enabled AND CASE component
    WHEN 'content_catalog' THEN bytes>2097152
    WHEN 'live_public' THEN bytes>524288
    ELSE bytes>1048576 END;
  IF invalid_enabled<>0 THEN RAISE EXCEPTION 'enabled client-sync scope has % over-budget components',invalid_enabled; END IF;
  IF (SELECT count(*) FROM measured_components WHERE enabled)<>6 THEN
    RAISE EXCEPTION 'enabled client-sync scope does not have six materialized components';
  END IF;
  IF (SELECT count(*) FROM public.client_projection_dirty_keys WHERE scope_type='occasion' AND scope_id=enabled_occasion)<>6 THEN
    RAISE EXCEPTION 'enabled client-sync scope does not have six dirty components';
  END IF;

  SELECT count(*)*6 INTO expected_private FROM public.occasion_users ou
  JOIN public.user_info ui ON ui.id=ou."user";
  SELECT count(*) INTO actual_private FROM public.client_sync_private_scopes;
  IF actual_private<>expected_private THEN
    RAISE EXCEPTION 'private vector count mismatch: expected %, got %',expected_private,actual_private;
  END IF;

  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed)
  VALUES (import_run,'merged-client-materialization','pass',jsonb_build_object(
    'enabled_occasion',enabled_occasion,
    'enabled_components',6,
    'enabled_max_component_bytes',(SELECT max(bytes) FROM measured_components WHERE enabled),
    'private_vectors',actual_private,
    'revision_epoch',(SELECT min(source_revision) FROM public.client_sync_scopes),
    'non_enabled_over_budget_components',(SELECT count(*) FROM measured_components WHERE NOT enabled AND CASE component WHEN 'content_catalog' THEN bytes>2097152 WHEN 'live_public' THEN bytes>524288 ELSE bytes>1048576 END),
    'production_r2_writes',0))
  ON CONFLICT (run_id,check_name) DO UPDATE SET status=EXCLUDED.status,observed=EXCLUDED.observed;
END
$validate$;

COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v
JOIN festapp_merge.import_runs r USING(run_id)
WHERE r.source_alias='a' AND v.check_name='merged-client-materialization'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Merged client-derived state validated for the enabled production scope; no R2 object was written."
echo "Evidence: $RUN_DIR"
