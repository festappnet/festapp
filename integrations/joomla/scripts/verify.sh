#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .private evidence
python3 scripts/package.py > .private/package.log
# Build twice and require byte identity.
cp evidence/packages.json .private/packages-first.json
python3 scripts/package.py > .private/package-repeat.log
cmp evidence/packages.json .private/packages-first.json
python3 scripts/stage-release.py > .private/stage-release.log
for major in 5 6; do
  container="festapp-joomla-20261026-$major"
  for product in mod_vstupenky_online mod_festapp_tickets; do
    version=$(python3 -c 'import json,sys;print(next(p["version"] for p in json.load(open("products.json")) if p["element"]==sys.argv[1]))' "$product")
    docker exec "$container" cp "/artifacts/$product-$version.zip" /tmp/
    docker exec "$container" php cli/joomla.php extension:install --path="/tmp/$product-$version.zip" > ".private/install-$major-$product.log" 2>&1
    docker exec "$container" sh -c "find modules/$product -name '*.php' -print0 | xargs -0 -n1 php -l" > ".private/lint-$major-$product.log"
  done
  docker exec "$container" php /tests/contract.php > "evidence/contract-$major.json"
  docker exec "$container" php /tests/seed.php > ".private/seed-$major.json"
  docker exec "$container" php /tests/clear-cache.php > ".private/seed-cache-$major.log"
done
python3 tests/installed-files.py
python3 tests/cms.py
python3 tests/native-publication.py
python3 tests/browser.py
python3 tests/updater.py
python3 scripts/check-live.py
python3 tests/live-browser.py
for major in 5 6; do
  docker exec "festapp-joomla-20261026-$major" php /tests/lifecycle.php > "evidence/lifecycle-$major.json"
  docker exec "festapp-joomla-20261026-$major" php /tests/clear-cache.php > ".private/clear-cache-$major.log"
done
python3 tests/uninstall-http.py
printf 'PASS Joomla installed ZIP contracts, CMS lifecycle and browser checks\n'
