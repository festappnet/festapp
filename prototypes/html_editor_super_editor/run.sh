#!/bin/sh
set -eu
cd "$(dirname "$0")"
fvm flutter pub get
fvm flutter run -d web-server --web-hostname=127.0.0.1 --web-port="${PORT:-8766}"
