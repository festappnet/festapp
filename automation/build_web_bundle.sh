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

deno run --frozen --lock=supabase/functions/deno.lock --allow-read automation/tickets/generate-preview-assets.ts --check

# Every production build must reach the image service using this tenant's
# actual domain and project, before compiling another unusable application.
node automation/verify_image_service.mjs

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

(cd automation/release/platform_updates && pnpm install --frozen-lockfile)

# project.conf is the sole tenant-identity owner. Apply it immediately before
# compilation so stale generated files can never leak between production apps.
bash automation/apply_config.sh
if [ "${FESTAPP_CANONICAL_CUTOVER_RELEASE:-0}" = 1 ]; then
    node automation/release/client_cutover_preflight.mjs --require-canonical-cutover
else
    node automation/release/client_cutover_preflight.mjs
fi

"${FLUTTER_CMD[@]}" precache --web
FESTAPP_SETUP_BUILD_ARGS=()
FESTAPP_SETUP_ENABLED="$(sed -n 's/^OCCASION_SETUP_ENABLED=//p' automation/project.conf)"
case "$FESTAPP_SETUP_ENABLED" in
    true) FESTAPP_SETUP_BUILD_ARGS+=(--dart-define=FESTAPP_OCCASION_SETUP=true) ;;
    false|'') ;;
    *) echo "OCCASION_SETUP_ENABLED must be true or false." >&2; exit 1 ;;
esac
# Pinned esbuild is also used for lexical compaction before immutable stamping.
(cd web_client && pnpm install --frozen-lockfile)
"${FLUTTER_CMD[@]}" build web --release --base-href / --no-web-resources-cdn --no-wasm-dry-run "${FESTAPP_SETUP_BUILD_ARGS[@]}"
node automation/optimize_web_fonts.mjs build/web automation/project.conf
node automation/compact_flutter_javascript.mjs build/web
bash automation/emit_version_manifest.sh build/web

if [ "$TARGET" = cloudflare ]; then
    mv build/web/index.html build/web/flutter
else
    mv build/web/index.html build/web/flutter.html
fi

# Both direct deployment and GitHub Deploy use this shared build path.
# Fail before publishing if restricted WebViews or built module identity regress.
bash automation/test_web_startup.sh
(cd web_client && pnpm run build)
cp -R web_client/dist/. build/web/
node automation/minify_web_translations.mjs build/web
# The standalone organizer document shares the compiled tenant theme and fonts.
node automation/release/render_organizer_page.mjs --config automation/project.conf --built-index web_client/dist/index.html --output build/web/organizers-page

node automation/release/render_help_pages.mjs --config automation/project.conf --built-index web_client/dist/index.html
rm -rf build/web/napoveda
if [ -d web_client/public/napoveda ]; then cp -R web_client/public/napoveda build/web/; fi

# Ship marketing media only when the shared organizer page is enabled.
LANDING_ENABLED="$(node automation/release/organizers/context.mjs --config automation/project.conf | node -e 'let input="";process.stdin.on("data",part=>input+=part);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(input).enabled)))')"
if [ "$LANDING_ENABLED" != true ]; then
    rm -rf "$BUILD_WEB_DIR/organizers-media"
fi

if [ "$TARGET" = cloudflare ]; then
    mv build/web/index.html build/web/webclient
    if [ -f build/web/auth_bridge.html ]; then
        mv build/web/auth_bridge.html build/web/auth_bridge
    fi
fi

rm -f build/web/flutter_service_worker.js
VERSION="$(grep -m1 '^VERSION=' automation/project.conf | cut -d= -f2 | tr -d '[:space:]')"
FORCED_OCCASION="$(grep -m1 '^FORCE_OCCASION_LINK=' automation/project.conf | cut -d= -f2- | tr -d '\"' | tr -d "'" | tr -d '[:space:]')"
APP_SUPPORTED="$(sed -n 's/^IS_APP_SUPPORTED=//p' automation/project.conf | tr -d '[:space:]')"
node automation/generate_pwa_service_worker.mjs build/web "$VERSION" "$FORCED_OCCASION" "$APP_SUPPORTED"
node automation/check_pwa_shell_budget.mjs build/web automation/project.conf

node automation/generate_csp_policy.mjs build/web "$TARGET"

# Cloudflare adds its edge router before running the same verifier. Static
# hosts have no generated edge worker, so their completed bundle is verified here.
if [ "$TARGET" = static ]; then
    node automation/verify_web_build.mjs build/web "$VERSION" automation/project.conf static
fi
