#!/bin/bash
# ==============================================================================
# apply_config.sh smoke test
#
# Strategy: copy the real templates that apply_config.sh modifies into a temp
# tree, then run apply_config.sh against the fixture project.conf and assert
# the expected substitutions landed.
#
# Goal: catch regressions in the sed patterns and the portable sed wrapper,
# without spinning up Flutter or npm.
#
# Usage:
#   ./automation/tests/apply_config.test.sh
# Exits non-zero on the first failure.
# ==============================================================================
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_CONF="$SCRIPT_DIR/fixtures/project.conf"

if [ ! -f "$FIXTURE_CONF" ]; then
    echo "Fixture missing: $FIXTURE_CONF"
    exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "Temp project root: $TMP_ROOT"

# 1. Stage the files apply_config.sh writes to. Use the real ones in the repo
#    as the starting state — that way we test against actual templates.
mkdir -p "$TMP_ROOT/automation" \
         "$TMP_ROOT/automation/hetzner-supabase/merge" \
         "$TMP_ROOT/automation/lib" \
         "$TMP_ROOT/automation/release" \
         "$TMP_ROOT/.fvm" \
         "$TMP_ROOT/.vscode" \
         "$TMP_ROOT/automation/release/legal" \
         "$TMP_ROOT/automation/templates/web/delete-account" \
         "$TMP_ROOT/android/app/src/main/kotlin/fstapp/example" \
         "$TMP_ROOT/android/app/src/main" \
         "$TMP_ROOT/ios/Runner.xcodeproj" \
         "$TMP_ROOT/ios/Runner" \
         "$TMP_ROOT/ios/OneSignalNotificationServiceExtension" \
         "$TMP_ROOT/web/.well-known" \
         "$TMP_ROOT/web/delete-account" \
         "$TMP_ROOT/web" \
         "$TMP_ROOT/web_client/src" \
         "$TMP_ROOT/web_client/public" \
         "$TMP_ROOT/lib" \
         "$TMP_ROOT/assets/icons"

cp "$PROJECT_ROOT/automation/apply_config.sh" "$TMP_ROOT/automation/apply_config.sh"
cp "$PROJECT_ROOT/automation/hetzner-supabase/merge/source-registry.json" \
   "$TMP_ROOT/automation/hetzner-supabase/merge/source-registry.json"
cp "$PROJECT_ROOT/automation/lib/supabase_client_config.mjs" "$TMP_ROOT/automation/lib/supabase_client_config.mjs"
cp "$PROJECT_ROOT/automation/lib/backend_activation_manifest.mjs" "$TMP_ROOT/automation/lib/backend_activation_manifest.mjs"
cp "$PROJECT_ROOT/automation/release/generate_backend_activation_manifest.mjs" "$TMP_ROOT/automation/release/generate_backend_activation_manifest.mjs"
cp "$PROJECT_ROOT/automation/release/generate_backend_profile_fingerprint.mjs" "$TMP_ROOT/automation/release/generate_backend_profile_fingerprint.mjs"
cp "$PROJECT_ROOT/automation/release/render_legal_pages.mjs" "$TMP_ROOT/automation/release/render_legal_pages.mjs"
cp "$PROJECT_ROOT"/automation/release/legal/*.md "$TMP_ROOT/automation/release/legal/"
cp "$PROJECT_ROOT/automation/templates/web/delete-account/index.html" "$TMP_ROOT/automation/templates/web/delete-account/index.html"
cp "$FIXTURE_CONF" "$TMP_ROOT/automation/project.conf"
cp "$PROJECT_ROOT/.vscode/settings.json" "$TMP_ROOT/.vscode/settings.json"

# Snapshot real templates the script edits.
cp "$PROJECT_ROOT/web/index.html"            "$TMP_ROOT/web/index.html"
cp "$PROJECT_ROOT/web/site.webmanifest"      "$TMP_ROOT/web/site.webmanifest"
cp "$PROJECT_ROOT/web_client/index.html"     "$TMP_ROOT/web_client/index.html"
cp "$PROJECT_ROOT/web_client/public/site.webmanifest" "$TMP_ROOT/web_client/public/site.webmanifest"
cp "$PROJECT_ROOT/web_client/src/app_config.js" "$TMP_ROOT/web_client/src/app_config.js"
cp "$PROJECT_ROOT/web_client/public/auth_bridge.html" "$TMP_ROOT/web_client/public/auth_bridge.html"
cp "$PROJECT_ROOT/lib/app_config.dart"       "$TMP_ROOT/lib/app_config.dart"
cp "$PROJECT_ROOT/lib/theme_config.dart"     "$TMP_ROOT/lib/theme_config.dart"
cp "$PROJECT_ROOT/android/app/build.gradle" "$TMP_ROOT/android/app/build.gradle"
cp "$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml" "$TMP_ROOT/android/app/src/main/AndroidManifest.xml"
cp "$PROJECT_ROOT/android/app/src/main/kotlin/fstapp/MainActivity.kt" "$TMP_ROOT/android/app/src/main/kotlin/fstapp/example/MainActivity.kt"
cp "$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj" "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj"
cp "$PROJECT_ROOT/ios/Runner/Info.plist" "$TMP_ROOT/ios/Runner/Info.plist"
cp "$PROJECT_ROOT/ios/Runner/Runner.entitlements" "$TMP_ROOT/ios/Runner/Runner.entitlements"
cp "$PROJECT_ROOT/ios/OneSignalNotificationServiceExtension/Info.plist" "$TMP_ROOT/ios/OneSignalNotificationServiceExtension/Info.plist"
cp "$PROJECT_ROOT/ios/OneSignalNotificationServiceExtension/OneSignalNotificationServiceExtensionRelease.entitlements" "$TMP_ROOT/ios/OneSignalNotificationServiceExtension/OneSignalNotificationServiceExtensionRelease.entitlements"
cp "$PROJECT_ROOT/web/apple-app-site-association" "$TMP_ROOT/web/apple-app-site-association"
cp "$PROJECT_ROOT/web/.well-known/apple-app-site-association" "$TMP_ROOT/web/.well-known/apple-app-site-association"
# The fixture validates configured paths, not tenant artwork bytes. Create its
# own assets so this shared test runs from every production overlay even when
# that tenant intentionally replaces the generic main logos.
touch "$TMP_ROOT/assets/icons/fstapplogo.svg" \
      "$TMP_ROOT/assets/icons/fstapplogo.dark.svg" \
      "$TMP_ROOT/web/android-chrome-192x192.png"

# theme_config.css is optional but typically present.
if [ -f "$PROJECT_ROOT/web_client/src/theme_config.css" ]; then
    cp "$PROJECT_ROOT/web_client/src/theme_config.css" "$TMP_ROOT/web_client/src/theme_config.css"
fi

# Skip the optional helper scripts apply_config.sh calls at the end (fonts,
# version) — they require Node and a fonts/ tree we are not staging.
# apply_config.sh only invokes them if the files exist, so leaving them out
# keeps the test focused.

# 2. Run apply_config.sh in the temp tree.
cd "$TMP_ROOT"
chmod +x automation/apply_config.sh
./automation/apply_config.sh > apply_config.log 2>&1 || {
    echo "apply_config.sh exited non-zero. Log:"
    cat apply_config.log
    exit 1
}

# 3. Assertions.
fail=0
assert_contains() {
    local file="$1" needle="$2"
    if grep -F -q "$needle" "$file"; then
        echo "  ok: $file contains '$needle'"
    else
        echo "  FAIL: $file missing '$needle'"
        fail=1
    fi
}
assert_missing() {
    local file="$1" needle="$2"
    if grep -F -q "$needle" "$file"; then
        echo "  FAIL: $file should not contain '$needle' anymore"
        fail=1
    else
        echo "  ok: $file does not contain '$needle'"
    fi
}
assert_not_file() {
    if [ -e "$1" ]; then
        echo "  FAIL: unexpected file exists: $1"
        fail=1
    else
        echo "  ok: file is absent: $1"
    fi
}

echo
echo "--- generated Flutter SDK adapters ---"
assert_contains "$TMP_ROOT/.fvmrc" '"flutter": "9.9.9"'
assert_contains "$TMP_ROOT/.fvm/fvm_config.json" '"flutterSdkVersion": "9.9.9"'
assert_contains "$TMP_ROOT/.fvm/release" '9.9.9'
assert_contains "$TMP_ROOT/.vscode/settings.json" '"dart.flutterSdkPath": ".fvm/versions/9.9.9"'
assert_contains "$TMP_ROOT/.vscode/settings.json" '"java.configuration.updateBuildConfiguration": "interactive"'

echo
echo "--- web/index.html (Flutter template) ---"
assert_contains "$TMP_ROOT/web/index.html" "<title>Test App Name</title>"
assert_contains "$TMP_ROOT/web/index.html" '<meta name="apple-mobile-web-app-title" content="TST">'
assert_contains "$TMP_ROOT/web/index.html" 'const oneSignalWebAppId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";'
assert_contains "$TMP_ROOT/web/index.html" 'if (!oneSignalWebAppId) {'
assert_contains "$TMP_ROOT/web/index.html" 'appId: oneSignalWebAppId'
assert_contains "$TMP_ROOT/web/index.html" 'if (!oneSignalWebAppId) return false;'
assert_contains "$TMP_ROOT/web/index.html" 'safari_web_id: "web.onesignal.auto.test"'
assert_contains "$TMP_ROOT/web/index.html" "app_generation: 'test_generation_v1'"
assert_contains "$TMP_ROOT/web/index.html" "occasion: 'test-occasion'"
assert_contains "$TMP_ROOT/web/index.html" '<img class="initial-logo" src="android-chrome-192x192.png"'
assert_missing "$TMP_ROOT/web/index.html" '<svg class="initial-logo"'
assert_missing "$TMP_ROOT/web/index.html" 'CSM Ostrava 2026'

echo
echo "--- web_client/index.html (crawler metadata) ---"
assert_contains "$TMP_ROOT/web_client/index.html" '<title>Test App Name</title>'
assert_contains "$TMP_ROOT/web_client/index.html" '<meta name="description" content="Test application description.">'
assert_contains "$TMP_ROOT/web_client/index.html" '<meta property="og:title" content="Test App Name">'
assert_contains "$TMP_ROOT/web_client/index.html" '<meta property="twitter:description" content="Test application description.">'
assert_contains "$TMP_ROOT/web_client/index.html" '"name": "Test App Name"'
assert_contains "$TMP_ROOT/web_client/index.html" '<link rel="canonical" href="https://test.example.com/">'
assert_contains "$TMP_ROOT/web_client/index.html" '"url": "https://test.example.com/"'
assert_contains "$TMP_ROOT/web_client/index.html" '"target": "https://test.example.com/?q={search_term_string}"'
assert_contains "$TMP_ROOT/web_client/index.html" 'https://test.example.com/android-chrome-512x512.png'
assert_missing "$TMP_ROOT/web_client/index.html" 'Festapp - Vstupenky.online'

echo
echo "--- web/delete-account/index.html ---"
assert_contains "$TMP_ROOT/web/delete-account/index.html" "<title>Smazání účtu | Test App Name</title>"
assert_contains "$TMP_ROOT/web/delete-account/index.html" 'const endpoint = "https://test.supabase.co/functions/v1/confirm-account-deletion";'
assert_contains "$TMP_ROOT/web/delete-account/index.html" 'const apiKey = "test-anon-key-fixture";'
assert_missing "$TMP_ROOT/web/delete-account/index.html" "CSM Ostrava"

echo
echo "--- required legal pages ---"
assert_contains "$TMP_ROOT/web/privacy/index.html" "<title>Ochrana osobních údajů | Test App Name</title>"
assert_contains "$TMP_ROOT/web/privacy/choices/index.html" "<title>Vaše volby a práva | Test App Name</title>"
assert_contains "$TMP_ROOT/web/terms/index.html" "<title>Podmínky | Test App Name</title>"
assert_contains "$TMP_ROOT/web/support/index.html" "<title>Podpora | Test App Name</title>"
for legal_page in "$TMP_ROOT/web/privacy/index.html" "$TMP_ROOT/web/privacy/choices/index.html" \
    "$TMP_ROOT/web/terms/index.html" "$TMP_ROOT/web/support/index.html"; do
    assert_contains "$legal_page" '<nav aria-label="Právní informace">'
    assert_contains "$legal_page" 'href="/privacy/"'
    assert_contains "$legal_page" 'href="/privacy/choices/"'
    assert_contains "$legal_page" 'href="/terms/"'
    assert_contains "$legal_page" 'href="/support/"'
done

echo
echo "--- installable PWA manifests ---"
for manifest in "$TMP_ROOT/web/site.webmanifest" "$TMP_ROOT/web_client/public/site.webmanifest"; do
    assert_contains "$manifest" '"name": "Test App Name"'
    # Preserve the historical root identity so existing installations update
    # instead of becoming a competing nested PWA after an occasion cutover.
    assert_contains "$manifest" '"id": "/"'
    assert_contains "$manifest" '"start_url": "/test-occasion/event"'
    assert_contains "$manifest" '"scope": "/"'
done

echo
echo "--- installable PWA manifests ---"
for manifest in "$TMP_ROOT/web/site.webmanifest" "$TMP_ROOT/web_client/public/site.webmanifest"; do
    assert_contains "$manifest" '"name": "Test App Name"'
    # Preserve the historical root identity so existing installations update
    # instead of becoming a competing nested PWA after an occasion cutover.
    assert_contains "$manifest" '"id": "/"'
    assert_contains "$manifest" '"start_url": "/test-occasion/event"'
    assert_contains "$manifest" '"scope": "/"'
done

echo
echo "--- web_client/index.html ---"
assert_contains "$TMP_ROOT/web_client/index.html" "https://test.example.com/"

echo
echo "--- web_client/src/app_config.js ---"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static supabaseUrl = 'https://test.supabase.co';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static appName = 'Test App Name';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static appTitleShort = 'TST';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static anonKey = 'test-anon-key-fixture';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static backendActivationTenantId = '';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "auth: 'sb-test-auth-token'"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static organization = 42;"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static isAllUnit = true;"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static supportedLanguages = ['cs', 'en'];"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static webLink = "https://test.example.com";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static privacyUrl = "https://test.example.com/privacy/";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static privacyChoicesUrl = "https://test.example.com/privacy/choices/";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static termsUrl = "https://test.example.com/terms/";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static supportUrl = "https://test.example.com/support/";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static deleteAccountUrl = "https://test.example.com/delete-account/";'
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static imageApiUrl = 'https://image-api.test.example.com';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static imageProjectId = 'a';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" 'static forceOccasionLink = "test-occasion";'

echo
echo "--- web_client/public/auth_bridge.html ---"
assert_contains "$TMP_ROOT/web_client/public/auth_bridge.html" "const SUPABASE_KEY = 'sb-test-auth-token';"

echo
echo "--- lib/app_config.dart ---"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String supabaseUrl = 'https://test.supabase.co';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "'test-anon-key-fixture';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String supabaseAuthStorageKey = 'sb-test-auth-token';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String backendActivationTenantId = '';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static int organization = 42;"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const bool isAllUnit = true;"
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String webLink = "https://test.example.com";'
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String privacyUrl = "https://test.example.com/privacy/";'
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String privacyChoicesUrl = "https://test.example.com/privacy/choices/";'
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String termsUrl = "https://test.example.com/terms/";'
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String supportUrl = "https://test.example.com/support/";'
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String deleteAccountUrl = "https://test.example.com/delete-account/";'
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String imageApiUrl = 'https://image-api.test.example.com';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String imageProjectId = 'a';"
assert_contains "$TMP_ROOT/lib/app_config.dart" 'static const String? forceOccasionLink = "test-occasion";'
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String oneSignalAppId = '11111111-2222-3333-4444-555555555555';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String oneSignalWebAppId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String pushAppGeneration = 'test_generation_v1';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String programLogoAsset = 'assets/icons/fstapplogo.svg';"

echo
echo "--- native tenant identity ---"
assert_contains "$TMP_ROOT/android/app/build.gradle" 'namespace = "example.testapp"'
assert_contains "$TMP_ROOT/android/app/build.gradle" 'applicationId = "example.testapp"'
assert_contains "$TMP_ROOT/android/app/src/main/AndroidManifest.xml" 'android:label="Test App Name"'
assert_contains "$TMP_ROOT/android/app/src/main/kotlin/fstapp/example/MainActivity.kt" 'package example.testapp'
assert_contains "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj" 'PRODUCT_BUNDLE_IDENTIFIER = example.testapp;'
assert_contains "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj" 'PRODUCT_BUNDLE_IDENTIFIER = example.testapp.OneSignalNotificationServiceExtension;'
assert_contains "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj" 'DEVELOPMENT_TEAM = TESTTEAM01;'
assert_contains "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj" 'PROVISIONING_PROFILE_SPECIFIER = "Test AppStore";'
assert_contains "$TMP_ROOT/ios/Runner.xcodeproj/project.pbxproj" 'PROVISIONING_PROFILE_SPECIFIER = "Test OneSignal AppStore";'
assert_contains "$TMP_ROOT/ios/Runner/Runner.entitlements" '<string>group.example.testapp.onesignal</string>'
assert_contains "$TMP_ROOT/ios/Runner/Runner.entitlements" '<string>applinks:test.example.com</string>'
assert_contains "$TMP_ROOT/ios/OneSignalNotificationServiceExtension/Info.plist" '<string>group.example.testapp.onesignal</string>'
assert_contains "$TMP_ROOT/web/apple-app-site-association" 'TESTTEAM01.example.testapp'
assert_contains "$TMP_ROOT/web/.well-known/apple-app-site-association" 'TESTTEAM01.example.testapp'

echo
echo "--- lib/theme_config.dart (seed colors) ---"
assert_contains "$TMP_ROOT/lib/theme_config.dart" "static Color seed1 = const Color(0xFF112233);"
assert_contains "$TMP_ROOT/lib/theme_config.dart" "static Color seed4 = const Color(0xFFAABBCC);"

echo
echo "--- web_client/public/CNAME ---"
assert_contains "$TMP_ROOT/web_client/public/CNAME" "test.example.com"

echo
echo "--- self-hosted Supabase origin ---"
node - "$TMP_ROOT/automation/project.conf" <<'NODE'
const fs = require('fs');
const configPath = process.argv[2];
const source = fs.readFileSync(configPath, 'utf8');
fs.writeFileSync(
  configPath,
  source.replace(/^SUPABASE_URL=.*$/m, 'SUPABASE_URL=https://api.example.com'),
);
NODE
./automation/apply_config.sh > apply_config-self-hosted.log 2>&1 || {
    echo "apply_config.sh rejected a self-hosted HTTPS origin. Log:"
    cat apply_config-self-hosted.log
    exit 1
}
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "static supabaseUrl = 'https://api.example.com';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "auth: 'sb-selfhost-d0c43d3885064d9a-auth-token'"
assert_contains "$TMP_ROOT/web_client/public/auth_bridge.html" "const SUPABASE_KEY = 'sb-selfhost-d0c43d3885064d9a-auth-token';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String supabaseUrl = 'https://api.example.com';"

printf '\nSUPABASE_AUTH_STORAGE_KEY=sb-previous-cloud-auth-token\n' >> "$TMP_ROOT/automation/project.conf"
./automation/apply_config.sh > apply_config-stable-auth-key.log 2>&1 || {
    echo "apply_config.sh rejected an explicit stable auth namespace. Log:"
    cat apply_config-stable-auth-key.log
    exit 1
}
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "auth: 'sb-previous-cloud-auth-token'"
assert_contains "$TMP_ROOT/web_client/public/auth_bridge.html" "const SUPABASE_KEY = 'sb-previous-cloud-auth-token';"

echo
echo "--- one-way backend activation generation ---"
node - "$TMP_ROOT/automation/project.conf" <<'NODE'
const fs = require('fs');
const configPath = process.argv[2];
let source = fs.readFileSync(configPath, 'utf8');
for (const [key, value] of Object.entries({
  BACKEND_ACTIVATION_TENANT_ID: 'fixture-transition',
  BACKEND_ACTIVATION_PHASE: 'legacy',
  BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL: 'https://api.festapp.net',
  BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY: 'fixture-canonical-key',
  BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID: '84',
})) {
  const line = `${key}=${value}`;
  source = new RegExp(`^${key}=.*$`, 'm').test(source)
    ? source.replace(new RegExp(`^${key}=.*$`, 'm'), line)
    : `${source.trimEnd()}\n${line}\n`;
}
fs.writeFileSync(configPath, source);
NODE
./automation/apply_config.sh > apply_config-activation.log 2>&1 || {
    echo "apply_config.sh rejected complete activation configuration. Log:"
    cat apply_config-activation.log
    exit 1
}
cmp -s "$TMP_ROOT/web/backend-activation.json" \
       "$TMP_ROOT/web_client/public/backend-activation.json" || {
    echo "activation manifests differ" >&2; exit 1;
}
assert_contains "$TMP_ROOT/web/backend-activation.json" '"backend":"legacy"'
assert_contains "$TMP_ROOT/lib/app_config.dart" \
    "static const String backendActivationTenantId = 'fixture-transition';"
assert_contains "$TMP_ROOT/lib/app_config.dart" \
    "static const String backendActivationManifestUrl = 'https://test.example.com/backend-activation.json';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" \
    "static backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net';"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" \
    'static backendActivationCanonicalOrganizationId = 84;'
assert_contains "$TMP_ROOT/lib/app_config.dart" \
    'static const int backendActivationCanonicalOrganizationId = 84;'
EXPECTED_ACTIVATION_SHA="$(node --input-type=module - \
    "$TMP_ROOT/automation/lib/backend_activation_manifest.mjs" <<'NODE'
const modulePath = process.argv[2];
const { canonicalBackendActivationSha256 } = await import(`file://${modulePath}`);
process.stdout.write(canonicalBackendActivationSha256('fixture-transition'));
NODE
)"
assert_contains "$TMP_ROOT/lib/app_config.dart" "$EXPECTED_ACTIVATION_SHA"
EXPECTED_PROFILE_SHA="$(node \
    "$TMP_ROOT/automation/release/generate_backend_profile_fingerprint.mjs" \
    fixture-transition https://api.festapp.net fixture-canonical-key 84)"
assert_contains "$TMP_ROOT/lib/app_config.dart" "$EXPECTED_PROFILE_SHA"
assert_contains "$TMP_ROOT/web_client/src/app_config.js" "$EXPECTED_PROFILE_SHA"

sed -i.bak \
    's#^BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=.*#BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=https://api.example.com#' \
    "$TMP_ROOT/automation/project.conf"
set +e
./automation/apply_config.sh > apply_config-activation-same-origin.log 2>&1
same_origin_status=$?
set -e
if [ "$same_origin_status" -eq 0 ]; then
    echo "apply_config.sh accepted identical legacy and canonical origins" >&2
    exit 1
fi
assert_contains "$TMP_ROOT/apply_config-activation-same-origin.log" \
    'backend activation canonical origin must differ from the legacy origin'
mv "$TMP_ROOT/automation/project.conf.bak" "$TMP_ROOT/automation/project.conf"

node - "$TMP_ROOT/automation/project.conf" <<'NODE'
const fs = require('fs');
const configPath = process.argv[2];
let source = fs.readFileSync(configPath, 'utf8');
for (const key of [
  'BACKEND_ACTIVATION_TENANT_ID',
  'BACKEND_ACTIVATION_PHASE',
  'BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL',
  'BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY',
  'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID',
]) source = source.replace(new RegExp(`^${key}=.*$`, 'm'), `${key}=`);
fs.writeFileSync(configPath, source);
NODE
./automation/apply_config.sh > apply_config-activation-disabled.log 2>&1 || {
    cat apply_config-activation-disabled.log; exit 1;
}
assert_not_file "$TMP_ROOT/web/backend-activation.json"
assert_not_file "$TMP_ROOT/web_client/public/backend-activation.json"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String backendActivationTenantId = '';"
assert_contains "$TMP_ROOT/lib/app_config.dart" "static const String backendActivationCanonicalProfileSha256 = '';"

for invalid_url in \
    'https://user:pass@api.example.com' \
    'https://api.example.com/rest/v1' \
    'https://api.example.com?tenant=a' \
    'https://api.example.com#fragment'; do
    node - "$TMP_ROOT/automation/project.conf" "$invalid_url" <<'NODE'
const fs = require('fs');
const [configPath, invalidUrl] = process.argv.slice(2);
const source = fs.readFileSync(configPath, 'utf8');
fs.writeFileSync(configPath, source.replace(/^SUPABASE_URL=.*$/m, `SUPABASE_URL=${invalidUrl}`));
NODE
    if ./automation/apply_config.sh > apply_config-invalid-origin.log 2>&1; then
        echo "apply_config.sh accepted invalid Supabase origin: $invalid_url" >&2
        exit 1
    fi
done

# 4. Verify the seed Color() change happens in upper-case as the script writes
#    it. We assert lowercase is NOT present because BSD sed and GNU sed differ
#    in how they handle replacement strings on rare flags.
if grep -F -q "static Color seed1 = const Color(0xff112233);" "$TMP_ROOT/lib/theme_config.dart"; then
    echo "  FAIL: lib/theme_config.dart kept lowercase 0xff which the script does not write"
    fail=1
fi

echo
if [ $fail -ne 0 ]; then
    echo "❌ apply_config.sh test FAILED"
    exit 1
fi
echo "✅ apply_config.sh test passed"
