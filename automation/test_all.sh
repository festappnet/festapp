#!/usr/bin/env bash
# Explicit selected-lane wrapper; workspace ownership and outcomes: test_all.py.
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
exec python3 "$SCRIPT_DIR/test_all.py" "$@"
