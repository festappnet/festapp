#!/usr/bin/env bash
# Overlap independent hosted downloads; retain both failures before running tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

needs_database="${FESTAPP_CI_NEEDS_DATABASE:-true}"
needs_browser="${FESTAPP_CI_NEEDS_BROWSER:-true}"
for required in "$needs_database" "$needs_browser"; do
  [[ "$required" == true || "$required" == false ]] || exit 2
done

image="$(python3 - <<'PY'
import json, os
from pathlib import Path
config = json.loads(Path('automation/local_db/test-base.json').read_text())
print(config['providers'][os.environ.get('FESTAPP_TEST_PG_MAJOR', '15')]['image'])
PY
)"
image_pid=''
if [[ "$needs_database" == true ]]; then
  python3 automation/local_db/images.py "$image" > /dev/null &
  image_pid=$!
fi
trap 'if [[ -n "$image_pid" ]]; then kill "$image_pid" 2>/dev/null || true; wait "$image_pid" 2>/dev/null || true; fi' EXIT

browser_status=0
if [[ "$needs_browser" == true ]]; then
  bash automation/ci/browser.sh || browser_status=$?
fi
image_status=0
if [[ -n "$image_pid" ]]; then
  wait "$image_pid" || image_status=$?
fi
trap - EXIT

if (( browser_status != 0 )); then exit "$browser_status"; fi
exit "$image_status"
