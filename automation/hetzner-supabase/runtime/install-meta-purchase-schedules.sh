#!/usr/bin/env bash
set -euo pipefail
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_META_PURCHASE_SCHEDULES_ACK:-}" == "install-meta-purchase-schedules-on-canonical-database" ]] ||
  fail "set FESTAPP_META_PURCHASE_SCHEDULES_ACK=install-meta-purchase-schedules-on-canonical-database"
[[ "$(id -u)" == 0 && "$(hostname -s)" == festapp-supabase-rehearsal-01 ]] || fail "run as root on the approved Festapp host"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid canonical database"
cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime operation is active"
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] || fail "runtime database mismatch"
db_psql() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres "$@"; }
[[ "$(db_psql -d "$TARGET_DATABASE" -Atqc "SELECT to_regprocedure('public.purge_meta_purchase_data_internal()') IS NOT NULL AND to_regprocedure('public.wake_meta_purchase_worker()') IS NOT NULL AND to_regprocedure('public.meta_purchase_retention_ready_internal()') IS NOT NULL")" == t ]] ||
  fail "Meta Purchase migration is missing"

db_psql -d postgres -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
SELECT set_config('festapp.meta_purchase_schedule_database',:'target_database',true);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  RAISE EXCEPTION 'control-plane pg_cron is missing';
 END IF;
 IF EXISTS(SELECT 1 FROM cron.job
  WHERE jobname IN ('festapp_meta_purchase_retention','festapp_meta_purchase_delivery')
    AND (database<>current_setting('festapp.meta_purchase_schedule_database') OR username<>current_user)) THEN
  RAISE EXCEPTION 'an existing Meta Purchase job belongs to another database or role';
 END IF;
END $$;
SELECT cron.schedule_in_database('festapp_meta_purchase_retention','* * * * *',
 'SELECT public.purge_meta_purchase_data_internal()',:'target_database');
-- A new delivery job must wait for the first successful retention sweep.
SELECT cron.schedule_in_database('festapp_meta_purchase_delivery','* * * * *',
 'SELECT public.wake_meta_purchase_worker()',:'target_database',active:=false)
WHERE NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='festapp_meta_purchase_delivery' AND username=current_user);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='festapp_meta_purchase_retention' AND active
  AND database=current_setting('festapp.meta_purchase_schedule_database') AND schedule='* * * * *'
  AND command='SELECT public.purge_meta_purchase_data_internal()')
 OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='festapp_meta_purchase_delivery'
  AND database=current_setting('festapp.meta_purchase_schedule_database') AND schedule='* * * * *'
  AND command='SELECT public.wake_meta_purchase_worker()') THEN
  RAISE EXCEPTION 'Meta Purchase schedule readback failed';
 END IF;
END $$;
COMMIT;
SQL

printf '%s\n' "Checking for a successful Meta Purchase retention sweep"
deadline=$((SECONDS + 75))
while :; do
  retention_ready=$(db_psql -d "$TARGET_DATABASE" -Atqc 'SELECT public.meta_purchase_retention_ready_internal()')
  [[ "$retention_ready" == t ]] && break
  (( SECONDS < deadline )) || fail "Meta Purchase retention did not become ready within 75 seconds"
  sleep 2
done

db_psql -d postgres -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
SELECT set_config('festapp.meta_purchase_schedule_database',:'target_database',true);
SELECT cron.alter_job(jobid, active:=true)
FROM cron.job
WHERE jobname='festapp_meta_purchase_delivery' AND database=:'target_database'
  AND username=current_user AND schedule='* * * * *'
  AND command='SELECT public.wake_meta_purchase_worker()' AND NOT active;
DO $$ BEGIN
 IF (SELECT count(*) FROM cron.job WHERE active AND username=current_user
  AND database=current_setting('festapp.meta_purchase_schedule_database') AND schedule='* * * * *'
  AND ((jobname='festapp_meta_purchase_retention' AND command='SELECT public.purge_meta_purchase_data_internal()')
    OR (jobname='festapp_meta_purchase_delivery' AND command='SELECT public.wake_meta_purchase_worker()'))) <> 2 THEN
  RAISE EXCEPTION 'Meta Purchase schedules are not both active';
 END IF;
END $$;
COMMIT;
SELECT jobname,schedule,database,active FROM cron.job
WHERE jobname IN ('festapp_meta_purchase_retention','festapp_meta_purchase_delivery') AND database=:'target_database';
SQL
