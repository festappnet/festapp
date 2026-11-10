#!/usr/bin/env bash
# Real renderer code with only CMS APIs stubbed; no live CMS or external network.
set -euo pipefail
cd "$(dirname "$0")/.."
node integrations/measurement/build_gtm_preset.mjs --check
node --test web_client/tests/core/host_gtm_preset.test.js
adapter_contract_root="$(mktemp -d "${TMPDIR:-/tmp}/festapp-embed-contracts.XXXXXX")"
trap 'rm -rf "$adapter_contract_root"' EXIT
# Exercise the real packagers and generated renderers without rewriting reviewed
# release archives or their evidence in the source checkout.
python3 - "$PWD" "$adapter_contract_root" <<'FIXTURE'
from pathlib import Path
import shutil
import sys
source,target=map(Path,sys.argv[1:])
for cms in ('wordpress','joomla'):
    original=source/'integrations'/cms
    fixture=target/'integrations'/cms
    for directory in ('scripts','shared'):
        shutil.copytree(original/directory,fixture/directory,ignore=shutil.ignore_patterns('__pycache__','node_modules'))
    for name in ('products.json','translations.json'):
        if (original/name).is_file():shutil.copy2(original/name,fixture/name)
    (fixture/'evidence').mkdir()
    (fixture/'tests').mkdir(exist_ok=True)
shutil.copy2(source/'integrations/wordpress/tests/measurement-defaults.test.mjs',target/'integrations/wordpress/tests/measurement-defaults.test.mjs')
shutil.copy2(source/'integrations/joomla/tests/measurement-defaults.php',target/'integrations/joomla/tests/measurement-defaults.php')
(target/'integrations/tests').mkdir()
shutil.copy2(source/'integrations/tests/embed-appearance-contract.php',target/'integrations/tests/embed-appearance-contract.php')
FIXTURE
cd "$adapter_contract_root"
python3 integrations/wordpress/scripts/package.py
python3 integrations/joomla/scripts/package.py
node --test integrations/wordpress/tests/measurement-defaults.test.mjs
# Stream only fixture sources: this works with isolated macOS Docker file sharing.
tar -cf - \
  integrations/tests/embed-appearance-contract.php \
  integrations/joomla/tests/measurement-defaults.php \
  integrations/joomla/build/mod_vstupenky_online/src/Field/MeasurementField.php \
  integrations/joomla/build/mod_festapp_tickets/src/Field/MeasurementField.php \
  integrations/wordpress/vstupenky-online/includes/embed.php \
  integrations/wordpress/festapp-tickets/includes/embed.php \
  integrations/joomla/build/mod_vstupenky_online/src/Helper/EmbedHelper.php \
  integrations/joomla/build/mod_festapp_tickets/src/Helper/EmbedHelper.php |
  docker run --rm --network none -i \
    php@sha256:d8784155c4d37986be9ddd7a8950df7e78998cc48e35472cd69e2b9371424a65 \
    sh -eu -c 'mkdir /work; tar -xf - -C /work; php /work/integrations/tests/embed-appearance-contract.php; php /work/integrations/joomla/tests/measurement-defaults.php'
