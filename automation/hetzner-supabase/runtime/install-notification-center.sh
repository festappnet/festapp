#!/usr/bin/env bash
set -euo pipefail
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
[[ "${FESTAPP_NOTIFICATION_CENTER_INSTALL_ACK:-}" == 'install-canonical-notification-center-schedules' ]] || { echo 'missing schedule acknowledgement' >&2; exit 1; }
[[ "$(id -u)" == 0 && "$(hostname -s)" == festapp-supabase-rehearsal-01 ]] || { echo 'canonical host required' >&2; exit 1; }
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || exit 1
cd /opt/festapp-supabase/docker
exec 9>.festapp-runtime-upgrade.lock
flock -n 9 || { echo 'another runtime operation is active' >&2; exit 1; }
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] || { echo 'database mismatch' >&2; exit 1; }
[[ "$(docker exec supabase-db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc "SELECT to_regprocedure('public.wake_notification_center()') IS NOT NULL AND to_regprocedure('public.maintain_notification_center(integer)') IS NOT NULL")" == t ]] || exit 1
# pg_cron lives in the control database; preserve every unrelated existing job.
docker exec -i supabase-db psql -X -U postgres -d postgres -q -v ON_ERROR_STOP=1 -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
SELECT cron.schedule_in_database('festapp_canonical_notification_center_wake','1 second',
  'SELECT public.wake_notification_center()',:'target_database');
SELECT cron.schedule_in_database('festapp_canonical_notification_center_project','*/1 * * * *',
  'SELECT public.maintain_notification_center(100)',:'target_database');
COMMIT;
SQL
echo 'Canonical notification schedules installed (one-second wake, minute maintenance).'
