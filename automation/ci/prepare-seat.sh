#!/usr/bin/env bash
# Overlap independent hosted downloads; retain both failures before running tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

image="$(python3 - <<'PY'
import json, os
from pathlib import Path
config = json.loads(Path('automation/local_db/test-base.json').read_text())
print(config['providers'][os.environ.get('FESTAPP_TEST_PG_MAJOR', '15')]['image'])
PY
)"
docker pull "$image" &
image_pid=$!
trap 'kill "$image_pid" 2>/dev/null || true; wait "$image_pid" 2>/dev/null || true' EXIT

browser_status=0
bash automation/ci/browser.sh || browser_status=$?
image_status=0
wait "$image_pid" || image_status=$?
trap - EXIT

if (( browser_status != 0 )); then exit "$browser_status"; fi
exit "$image_status"
