#!/usr/bin/env bash
# Real renderer code with only CMS APIs stubbed; no live CMS or external network.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 integrations/wordpress/scripts/package.py
python3 integrations/joomla/scripts/package.py
# Stream only fixture sources: this works with isolated macOS Docker file sharing.
tar -cf - \
  integrations/tests/embed-appearance-contract.php \
  integrations/wordpress/vstupenky-online/includes/embed.php \
  integrations/wordpress/festapp-tickets/includes/embed.php \
  integrations/joomla/build/mod_vstupenky_online/src/Helper/EmbedHelper.php \
  integrations/joomla/build/mod_festapp_tickets/src/Helper/EmbedHelper.php |
  docker run --rm --network none -i \
    php@sha256:d8784155c4d37986be9ddd7a8950df7e78998cc48e35472cd69e2b9371424a65 \
    sh -eu -c 'mkdir /work; tar -xf - -C /work; php /work/integrations/tests/embed-appearance-contract.php'
