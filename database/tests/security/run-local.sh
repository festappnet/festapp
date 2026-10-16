#!/usr/bin/env bash
set -euo pipefail
readonly TASK_PROJECT_ID='festapp-security-remediation-20261016'
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -n "$(docker ps -a --filter "name=^supabase_db_${TASK_PROJECT_ID}$" --format '{{.Names}}')" ]]; then
  echo 'Task database already exists; refusing reuse.' >&2; exit 1
fi
# Check both ports before bootstrap (which stops only this task project).
python3 - <<'CHECK'
import socket
for port in (55562,55560):
 s=socket.socket(); s.bind(('127.0.0.1',port)); s.close()
CHECK
readonly TASK_DIRECTORY="$(mktemp -d /tmp/festapp-security.XXXXXX)"
cleanup() {
  if [[ "${KEEP_SECURITY_DB:-0}" == 1 ]]; then echo "Retained task DB/logs: $TASK_DIRECTORY"; return; fi
  supabase stop --project-id "$TASK_PROJECT_ID" --workdir "$TASK_DIRECTORY/local_db" --no-backup >/dev/null 2>&1 || true
  rm -rf "$TASK_DIRECTORY"
}
trap cleanup EXIT
python3 - "$REPOSITORY_ROOT" "$TASK_DIRECTORY" <<'CONFIG'
from pathlib import Path
import sys
root, task=map(Path,sys.argv[1:])
work=task/'local_db/supabase'; work.mkdir(parents=True)
config=(root/'automation/local_db/supabase/config.toml').read_text()
for old,new in [('festapp-db-tests-pg15','festapp-security-remediation-20261016'),('55432','55562'),('55430','55560'),('major_version = 15','major_version = 17')]:
 assert old in config
 config=config.replace(old,new)
(work/'config.toml').write_text(config)
CONFIG
if ! FESTAPP_LOCAL_DB_WORKDIR="$TASK_DIRECTORY/local_db" FESTAPP_LOCAL_DB_PROJECT_ID="$TASK_PROJECT_ID" FESTAPP_LOCAL_DB_PORT=55562 bash "$REPOSITORY_ROOT/automation/bootstrap_local_db.sh" > "$TASK_DIRECTORY/bootstrap.log" 2>&1; then
  tail -30 "$TASK_DIRECTORY/bootstrap.log" >&2; exit 1
fi
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55562/postgres?sslmode=disable'
node --test "$SCRIPT_DIR/server_rpc_security.test.mjs" "$SCRIPT_DIR/inventory_concurrency.test.mjs"
node --test "$SCRIPT_DIR/deployment_drivers.test.mjs"
node "$SCRIPT_DIR/scan_attendance_security.mjs"
node "$REPOSITORY_ROOT/web_client/scripts/run_db_tests.js" \
  rpc_object_authorization full_deposit_flow on_site_surcharge_flow overpayment_flow \
  get_inventory_pools_tenant_scope event_attendance_summary
