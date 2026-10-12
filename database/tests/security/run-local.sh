#!/usr/bin/env bash
# Run security regressions only in a new, disposable Supabase database. Never reuse the shared test DB.
set -euo pipefail
readonly TASK_PROJECT_ID='festapp-security-remediation-20261009'
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -n "$(docker ps -a --filter "name=^supabase_db_${TASK_PROJECT_ID}$" --format '{{.Names}}')" ]]; then
  echo 'The task database already exists; refusing to stop or reuse another run.' >&2
  exit 1
fi
readonly TASK_DIRECTORY="$(mktemp -d /tmp/festapp-security-remediation.XXXXXX)"
cleanup() {
  supabase stop --project-id "$TASK_PROJECT_ID" --workdir "$TASK_DIRECTORY/local_db" --no-backup >/dev/null 2>&1 || true
  rm -rf "$TASK_DIRECTORY"
}
trap cleanup EXIT
python3 - "$REPOSITORY_ROOT" "$TASK_DIRECTORY" <<'PY'
from pathlib import Path
import sys
root, task = map(Path, sys.argv[1:])
work = task / 'local_db'
(work / 'supabase').mkdir(parents=True)
config = (root / 'automation/local_db/supabase/config.toml').read_text()
for old, new in [('festapp-db-tests-pg15', 'festapp-security-remediation-20261009'), ('55432', '55562'), ('55430', '55560')]:
    assert old in config, f'Local DB config changed: missing {old}'
    config = config.replace(old, new)
(work / 'supabase/config.toml').write_text(config)
PY
if ! FESTAPP_LOCAL_DB_WORKDIR="$TASK_DIRECTORY/local_db" FESTAPP_LOCAL_DB_PROJECT_ID="$TASK_PROJECT_ID" FESTAPP_LOCAL_DB_PORT=55562 bash "$REPOSITORY_ROOT/automation/bootstrap_local_db.sh" > "$TASK_DIRECTORY/bootstrap.log" 2>&1; then
  tail -20 "$TASK_DIRECTORY/bootstrap.log" >&2
  exit 1
fi
node "$SCRIPT_DIR/scan_attendance_security.mjs"
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55562/postgres?sslmode=disable' \
  node "$REPOSITORY_ROOT/web_client/scripts/run_db_tests.js" \
  account_intent_atomicity account_email_service_role_permissions sign_in_codes event_attendance_summary rpc_object_authorization get_all_email_templates get_email_templates_tenant_scope \
  full_deposit_flow on_site_surcharge_flow overpayment_flow companion_contract
