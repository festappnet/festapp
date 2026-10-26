#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable"

cleanup() {
  "$SCRIPT_DIR/bootstrap_local_db.sh" --stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

echo "[1/4] SQL domain and projection contract"
"$SCRIPT_DIR/bootstrap_local_db.sh" >/dev/null
DATABASE_URL="$TEST_DATABASE_URL" node web_client/scripts/run_db_tests.js \
  database/tests/users/reception_qr_login_test.sql

echo "[2/4] Edge exchange and cancel orchestration"
deno test \
  supabase/functions/exchange-login-qr/qr_test.ts \
  supabase/functions/exchange-login-qr/exchange_test.ts \
  supabase/functions/cancel-reception-registration/cancel_test.ts

echo "[3/4] Dart payload and Flutter feature/model contracts"
"$SCRIPT_DIR/test_client.sh" core
CLIENT_TEST_WORKERS="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from test_client import client_concurrency; print(client_concurrency())' "$SCRIPT_DIR")"
fvm flutter test --concurrency="$CLIENT_TEST_WORKERS" \
  test/sessions/shared_default_3_test.dart \
  test/sessions/shared_default_1_test.dart \
  test/components/users/login_feedback_cases.dart

echo "[4/4] Static contract and secret-absence checks"
fvm flutter analyze --no-fatal-infos \
  lib/components/reception \
  lib/data_services/auth_service.dart \
  lib/data_services/rights_service.dart \
  lib/components/users/occasion_user_model.dart || {
    code=$?
    echo "Flutter analyze reported diagnostics (exit $code)." >&2
    exit "$code"
  }
if rg -n \
  '(console\.(log|error)|AppLogger|debugPrint|print\().*(payload|token|refresh|access)' \
  supabase/functions/exchange-login-qr \
  supabase/functions/cancel-reception-registration \
  lib/components/reception; then
  echo "Sensitive reception logging pattern found." >&2
  exit 1
fi

echo "Reception rollout contract passed. No production state was changed."
