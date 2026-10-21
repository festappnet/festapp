#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "validate-a-approved-identity-merges" ]] || fail "set FESTAPP_REHEARSAL_ACK=validate-a-approved-identity-merges"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run as root on the approved rehearsal host"
cd "$COMPOSE_DIR"
docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-identity-merge-validation-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
DO $validate$
DECLARE import_run uuid; mappings bigint; preserved_profiles bigint; missing_profiles bigint;
  changed_default_hashes bigint; email_mismatches bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked';
  IF NOT EXISTS (SELECT 1 FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='a-auth-import' AND status='pass') THEN
    RAISE EXCEPTION 'source a Auth import is not validated';
  END IF;
  SELECT count(*) INTO mappings FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='auth.users';
  SELECT count(*) INTO preserved_profiles FROM festapp_merge.quarantined_rows
    WHERE run_id=import_run AND source_table='public.user_info' AND reason='identity-merged-default-profile-preferred-review-required';
  SELECT count(*) INTO missing_profiles FROM festapp_merge.id_mappings m
    LEFT JOIN public.user_info target ON target.id=m.target_id::uuid
    WHERE m.run_id=import_run AND m.source_table='public.user_info' AND target.id IS NULL;
  SELECT count(*) INTO changed_default_hashes FROM festapp_merge.id_mappings m
    JOIN auth.users target ON target.id=m.target_id::uuid
    LEFT JOIN festapp_stage_default_managed.rows source ON source.source_schema='auth' AND source.source_table='users'
      AND source.row_data->>'id'=m.target_id
    WHERE m.run_id=import_run AND m.source_table='auth.users'
      AND (source.row_data IS NULL OR target.encrypted_password IS DISTINCT FROM source.row_data->>'encrypted_password');
  SELECT count(*) INTO email_mismatches FROM festapp_merge.id_mappings m
    JOIN festapp_stage_a_managed.rows source ON source.source_schema='auth' AND source.source_table='users'
      AND source.row_data->>'id'=m.source_id
    JOIN auth.users target ON target.id=m.target_id::uuid
    WHERE m.run_id=import_run AND m.source_table='auth.users'
      AND lower(source.row_data->>'email') IS DISTINCT FROM lower(target.email);
  IF mappings=0 OR preserved_profiles<>mappings OR missing_profiles<>0 OR changed_default_hashes<>0 OR email_mismatches<>0 THEN
    RAISE EXCEPTION 'identity merge validation failed: mappings %, profiles %, missing %, changed hashes %, email mismatches %',
      mappings,preserved_profiles,missing_profiles,changed_default_hashes,email_mismatches;
  END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'approved_identity_merges',mappings,'preserved_source_profiles',preserved_profiles,
    'canonical_rule','verified-email-prefer-default-v1','default_profiles_present',true,
    'default_password_hashes_preserved',true,'email_mismatches',0,'deleted_rows',0)
  WHERE run_id=import_run AND check_name='a-identity-profile-review' AND status='blocked';
  IF NOT FOUND THEN RAISE EXCEPTION 'identity profile review gate is not in the approved blocked state'; END IF;
END
$validate$;
COMMIT;
SQL

psql_main -Atqc "SELECT observed FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id) WHERE r.source_alias='a' AND v.check_name='a-identity-profile-review'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Approved source-a identity merges validated with default profiles and password hashes preserved."
echo "Evidence: $RUN_DIR"
