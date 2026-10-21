#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "preserve-unclassifiable-companions-without-activation" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=preserve-unclassifiable-companions-without-activation"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/default-companion-quarantine-validation-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
DO $validate$
DECLARE import_run uuid; preserved integer; source_rows integer; canonical_rows integer;
  classifiable integer; activated_classifiable integer;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs
  WHERE source_alias='default' AND status='blocked';
  SELECT count(*) INTO preserved FROM festapp_merge.quarantined_rows
  WHERE run_id=import_run AND source_table='public.user_companions'
    AND reason='zero-common-occasion-legacy-orphan';
  SELECT count(*) INTO source_rows FROM festapp_stage_default_public.user_companions;
  SELECT count(*) INTO canonical_rows FROM public.user_companions;
  WITH shared AS (
    SELECT uc."user",uc.companion,
      array_agg(owner_membership.occasion ORDER BY owner_membership.occasion)
        FILTER(WHERE companion_membership.occasion IS NOT NULL) common_occasions
    FROM festapp_stage_default_public.user_companions uc
    LEFT JOIN festapp_stage_default_public.occasion_users owner_membership ON owner_membership."user"=uc."user"
    LEFT JOIN festapp_stage_default_public.occasion_users companion_membership
      ON companion_membership."user"=uc.companion AND companion_membership.occasion=owner_membership.occasion
    GROUP BY uc."user",uc.companion
  ) SELECT count(*),count(*) FILTER(WHERE EXISTS(
    SELECT 1 FROM public.user_companions target
    WHERE target."user"=shared."user" AND target.companion=shared.companion
      AND target.occasion=shared.common_occasions[1]
  )) INTO classifiable,activated_classifiable
  FROM shared WHERE cardinality(common_occasions)=1;
  IF preserved+classifiable<>source_rows OR activated_classifiable<>classifiable THEN
    RAISE EXCEPTION 'unexpected companion preservation state: source %, target total %, classifiable %, activated %, preserved %',source_rows,canonical_rows,classifiable,activated_classifiable,preserved;
  END IF;
  IF EXISTS (
    SELECT 1 FROM festapp_merge.quarantined_rows q
    WHERE q.run_id=import_run AND q.source_table='public.user_companions'
      AND COALESCE(jsonb_array_length(NULLIF(q.source_row->'common_occasions','null'::jsonb)),0)<>0
  ) THEN RAISE EXCEPTION 'a preserved companion row is classifiable'; END IF;

  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'source_rows',source_rows,'merged_canonical_rows',canonical_rows,'activated_classifiable_source_rows',activated_classifiable,'privately_preserved_unclassifiable_rows',preserved,
    'reason','zero shared occasion; target contract requires an occasion and both memberships',
    'invented_relationships',0,'deleted_rows',0)
  WHERE run_id=import_run AND check_name='default-companion-orphans';
  IF EXISTS (SELECT 1 FROM festapp_merge.validation_results WHERE run_id=import_run AND status<>'pass') THEN
    RAISE EXCEPTION 'default source still has a blocked validation gate';
  END IF;
  UPDATE festapp_merge.import_runs SET status='validated' WHERE run_id=import_run;
END
$validate$;
COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object('source_status',r.status,'validation',v.observed)
FROM festapp_merge.import_runs r JOIN festapp_merge.validation_results v USING(run_id)
WHERE r.source_alias='default' AND v.check_name='default-companion-orphans'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Unclassifiable legacy companion rows remain privately preserved and inactive; nothing was deleted."
echo "Evidence: $RUN_DIR"
