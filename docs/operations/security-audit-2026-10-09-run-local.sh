#!/usr/bin/env bash
# Historical diagnostic, not a passing regression gate; actual SQL is retained.
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export FESTAPP_LOCAL_DB_PROJECT_ID=festapp-security-doublecheck-20261009 FESTAPP_LOCAL_DB_PORT=55552
exec python3 "$REPOSITORY_ROOT/automation/local_db/runtime.py" exec --exclusive -- node "$SCRIPT_DIR/security-audit-2026-10-09-repro.mjs"
