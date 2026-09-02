#!/usr/bin/env bash
set -euo pipefail

readonly REVISION=241bb11c0627f2981746d37033f57dbfa81d29b0
readonly ROOT=/opt/festapp-supabase
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

[[ "$(id -u)" == "0" ]] || { echo "deploy-rehearsal must run as root" >&2; exit 1; }
[[ ! -e "$ROOT" ]] || { echo "$ROOT already exists; refusing to overwrite" >&2; exit 1; }

git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git "$ROOT"
git -C "$ROOT" fetch --depth 1 origin "$REVISION"
git -C "$ROOT" checkout --detach "$REVISION"

cd "$ROOT/docker"
cp .env.example .env
chmod 0600 .env
sh utils/generate-keys.sh --update-env >/dev/null
install -o root -g root -m 0644 "$SCRIPT_DIR/docker-compose.festapp.yml" docker-compose.festapp.yml
install -o root -g root -m 0644 "$SCRIPT_DIR/docker-compose.database-target.yml" docker-compose.database-target.yml
install -d -o root -g root -m 0755 caddy
install -o root -g root -m 0644 "$SCRIPT_DIR/Caddyfile" caddy/Caddyfile
install -o root -g root -m 0700 "$SCRIPT_DIR/configure-rehearsal-env.py" configure-rehearsal-env.py
install -o root -g root -m 0700 "$SCRIPT_DIR/switch-rehearsal-runtime-database.sh" switch-rehearsal-runtime-database.sh
install -o root -g root -m 0444 "$SCRIPT_DIR/../merge/source-registry.json" festapp-source-registry.json
install -o root -g root -m 0444 "$SCRIPT_DIR/../merge/reference-registry.json" festapp-reference-registry.json
install -o root -g root -m 0444 "$SCRIPT_DIR/../merge/runtime-writer-policy.json" festapp-runtime-writer-policy.json
install -o root -g root -m 0700 "$SCRIPT_DIR/install-runtime-registries.mjs" install-runtime-registries.mjs
install -o root -g root -m 0700 "$SCRIPT_DIR/validate-production-promotion.mjs" validate-production-promotion.mjs
install -o root -g root -m 0700 "$SCRIPT_DIR/promote-production-runtime.sh" promote-production-runtime.sh
install -o root -g root -m 0700 "$SCRIPT_DIR/set-production-target-write-barrier.sh" set-production-target-write-barrier.sh
install -o root -g root -m 0700 "$SCRIPT_DIR/validate-operational-readiness.mjs" validate-operational-readiness.mjs
install -o root -g root -m 0700 "$SCRIPT_DIR/install-production-function-bundle.sh" install-production-function-bundle.sh
install -o root -g root -m 0700 "$SCRIPT_DIR/upgrade-installed-production-runtime.sh" upgrade-installed-production-runtime.sh
install -o root -g root -m 0700 "$SCRIPT_DIR/rotate-rehearsal-runtime-credentials.sh" rotate-rehearsal-runtime-credentials.sh
./configure-rehearsal-env.py

docker compose config -q
docker compose pull
docker compose up -d
docker compose ps
