#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "validate-default-auth-credential-continuity" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=validate-default-auth-credential-continuity"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='default' AND status='blocked'),
  (SELECT (SELECT count(*) FROM auth.users)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='users')
    AND (SELECT count(*) FROM auth.identities)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='identities')
    AND (SELECT count(*) FROM auth.sessions)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='sessions')
    AND (SELECT count(*) FROM auth.refresh_tokens)=(SELECT count(*) FROM festapp_stage_default_managed.rows WHERE source_schema='auth' AND source_table='refresh_tokens')),
  (SELECT count(*) FROM festapp_merge.validation_results WHERE check_name='default-auth-credential-continuity'))")"
[[ "$STATE" == "17|1|t|0" ]] || fail "target is not approved Auth continuity state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/default-auth-continuity-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main -Atq <<'SQL' >"$RUN_DIR/result.json"
WITH source_users AS (
  SELECT row_data FROM festapp_stage_default_managed.rows
  WHERE source_schema='auth' AND source_table='users'
), password_check AS (
  SELECT count(*) AS source_users,
    count(*) FILTER (WHERE u.id IS NULL) AS missing_users,
    count(*) FILTER (WHERE (s.row_data->>'encrypted_password') IS DISTINCT FROM u.encrypted_password) AS changed_password_hashes,
    count(*) FILTER (WHERE nullif(s.row_data->>'encrypted_password','') IS NOT NULL) AS password_accounts,
    count(*) FILTER (WHERE nullif(s.row_data->>'encrypted_password','') IS NULL) AS passwordless_accounts
  FROM source_users s LEFT JOIN auth.users u ON u.id=(s.row_data->>'id')::uuid
), identity_check AS (
  SELECT count(*) AS source_identities,count(*) FILTER (WHERE i.id IS NULL) AS missing_identities
  FROM festapp_stage_default_managed.rows s LEFT JOIN auth.identities i ON i.id=(s.row_data->>'id')::uuid
  WHERE s.source_schema='auth' AND s.source_table='identities'
), session_check AS (
  SELECT count(*) AS source_sessions,count(*) FILTER (WHERE t.id IS NULL) AS missing_sessions
  FROM festapp_stage_default_managed.rows s LEFT JOIN auth.sessions t ON t.id=(s.row_data->>'id')::uuid
  WHERE s.source_schema='auth' AND s.source_table='sessions'
), refresh_check AS (
  SELECT count(*) AS source_refresh_tokens,
    count(*) FILTER (WHERE t.id IS NULL) AS missing_refresh_tokens,
    count(*) FILTER (WHERE (s.row_data->>'token') IS DISTINCT FROM t.token) AS changed_refresh_tokens
  FROM festapp_stage_default_managed.rows s LEFT JOIN auth.refresh_tokens t ON t.id=(s.row_data->>'id')::bigint
  WHERE s.source_schema='auth' AND s.source_table='refresh_tokens'
), result AS (
  SELECT jsonb_build_object(
    'source_users',p.source_users,'missing_users',p.missing_users,
    'password_accounts',p.password_accounts,'passwordless_accounts',p.passwordless_accounts,
    'changed_password_hashes',p.changed_password_hashes,
    'source_identities',i.source_identities,'missing_identities',i.missing_identities,
    'source_sessions',se.source_sessions,'missing_sessions',se.missing_sessions,
    'source_refresh_tokens',r.source_refresh_tokens,'missing_refresh_tokens',r.missing_refresh_tokens,
    'changed_refresh_tokens',r.changed_refresh_tokens
  ) AS observed
  FROM password_check p CROSS JOIN identity_check i CROSS JOIN session_check se CROSS JOIN refresh_check r
), asserted AS (
  SELECT observed FROM result
  WHERE (observed->>'missing_users')::bigint=0
    AND (observed->>'changed_password_hashes')::bigint=0
    AND (observed->>'source_users')::bigint =
      (observed->>'password_accounts')::bigint + (observed->>'passwordless_accounts')::bigint
    AND (observed->>'missing_identities')::bigint=0
    AND (observed->>'missing_sessions')::bigint=0
    AND (observed->>'missing_refresh_tokens')::bigint=0
    AND (observed->>'changed_refresh_tokens')::bigint=0
), recorded AS (
  INSERT INTO festapp_merge.validation_results(run_id,check_name,status,observed)
  SELECT run_id,'default-auth-credential-continuity','pass',asserted.observed
  FROM festapp_merge.import_runs CROSS JOIN asserted
  WHERE source_alias='default' AND status='blocked'
  RETURNING observed
)
SELECT observed FROM recorded;
SQL
chmod 0600 "$RUN_DIR/result.json"
[[ -s "$RUN_DIR/result.json" ]] || fail "Auth continuity assertion failed"
echo "Default Auth credential continuity passed without exposing credentials."
echo "Evidence: $RUN_DIR"
