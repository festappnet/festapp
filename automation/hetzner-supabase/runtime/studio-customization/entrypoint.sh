#!/bin/sh
set -eu

node /opt/festapp-studio/install-logout.mjs
exec docker-entrypoint.sh "$@"
