#!/usr/bin/env bash
set -euo pipefail
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
[[ "${FESTAPP_FIRST_LOGIN_INSTALL_ACK:-}" == 'install-canonical-first-login-notification-schedule' ]] || { echo 'missing schedule acknowledgement' >&2; exit 1; }
[[ "$(id -u)" == 0 && "$(hostname -s)" == festapp-supabase-rehearsal-01 ]] || { echo 'canonical host required' >&2; exit 1; }
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || exit 1
cd /opt/festapp-supabase/docker
exec 9>.festapp-runtime-upgrade.lock
flock -n 9 || { echo 'another runtime operation is active' >&2; exit 1; }
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] || { echo 'database mismatch' >&2; exit 1; }
[[ "$(docker exec supabase-db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc "SELECT to_regprocedure('public.enqueue_first_login_notifications_v1()') IS NOT NULL")" == t ]] || exit 1
docker exec -i supabase-db psql -X -U postgres -d postgres -q -v ON_ERROR_STOP=1 -v target_database="$TARGET_DATABASE" <<'SQL'
BEGIN;
SELECT cron.schedule_in_database('festapp-first-login-notifications-v1','* * * * *',
  'SELECT public.enqueue_first_login_notifications_v1()',:'target_database');
COMMIT;
SQL
echo 'Canonical first-login schedule installed (one minute).'
