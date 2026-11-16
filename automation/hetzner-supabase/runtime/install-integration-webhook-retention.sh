#!/usr/bin/env bash
set -euo pipefail
readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_WEBHOOK_RETENTION_INSTALL_ACK:-}" == "install-integration-webhook-retention-on-canonical-database" ]] ||
  fail "set FESTAPP_WEBHOOK_RETENTION_INSTALL_ACK=install-integration-webhook-retention-on-canonical-database"
[[ "$(id -u)" == 0 && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run as root on the approved Festapp host"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid canonical database"
cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime operation is active"
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] || fail "runtime database mismatch"
[[ "$(docker compose exec -T db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc "SELECT to_regprocedure('public.purge_integration_webhooks_internal()') IS NOT NULL")" == t ]] || fail "Webhook migration is missing"
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
SELECT set_config('festapp.webhook_retention_database',:'target_database',true);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
   RAISE EXCEPTION 'control-plane pg_cron is missing'; END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='integration-webhook-retention'
   AND database<>current_setting('festapp.webhook_retention_database')) THEN
   RAISE EXCEPTION 'retention job belongs to another database'; END IF;
END $$;
SELECT cron.schedule_in_database('integration-webhook-retention','*/10 * * * *',
  'SELECT public.purge_integration_webhooks_internal()',:'target_database');
COMMIT;
SELECT jobid,jobname,schedule,database,active FROM cron.job
WHERE jobname='integration-webhook-retention' AND database=:'target_database';
SQL
[[ "$(docker compose exec -T db psql -X -U postgres -d postgres -Atqc "SELECT count(*) FROM cron.job WHERE jobname='integration-webhook-retention' AND database='$TARGET_DATABASE' AND active AND schedule='*/10 * * * *' AND command='SELECT public.purge_integration_webhooks_internal()'")" == 1 ]] || fail "retention schedule readback failed"
echo "Webhook retention every ten minutes installed in the canonical control-plane scheduler"
