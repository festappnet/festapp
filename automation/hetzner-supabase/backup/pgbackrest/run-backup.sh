#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 && $(hostname -s) == festapp-supabase-rehearsal-01 ]]
[[ $(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' /opt/festapp-supabase/docker/.env) == festapp_rehearsal_20260909220601 ]]
[[ -f /etc/festapp-pgbackrest/enabled ]]
exec 9>/var/lib/festapp-pgbackrest/backup.lock
flock -n 9
# Share the existing scheduled dump lock so the two jobs never compete for I/O.
exec 8>/var/backups/festapp-supabase/.lock
flock -w 1800 8
kind=diff
[[ $(date -u +%u) != 7 ]] || kind=full
[[ ${1:-} != full ]] || kind=full
docker exec --user postgres supabase-db pgbackrest --stanza=festapp --repo1-bundle=y --type="$kind" backup
docker exec --user postgres supabase-db pgbackrest --stanza=festapp check
umask 077
receipt=$(mktemp /var/lib/festapp-pgbackrest/.backup-XXXXXX)
trap 'rm -f "$receipt"' EXIT
docker exec --user postgres supabase-db pgbackrest --stanza=festapp --output=json info |
  python3 -c 'import json,sys,time; d=json.load(sys.stdin); s=d[0]; assert s["name"]=="festapp" and s["status"]["code"]==0; b=s["backup"][-1]; assert b["error"] is False if "error" in b else True; print(json.dumps({"at":time.time(),"backup_stop":b["timestamp"]["stop"],"label":b["label"],"type":b["type"],"archive_check_passed":True}))' >"$receipt"
mv "$receipt" /var/lib/festapp-pgbackrest/last-backup.json
printf 'pgBackRest backup and archive check passed\n'
