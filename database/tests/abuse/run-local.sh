#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -z "${FESTAPP_DB_RUN_ID:-}" ]]; then
  export FESTAPP_LOCAL_DB_PROJECT_ID=festapp-abuse-runtime-pg15 FESTAPP_LOCAL_DB_PORT=55672 FESTAPP_TEST_PG_MAJOR=15
  keep=(); [[ "${KEEP_ABUSE_DB:-0}" == 1 ]] && keep=(--keep-workspace)
  exec python3 "$REPOSITORY_ROOT/automation/local_db/runtime.py" exec --exclusive "${keep[@]}" -- bash "$0" "$@"
fi
[[ "${FESTAPP_LOCAL_DB_PROJECT_ID:-}" == festapp-abuse-runtime-pg15 ]] || { echo 'Abuse proof requires its dedicated owned runtime.' >&2; exit 1; }
cd "$REPOSITORY_ROOT"
node "$REPOSITORY_ROOT/web_client/scripts/run_db_tests.js" \
  database/tests/abuse/ database/tests/occasion_setup/drafts_test.sql \
  duplicate_occasion_target_unit_test.sql duplicate_occasion_creator_editor_test.sql \
  database/tests/public_links/public_links_test.sql \
  database/tests/emails/account_intent_atomicity_test.sql \
  database/tests/emails/account_email_service_role_permissions_test.sql \
  database/tests/emails/order_ticket_intents_test.sql \
  database/tests/emails/ticket_cancellation_outcomes_test.sql \
  database/tests/cleaning/cleaning_test.sql \
  database/tests/security/rpc_object_authorization_test.sql \
  database/tests/security/event_attendance_summary_test.sql \
  database/tests/security/sign_in_codes_test.sql \
  database/tests/security/remediation_verification_test.sql \
  full_deposit_flow on_site_surcharge_flow overpayment_flow storno_reminder_cleanup \
  database/tests/users/password_reset_rate_limit_test.sql \
  database/tests/eshop/transactions/bank_sync_ticket_delivery_test.sql \
  database/tests/eshop/transactions/bank_sync_atomicity_test.sql \
  database/tests/eshop/transactions/bank_sync_operations_test.sql
node --test "$SCRIPT_DIR/concurrency.test.mjs"

python3 "$SCRIPT_DIR/native_auth_test.py"
