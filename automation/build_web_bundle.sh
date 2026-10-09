#!/bin/bash
# Canonical Flutter + web-client bundle builder for every hosting adapter.
set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
    cloudflare|static) ;;
    *) echo "Usage: $0 <cloudflare|static>" >&2; exit 1 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_WEB_DIR="$PROJECT_ROOT/build/web"
WEB_CLIENT_DIST_DIR="$PROJECT_ROOT/web_client/dist"
cd "$PROJECT_ROOT"

# Generated output must never retain content-hashed files from another tenant.
rm -rf -- "$BUILD_WEB_DIR" "$WEB_CLIENT_DIST_DIR"

FLUTTER_VERSION="$(node automation/flutter_version.mjs)"
FLUTTER_CMD=()

if command -v flutter >/dev/null 2>&1; then
    AVAILABLE_FLUTTER_VERSION="$(flutter --version --machine 2>/dev/null | node -e 'let input="";process.stdin.on("data",c=>input+=c);process.stdin.on("end",()=>{try{process.stdout.write(JSON.parse(input).frameworkVersion||"")}catch{}});')"
    if [ "$AVAILABLE_FLUTTER_VERSION" = "$FLUTTER_VERSION" ]; then
        FLUTTER_CMD=(flutter)
    fi
fi

if [ "${#FLUTTER_CMD[@]}" -eq 0 ] && command -v fvm >/dev/null 2>&1; then
    fvm install "$FLUTTER_VERSION"
    FLUTTER_CMD=(fvm spawn "$FLUTTER_VERSION")
fi

if [ "${#FLUTTER_CMD[@]}" -eq 0 ]; then
    FESTAPP_FLUTTER_INSTALL_DIR="${FESTAPP_FLUTTER_INSTALL_DIR:-${HOME}/.cache/festapp/flutter-${FLUTTER_VERSION}}"
    if [ ! -x "$FESTAPP_FLUTTER_INSTALL_DIR/bin/flutter" ]; then
        echo "Installing Flutter ${FLUTTER_VERSION} (linux)..."
        mkdir -p "$FESTAPP_FLUTTER_INSTALL_DIR"
        curl -L "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
            | tar -xJf - --strip-components=1 -C "$FESTAPP_FLUTTER_INSTALL_DIR"
    fi
    FLUTTER_CMD=("$FESTAPP_FLUTTER_INSTALL_DIR/bin/flutter")
fi

# FVM 4 prefixes spawned command output with a human-readable status line.
# Parse from the JSON object so direct Flutter and FVM output share one path.
ACTUAL_FLUTTER_VERSION="$("${FLUTTER_CMD[@]}" --version --machine | node -e 'let input="";process.stdin.on("data",c=>input+=c);process.stdin.on("end",()=>{const start=input.indexOf("{");process.stdout.write(JSON.parse(input.slice(start)).frameworkVersion);});')"
if [ "$ACTUAL_FLUTTER_VERSION" != "$FLUTTER_VERSION" ]; then
    echo "Flutter ${FLUTTER_VERSION} required by automation/project.conf, found ${ACTUAL_FLUTTER_VERSION}." >&2
    exit 1
fi

# project.conf is the sole tenant-identity owner. Apply it immediately before
# compilation so stale generated files can never leak between production apps.
bash automation/apply_config.sh
if [ "${FESTAPP_CANONICAL_CUTOVER_RELEASE:-0}" = 1 ]; then
    node automation/release/client_cutover_preflight.mjs --require-canonical-cutover
else
    node automation/release/client_cutover_preflight.mjs
fi

"${FLUTTER_CMD[@]}" precache --web
"${FLUTTER_CMD[@]}" build web --release --base-href / --no-web-resources-cdn --no-wasm-dry-run
bash automation/emit_version_manifest.sh build/web

if [ "$TARGET" = cloudflare ]; then
    mv build/web/index.html build/web/flutter
else
    mv build/web/index.html build/web/flutter.html
fi

(cd web_client && npm ci && npm run build)
cp -R web_client/dist/. build/web/

if [ "$TARGET" = cloudflare ]; then
    mv build/web/index.html build/web/webclient
    if [ -f build/web/auth_bridge.html ]; then
        mv build/web/auth_bridge.html build/web/auth_bridge
    fi
fi

rm -f build/web/flutter_service_worker.js
VERSION="$(grep -m1 '^VERSION=' automation/project.conf | cut -d= -f2 | tr -d '[:space:]')"
FORCED_OCCASION="$(grep -m1 '^FORCE_OCCASION_LINK=' automation/project.conf | cut -d= -f2- | tr -d '\"' | tr -d "'" | tr -d '[:space:]')"
node automation/generate_pwa_service_worker.mjs build/web "$VERSION" "$FORCED_OCCASION"
node automation/check_pwa_shell_budget.mjs build/web automation/project.conf

# Cloudflare adds its edge router before running the same verifier. Static
# hosts have no generated edge worker, so their completed bundle is verified here.
if [ "$TARGET" = static ]; then
    node automation/verify_web_build.mjs build/web "$VERSION" automation/project.conf static
fi
