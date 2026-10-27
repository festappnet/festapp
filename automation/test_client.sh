#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "$SCRIPT_DIR/configure_fonts.js" "$SCRIPT_DIR/.." --assets-only
exec python3 "$SCRIPT_DIR/test_client.py" "$@"
