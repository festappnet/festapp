#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -z "${FESTAPP_DB_RUN_ID:-}" ]]; then
  export FESTAPP_LOCAL_DB_PROJECT_ID=festapp-security-runtime-pg17 FESTAPP_LOCAL_DB_PORT=55562 FESTAPP_TEST_PG_MAJOR=17
  keep=(); [[ "${KEEP_SECURITY_DB:-0}" == 1 ]] && keep=(--keep-workspace)
  exec python3 "$REPOSITORY_ROOT/automation/local_db/runtime.py" exec --exclusive "${keep[@]}" -- bash "$0" "$@"
fi
[[ "${FESTAPP_TEST_PG_MAJOR:-}" == 17 && "${FESTAPP_LOCAL_DB_PROJECT_ID:-}" == festapp-security-runtime-pg17 ]] || { echo 'Security proof requires its owned PG17 runtime.' >&2; exit 1; }
cd "$REPOSITORY_ROOT"
node --test "$SCRIPT_DIR/server_rpc_security.test.mjs" "$SCRIPT_DIR/inventory_concurrency.test.mjs"
node --test "$SCRIPT_DIR/deployment_drivers.test.mjs"
node "$SCRIPT_DIR/scan_attendance_security.mjs"
node "$REPOSITORY_ROOT/web_client/scripts/run_db_tests.js" \
  rpc_object_authorization full_deposit_flow on_site_surcharge_flow overpayment_flow \
  get_inventory_pools_tenant_scope event_attendance_summary
