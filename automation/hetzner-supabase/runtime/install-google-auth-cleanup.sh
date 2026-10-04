#!/usr/bin/env bash
set -euo pipefail
readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_GOOGLE_CLEANUP_INSTALL_ACK:-}" == "install-google-auth-cleanup-on-canonical-database" ]] ||
  fail "set FESTAPP_GOOGLE_CLEANUP_INSTALL_ACK=install-google-auth-cleanup-on-canonical-database"
[[ "$(id -u)" == 0 && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run as root on the approved Festapp host"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid canonical database"
cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime operation is active"
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] || fail "runtime database mismatch"
[[ "$(docker compose exec -T db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc "SELECT to_regprocedure('public.cleanup_external_login_v1()') IS NOT NULL")" == t ]] || fail "Google migration is missing"
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN RAISE EXCEPTION 'control-plane pg_cron is missing'; END IF; END $$;
SELECT cron.schedule_in_database('festapp-external-login-cleanup-v1','0 * * * *',
  'SELECT public.cleanup_external_login_v1()',:'target_database');
COMMIT;
SELECT jobid,jobname,schedule,database,active FROM cron.job
WHERE jobname='festapp-external-login-cleanup-v1' AND database=:'target_database';
SQL
[[ "$(docker compose exec -T db psql -X -U postgres -d postgres -Atqc "SELECT count(*) FROM cron.job WHERE jobname='festapp-external-login-cleanup-v1' AND database='$TARGET_DATABASE' AND active AND schedule='0 * * * *' AND command='SELECT public.cleanup_external_login_v1()'")" == 1 ]] || fail "cleanup schedule readback failed"
echo "Google auth hourly cleanup installed in the canonical control-plane scheduler"
