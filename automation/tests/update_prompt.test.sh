#!/bin/bash
# ==============================================================================
# Auto-update build wiring smoke test
#
# Covers the build-time half of the "automatická vylepšená aktualizace":
#   1. configure_version.js stamps window.__FESTAPP_BUILD_VERSION__ into
#      web/index.html.
#   2. emit_version_manifest.sh writes festapp-version.json + a version-stamped
#      main.dart copy into a built web dir.
#
# Strategy: run both against a temp tree seeded from the real repo files, so a
# regression in the regex / filename munging is caught without Flutter or npm.
#
# Usage: ./automation/tests/update_prompt.test.sh
# Exits non-zero on the first failure.
# ==============================================================================
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
echo "Temp project root: $TMP_ROOT"

fail=0
assert_contains() {
    local file="$1" needle="$2"
    if grep -F -q "$needle" "$file"; then
        echo "  ok: $(basename "$file") contains '$needle'"
    else
        echo "  FAIL: $(basename "$file") missing '$needle'"
        fail=1
    fi
}
assert_not_contains() {
    local file="$1" needle="$2"
    if grep -F -q "$needle" "$file"; then
        echo "  FAIL: $(basename "$file") unexpectedly contains '$needle'"
        fail=1
    else
        echo "  ok: $(basename "$file") omits '$needle'"
    fi
}
assert_file() {
    if [ -f "$1" ]; then
        echo "  ok: $(basename "$1") exists"
    else
        echo "  FAIL: expected file missing: $1"
        fail=1
    fi
}

# ---------------------------------------------------------------------------
# 1. configure_version.js stamps web/index.html
# ---------------------------------------------------------------------------
echo
echo "--- configure_version.js stamps __FESTAPP_BUILD_VERSION__ ---"

mkdir -p "$TMP_ROOT/automation" "$TMP_ROOT/web" "$TMP_ROOT/web_client/src"
cp "$PROJECT_ROOT/automation/configure_version.js" "$TMP_ROOT/automation/configure_version.js"
cp "$PROJECT_ROOT/web/index.html"                  "$TMP_ROOT/web/index.html"
# Minimal pubspec + package.json so the earlier steps of the script do not warn-fail.
printf 'name: festapp\nversion: 0.0.0+1\n' > "$TMP_ROOT/pubspec.yaml"
printf '{\n  "name": "web_client",\n  "version": "0.0.0"\n}\n' > "$TMP_ROOT/web_client/package.json"
printf '{\n  "name": "web_client",\n  "version": "0.0.0",\n  "lockfileVersion": 3,\n  "packages": {"": {"name": "web_client", "version": "0.0.0"}}\n}\n' \
  > "$TMP_ROOT/web_client/package-lock.json"

( cd "$TMP_ROOT" && node automation/configure_version.js 1.2.3+456 > configure.log 2>&1 ) || {
    echo "  FAIL: configure_version.js exited non-zero. Log:"; cat "$TMP_ROOT/configure.log"; fail=1;
}
assert_contains "$TMP_ROOT/web/index.html" 'window.__FESTAPP_BUILD_VERSION__ = "1.2.3+456";'
assert_contains "$TMP_ROOT/web_client/package.json" '"version": "1.2.3"'
assert_contains "$TMP_ROOT/web_client/package-lock.json" '"version": "1.2.3"'

# A fresh HTML document may still be controlled by the previous app-shell
# worker. The runtime updater must compare both versions even when the network
# manifest already equals the HTML version, otherwise stale compiled tenant
# configuration can survive indefinitely.
assert_contains "$PROJECT_ROOT/web/festapp_update_prompt.js" \
  'activeVersion && activeVersion !== currentVersion'
assert_contains "$PROJECT_ROOT/web/festapp_update_prompt.js" \
  'await cutOverToVersion(currentVersion)'
# Idempotent second run should keep the same value.
( cd "$TMP_ROOT" && node automation/configure_version.js 1.2.3+456 >> configure.log 2>&1 ) || fail=1
assert_contains "$TMP_ROOT/web/index.html" 'window.__FESTAPP_BUILD_VERSION__ = "1.2.3+456";'

# ---------------------------------------------------------------------------
# 2. emit_version_manifest.sh writes the manifest + stamped main.dart copy
# ---------------------------------------------------------------------------
echo
echo "--- emit_version_manifest.sh writes festapp-version.json + stamped main ---"

BUILD_DIR="$TMP_ROOT/build/web"
mkdir -p "$BUILD_DIR/web-assets"
CONFIG_ANON_KEY="$(sed -n 's/^SUPABASE_ANON_KEY=//p' "$PROJECT_ROOT/automation/project.conf")"
CONFIG_SUPABASE_URL="$(sed -n 's/^SUPABASE_URL=//p' "$PROJECT_ROOT/automation/project.conf")"
CONFIG_PROJECT_REF="$(sed -n 's#^SUPABASE_URL=https://\([^.]*\)\.supabase\.co/*#\1#p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_ACTIVATION_TENANT_ID="$(sed -n 's/^BACKEND_ACTIVATION_TENANT_ID=//p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_ACTIVATION_PHASE="$(sed -n 's/^BACKEND_ACTIVATION_PHASE=//p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_CANONICAL_URL="$(sed -n 's/^BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=//p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_CANONICAL_KEY="$(sed -n 's/^BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=//p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_CANONICAL_ORGANIZATION_ID="$(sed -n \
  's/^BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=//p' \
  "$PROJECT_ROOT/automation/project.conf")"
CONFIG_CANONICAL_ACTIVATION_SHA=''
CONFIG_CANONICAL_PROFILE_SHA=''
if [ -n "$CONFIG_ACTIVATION_TENANT_ID" ]; then
  CONFIG_CANONICAL_ACTIVATION_SHA="$(printf '%s\n' \
    "{\"schemaVersion\":1,\"tenantId\":\"$CONFIG_ACTIVATION_TENANT_ID\",\"generation\":1,\"backend\":\"canonical\"}" \
    | shasum -a 256 | awk '{print $1}')"
  CONFIG_CANONICAL_PROFILE_SHA="$(node \
    "$PROJECT_ROOT/automation/release/generate_backend_profile_fingerprint.mjs" \
    "$CONFIG_ACTIVATION_TENANT_ID" "$CONFIG_CANONICAL_URL" "$CONFIG_CANONICAL_KEY" \
    "$CONFIG_CANONICAL_ORGANIZATION_ID")"
  printf '%s\n' \
    "{\"schemaVersion\":1,\"tenantId\":\"$CONFIG_ACTIVATION_TENANT_ID\",\"generation\":0,\"backend\":\"$CONFIG_ACTIVATION_PHASE\"}" \
    > "$BUILD_DIR/backend-activation.json"
fi
printf '// fake compiled app\n%s\n%s\n%s\n%s\n%s\n' \
  "$CONFIG_ANON_KEY" "$CONFIG_CANONICAL_URL" "$CONFIG_CANONICAL_KEY" \
  "$CONFIG_CANONICAL_ACTIVATION_SHA" "$CONFIG_CANONICAL_PROFILE_SHA" \
  > "$BUILD_DIR/main.dart.js"
printf '<script>window.__FESTAPP_BUILD_VERSION__ = "1.2.3+456";</script><script>_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};</script>\n' \
  > "$BUILD_DIR/index.html"
printf '_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};\n' \
  > "$BUILD_DIR/flutter_bootstrap.js"
printf "const SUPABASE_KEY = 'sb-%s-auth-token';\n" "$CONFIG_PROJECT_REF" \
  > "$BUILD_DIR/auth_bridge"
printf "const supabaseUrl = '%s'; const anonKey = '%s'; const authKey = 'sb-%s-auth-token'; const canonicalUrl = '%s'; const canonicalKey = '%s'; const canonicalProfile = '%s';\n" \
  "$CONFIG_SUPABASE_URL" "$CONFIG_ANON_KEY" "$CONFIG_PROJECT_REF" \
  "$CONFIG_CANONICAL_URL" "$CONFIG_CANONICAL_KEY" "$CONFIG_CANONICAL_PROFILE_SHA" \
  > "$BUILD_DIR/web-assets/app.js"
cp "$PROJECT_ROOT/automation/emit_version_manifest.sh" "$TMP_ROOT/automation/emit_version_manifest.sh"
chmod +x "$TMP_ROOT/automation/emit_version_manifest.sh"

"$TMP_ROOT/automation/emit_version_manifest.sh" "$BUILD_DIR" "1.2.3+456" > "$TMP_ROOT/emit.log" 2>&1 || {
    echo "  FAIL: emit_version_manifest.sh exited non-zero. Log:"; cat "$TMP_ROOT/emit.log"; fail=1;
}
assert_file    "$BUILD_DIR/festapp-version.json"
assert_file    "$BUILD_DIR/main.dart.1.2.3-456.js"   # '+' becomes '-' in the filename
assert_contains "$BUILD_DIR/festapp-version.json" '"version":"1.2.3+456"'
assert_contains "$BUILD_DIR/festapp-version.json" '"main":"main.dart.1.2.3-456.js"'
assert_contains "$BUILD_DIR/index.html" '"mainJsPath":"main.dart.1.2.3-456.js"'
assert_contains "$BUILD_DIR/flutter_bootstrap.js" '"mainJsPath":"main.dart.1.2.3-456.js"'
assert_not_contains "$BUILD_DIR/index.html" '"mainJsPath":"main.dart.js"'

# The stamped copy must be byte-identical to the entrypoint it mirrors.
if cmp -s "$BUILD_DIR/main.dart.js" "$BUILD_DIR/main.dart.1.2.3-456.js"; then
    echo "  ok: stamped main.dart copy matches main.dart.js"
else
    echo "  FAIL: stamped main.dart copy differs from main.dart.js"; fail=1
fi

# The release gate must accept only a self-consistent HTML/manifest/main/worker
# set carrying the same version.
CONFIG_LOADING_LOGO="$(sed -n 's/^WEB_LOADING_LOGO_ASSET=//p' "$PROJECT_ROOT/automation/project.conf")"
printf '<script>window.__FESTAPP_BUILD_VERSION__ = "1.2.3+456";</script><script>_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.1.2.3-456.js"}]};</script><img class="initial-logo" src="%s">\n' \
  "$CONFIG_LOADING_LOGO" > "$BUILD_DIR/flutter"
printf 'const BUILD_VERSION = "1.2.3+456"; const FORCED_OCCASION_PATH = "/test-occasion"; // FESTAPP_QUERY_BUILD_VERSION\n' > "$BUILD_DIR/festapp_service_worker.js"
printf '{"start_url":"/test-occasion/"}\n' > "$BUILD_DIR/site.webmanifest"
printf 'const FORCED_OCCASION_PATH = "/test-occasion";\n' > "$BUILD_DIR/_worker.js"
CONFIG_APP_NAME="$(sed -n 's/^APP_NAME=//p' "$PROJECT_ROOT/automation/project.conf")"
CONFIG_APP_NAME="${CONFIG_APP_NAME#\"}"
CONFIG_APP_NAME="${CONFIG_APP_NAME%\"}"
CONFIG_APP_NAME="${CONFIG_APP_NAME#\'}"
CONFIG_APP_NAME="${CONFIG_APP_NAME%\'}"
LEGAL_NAV='<nav aria-label="Právní informace"><a href="/privacy/">Privacy</a><a href="/privacy/choices/">Choices</a><a href="/terms/">Terms</a><a href="/support/">Support</a></nav>'
for page in privacy privacy/choices terms support; do
    mkdir -p "$BUILD_DIR/$page"
    printf '<title>%s | %s</title>%s<h1>%s</h1>\n' "$page" "$CONFIG_APP_NAME" "$LEGAL_NAV" "$page" \
      > "$BUILD_DIR/$page/index.html"
done
mkdir -p "$BUILD_DIR/delete-account"
printf '<title>Delete | %s</title>%s<h1>Smazání účtu</h1><a href="/privacy/choices/">Choices</a>\n' \
  "$CONFIG_APP_NAME" "$LEGAL_NAV" > "$BUILD_DIR/delete-account/index.html"
if node "$PROJECT_ROOT/automation/verify_web_build.mjs" "$BUILD_DIR" "1.2.3+456" > /dev/null; then
    echo "  ok: coherent web release passes the build gate"
else
    echo "  FAIL: coherent web release was rejected by the build gate"; fail=1
fi

# A completed transition bundle must bind the entire canonical profile. Merely
# changing the source organization after compilation must invalidate both JS
# artifacts through the profile fingerprint.
ACTIVATION_ROOT="$TMP_ROOT/activation"
mkdir -p "$ACTIVATION_ROOT/automation" "$ACTIVATION_ROOT/lib"
cp "$PROJECT_ROOT/automation/project.conf" "$ACTIVATION_ROOT/automation/project.conf"
cp "$PROJECT_ROOT/lib/app_config.dart" "$ACTIVATION_ROOT/lib/app_config.dart"
CANONICAL_KEY="$(sed -n 's/^BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=//p' \
  "$PROJECT_ROOT/automation/tests/fixtures/tenants/festivalslunovrat.conf")"
for entry in \
  'BACKEND_ACTIVATION_TENANT_ID=fixture-transition' \
  'BACKEND_ACTIVATION_PHASE=legacy' \
  'BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=https://api.festapp.net' \
  "BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=$CANONICAL_KEY" \
  'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=12'; do
  key=${entry%%=*}
  sed -i.bak "s#^${key}=.*#${entry}#" "$ACTIVATION_ROOT/automation/project.conf"
  rm -f "$ACTIVATION_ROOT/automation/project.conf.bak"
done
PROFILE_SHA="$(node "$PROJECT_ROOT/automation/release/generate_backend_profile_fingerprint.mjs" \
  fixture-transition https://api.festapp.net "$CANONICAL_KEY" 12)"
printf '%s\n' '{"schemaVersion":1,"tenantId":"fixture-transition","generation":0,"backend":"legacy"}' \
  > "$BUILD_DIR/backend-activation.json"
CANONICAL_ACTIVATION_SHA="$(printf '%s\n' \
  '{"schemaVersion":1,"tenantId":"fixture-transition","generation":1,"backend":"canonical"}' \
  | shasum -a 256 | awk '{print $1}')"
printf '%s\n%s\n%s\n%s\n' \
  'https://api.festapp.net' "$CANONICAL_KEY" "$CANONICAL_ACTIVATION_SHA" "$PROFILE_SHA" \
  >> "$BUILD_DIR/main.dart.js"
cp "$BUILD_DIR/main.dart.js" "$BUILD_DIR/main.dart.1.2.3-456.js"
printf '%s\n%s\n%s\n' 'https://api.festapp.net' "$CANONICAL_KEY" "$PROFILE_SHA" \
  >> "$BUILD_DIR/web-assets/app.js"
sed -i.bak \
  's/^  static const int backendActivationCanonicalOrganizationId = .*/  static const int backendActivationCanonicalOrganizationId = 12;/' \
  "$ACTIVATION_ROOT/lib/app_config.dart"
rm -f "$ACTIVATION_ROOT/lib/app_config.dart.bak"
if node "$PROJECT_ROOT/automation/verify_web_build.mjs" "$BUILD_DIR" "1.2.3+456" \
    "$ACTIVATION_ROOT/automation/project.conf" cloudflare > /dev/null; then
    echo "  ok: transition bundle binds its complete canonical profile"
else
    echo "  FAIL: coherent transition profile was rejected"; fail=1
fi
sed -i.bak \
  's/^BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=.*/BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=13/' \
  "$ACTIVATION_ROOT/automation/project.conf"
rm -f "$ACTIVATION_ROOT/automation/project.conf.bak"
sed -i.bak \
  's/^  static const int backendActivationCanonicalOrganizationId = .*/  static const int backendActivationCanonicalOrganizationId = 13;/' \
  "$ACTIVATION_ROOT/lib/app_config.dart"
rm -f "$ACTIVATION_ROOT/lib/app_config.dart.bak"
if node "$PROJECT_ROOT/automation/verify_web_build.mjs" "$BUILD_DIR" "1.2.3+456" \
    "$ACTIVATION_ROOT/automation/project.conf" cloudflare > /dev/null 2>&1; then
    echo "  FAIL: build gate accepted a stale canonical organization profile"; fail=1
else
    echo "  ok: build gate rejects a stale canonical organization profile"
fi
mkdir -p "$TMP_ROOT/partial/automation"
cp "$PROJECT_ROOT/automation/project.conf" "$TMP_ROOT/partial/automation/project.conf"
sed -i.bak 's/^BACKEND_ACTIVATION_PHASE=.*/BACKEND_ACTIVATION_PHASE=legacy/' \
  "$TMP_ROOT/partial/automation/project.conf"
rm -f "$TMP_ROOT/partial/automation/project.conf.bak"
sed -i.bak \
  's/^BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=.*/BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=/' \
  "$TMP_ROOT/partial/automation/project.conf"
rm -f "$TMP_ROOT/partial/automation/project.conf.bak"
if node "$PROJECT_ROOT/automation/verify_web_build.mjs" "$BUILD_DIR" "1.2.3+456" \
    "$TMP_ROOT/partial/automation/project.conf" cloudflare \
    > "$TMP_ROOT/partial-activation.log" 2>&1; then
    echo "  FAIL: build gate accepted partial backend activation configuration"; fail=1
elif grep -Fq 'backend activation configuration must be complete' \
    "$TMP_ROOT/partial-activation.log"; then
    echo "  ok: build gate rejects partial backend activation configuration"
else
    echo "  FAIL: build gate rejected partial activation for the wrong reason"; fail=1
fi
printf '// mismatched bundle\n' > "$BUILD_DIR/main.dart.1.2.3-456.js"
if node "$PROJECT_ROOT/automation/verify_web_build.mjs" "$BUILD_DIR" "1.2.3+456" > /dev/null 2>&1; then
    echo "  FAIL: build gate accepted mismatched main bundles"; fail=1
else
    echo "  ok: build gate rejects mismatched main bundles"
fi

# Missing main.dart.js must fail loudly rather than emit a dangling manifest.
echo
echo "--- emit_version_manifest.sh fails when main.dart.js is absent ---"
EMPTY_DIR="$TMP_ROOT/build/empty"
mkdir -p "$EMPTY_DIR"
if "$TMP_ROOT/automation/emit_version_manifest.sh" "$EMPTY_DIR" "1.2.3+456" > /dev/null 2>&1; then
    echo "  FAIL: expected non-zero exit when main.dart.js is missing"; fail=1
else
    echo "  ok: exits non-zero when main.dart.js is missing"
fi

echo
if [ $fail -ne 0 ]; then
    echo "❌ update_prompt build wiring test FAILED"
    exit 1
fi
echo "✅ update_prompt build wiring test passed"
