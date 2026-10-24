#!/usr/bin/env bash
# Run security regressions only in a new, disposable Supabase database. Never reuse the shared test DB.
set -euo pipefail
readonly TASK_PROJECT_ID='festapp-abuse-20261016'
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -n "$(docker ps -a --filter "name=^supabase_db_${TASK_PROJECT_ID}$" --format '{{.Names}}')" ]]; then
  echo 'The task database already exists; refusing to stop or reuse another run.' >&2
  exit 1
fi
readonly TASK_DIRECTORY="$(mktemp -d /tmp/festapp-abuse.XXXXXX)"
cleanup() {
  if [[ "${KEEP_ABUSE_DB:-0}" == "1" ]]; then echo "Retained task DB and logs: $TASK_DIRECTORY"; return; fi
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
for old, new in [('festapp-db-tests-pg15', 'festapp-abuse-20261016'), ('55432', '55672'), ('55430', '55670')]:
    assert old in config, f'Local DB config changed: missing {old}'
    config = config.replace(old, new)
(work / 'supabase/config.toml').write_text(config)
script = (root / 'automation/bootstrap_local_db.sh').read_text()
replacements = [
    ('readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"', f'readonly PROJECT_ROOT="{root}"'),
    ('readonly LOCAL_WORKDIR="$SCRIPT_DIR/local_db"', f'readonly LOCAL_WORKDIR="{work}"'),
    ('festapp-db-tests-pg15', 'festapp-abuse-20261016'),
    ('55432', '55672'),
]
for old, new in replacements:
    assert old in script, f'Bootstrap contract changed: missing {old}'
    script = script.replace(old, new)
(task / 'bootstrap.sh').write_text(script)
PY
if ! bash "$TASK_DIRECTORY/bootstrap.sh" > "$TASK_DIRECTORY/bootstrap.log" 2>&1; then
  cp "$TASK_DIRECTORY/bootstrap.log" /tmp/festapp-abuse-bootstrap-failed.log
  tail -80 "$TASK_DIRECTORY/bootstrap.log" >&2
  exit 1
fi
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55672/postgres?sslmode=disable' \
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
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55672/postgres?sslmode=disable' \
  node --test "$SCRIPT_DIR/concurrency.test.mjs"

python3 "$SCRIPT_DIR/native_auth_test.py"
