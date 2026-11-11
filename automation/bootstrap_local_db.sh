#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1-}" in
  '') exec python3 "$SCRIPT_DIR/local_db/runtime.py" prepare ;;
  --upgrade) exec python3 "$SCRIPT_DIR/local_db/runtime.py" upgrade ;;
  --stop) exec python3 "$SCRIPT_DIR/local_db/runtime.py" stop ;;
  --status) exec python3 "$SCRIPT_DIR/local_db/runtime.py" status ;;
  --prune) exec python3 "$SCRIPT_DIR/local_db/runtime.py" prune ;;
  *) echo 'Usage: automation/bootstrap_local_db.sh [--upgrade|--stop|--status|--prune]' >&2; exit 2 ;;
esac
