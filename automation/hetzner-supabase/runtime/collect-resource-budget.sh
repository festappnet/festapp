#!/usr/bin/env bash
# One read-only sample. Run across a representative peak + backup window.
# No daemon, credentials, application payloads, cap changes or paid capacity.
set -euo pipefail
[[ $EUID == 0 && $(hostname -s) == festapp-supabase-rehearsal-01 ]]
readonly COMPOSE_DIR=/opt/festapp-supabase/docker
readonly DB="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' "$COMPOSE_DIR/.env")"
[[ "$DB" == festapp_rehearsal_20260909220601 ]]
date -u +%Y-%m-%dT%H:%M:%SZ
awk '/MemTotal:|MemAvailable:|SwapTotal:|SwapFree:/ {print}' /proc/meminfo
df -B1 / /var/lib/docker /var/backups
cd "$COMPOSE_DIR"
mapfile -t containers < <(docker compose ps -q)
[[ ${#containers[@]} -gt 0 ]]
docker stats --no-stream --format '{{json .}}' "${containers[@]}"
docker inspect --format '{{.Name}} memory={{.HostConfig.Memory}} cpu={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' "${containers[@]}"
docker exec -i supabase-db psql -X -U postgres -d "$DB" -v ON_ERROR_STOP=1 -At <<'SQL'
BEGIN READ ONLY;
SELECT jsonb_build_object('connections',count(*),'active',count(*) FILTER(WHERE state='active'),
 'long_transactions',count(*) FILTER(WHERE xact_start<now()-interval '5 minutes'),
 'max_connections',current_setting('max_connections')) FROM pg_stat_activity;
SELECT to_regprocedure('public.get_festapp_monitoring_health_v1(text)') IS NOT NULL AS existing_monitor,
 (SELECT count(*) FROM public.festapp_monitoring_credentials WHERE expires_at>now()) AS valid_monitor_capabilities;
COMMIT;
SQL
systemctl show festapp-supabase-backup.service festapp-runtime-log-upload.service --property=Id,Result,ExecMainStatus,ActiveEnterTimestamp,InactiveEnterTimestamp
