#!/usr/bin/env bash
# Foreground HTTPS frontend of the existing disposable WordPress/embed fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
joomla_root="$PWD"
mkdir -p .private
if [[ ! -f .private/fixture-cert.pem ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout .private/fixture-key.pem -out .private/fixture-cert.pem -days 2 -subj /CN=vstupenky.online > .private/cert.log 2>&1
fi
chmod 600 .private/fixture-key.pem
cd ../wordpress
export FESTAPP_EMBED_TLS_CERT="$joomla_root/.private/fixture-cert.pem"
export FESTAPP_EMBED_TLS_KEY="$joomla_root/.private/fixture-key.pem"
exec pnpm run web:start
