#!/usr/bin/env bash
# Same regression checks as GitHub, with pinned runtimes and disposable local SQL.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec python3 automation/ci/run.py local "$@"
