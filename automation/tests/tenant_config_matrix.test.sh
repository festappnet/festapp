#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/festapp-config-matrix.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

copy_worktree() {
  local target=$1
  mkdir -p "$target"
  (cd "$PROJECT_ROOT" && while IFS= read -r -d '' path; do
    [[ -e "$path" || -L "$path" ]] && printf '%s\0' "$path"
  done < <(git ls-files -co --exclude-standard -z)) |
    (cd "$PROJECT_ROOT" && tar --null -T - -cf -) |
    tar -xf - -C "$target"
}

hash_generated() {
  local root=$1 path
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    if [[ -f "$root/$path" ]]; then
      shasum -a 256 "$root/$path"
    else
      printf 'missing  %s\n' "$path"
    fi
  done < "$PROJECT_ROOT/automation/tenant-overlays/generated.paths"
}

for tenant in festapp festapptickets absolventskyvelehrad aksmcz cavfotofest csmostrava2026 doobiscup farnostopava festivalslunovrat hvezdamorska jubileum2025; do
  root="$TMP_ROOT/$tenant"
  copy_worktree "$root"
  config="$PROJECT_ROOT/automation/tests/fixtures/tenants/$tenant.conf"
  (cd "$root" && bash automation/apply_config.sh "$config" >/dev/null)
  hash_generated "$root" > "$TMP_ROOT/$tenant.first.sha256"
  (cd "$root" && bash automation/apply_config.sh "$config" >/dev/null)
  hash_generated "$root" > "$TMP_ROOT/$tenant.second.sha256"
  cmp "$TMP_ROOT/$tenant.first.sha256" "$TMP_ROOT/$tenant.second.sha256"
done

grep -qE 'fixturecsm' "$TMP_ROOT/csmostrava2026/lib/app_config.dart"
grep -qF 'static webLink = "https://dev.example.invalid";' "$TMP_ROOT/festapp/web_client/src/app_config.js"
grep -qF "backendActivationTenantId = 'festapp'" "$TMP_ROOT/festapp/lib/app_config.dart"
grep -qF "backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net'" "$TMP_ROOT/festapp/web_client/src/app_config.js"
grep -qF 'backendActivationCanonicalOrganizationId = 1' "$TMP_ROOT/festapp/web_client/src/app_config.js"
cmp "$TMP_ROOT/festapp/web/backend-activation.json" \
  "$TMP_ROOT/festapp/web_client/public/backend-activation.json"
grep -qF '"generation":0,"backend":"legacy"' \
  "$TMP_ROOT/festapp/web/backend-activation.json"
grep -qE 'fixtureav' "$TMP_ROOT/absolventskyvelehrad/lib/app_config.dart"
grep -qE 'organization = 5' "$TMP_ROOT/absolventskyvelehrad/web_client/src/app_config.js"
grep -qF "static const String appName = 'Absolventský Velehrad';" "$TMP_ROOT/absolventskyvelehrad/lib/app_config.dart"
grep -qF '<meta name="apple-mobile-web-app-title" content="AV">' "$TMP_ROOT/absolventskyvelehrad/web/index.html"
grep -qF 'Mobilní aplikace pro Absolventský Velehrad.' "$TMP_ROOT/absolventskyvelehrad/web/site.webmanifest"
grep -qF "imageApiUrl = 'https://image-api.festapp.net'" "$TMP_ROOT/absolventskyvelehrad/web_client/src/app_config.js"
grep -qF "backendActivationTenantId = '';" "$TMP_ROOT/absolventskyvelehrad/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 0' "$TMP_ROOT/absolventskyvelehrad/web_client/src/app_config.js"
grep -qE 'fixturecav' "$TMP_ROOT/cavfotofest/lib/app_config.dart"
grep -qE 'fixturedoobiscup' "$TMP_ROOT/doobiscup/lib/app_config.dart"
grep -qE 'fixturefarnost' "$TMP_ROOT/farnostopava/lib/app_config.dart"
grep -qF "static const String appName = 'Rezervace Farnost Opava';" "$TMP_ROOT/farnostopava/lib/app_config.dart"
grep -qF "static const String oneSignalAppId = '';" "$TMP_ROOT/farnostopava/lib/app_config.dart"
grep -qF "static const String oneSignalWebAppId = '';" "$TMP_ROOT/farnostopava/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 11' "$TMP_ROOT/farnostopava/web_client/src/app_config.js"
grep -qF "static appName = 'Rezervace Farnost Opava'" "$TMP_ROOT/farnostopava/web_client/src/app_config.js"
grep -qF "static appTitleShort = 'Farnost Opava'" "$TMP_ROOT/farnostopava/web_client/src/app_config.js"
grep -qF "supportedLanguages = ['cs', 'en']" "$TMP_ROOT/farnostopava/web_client/src/app_config.js"
grep -qF "static const String appName = 'BISCUP';" "$TMP_ROOT/doobiscup/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 5' "$TMP_ROOT/doobiscup/web_client/src/app_config.js"
grep -qF 'group.vkhcr.doobiscup.onesignal' "$TMP_ROOT/doobiscup/ios/Runner/Runner.entitlements"
grep -qF "static const String oneSignalAppId = '';" "$TMP_ROOT/jubileum2025/lib/app_config.dart"
grep -qF "static const String oneSignalWebAppId = '';" "$TMP_ROOT/jubileum2025/lib/app_config.dart"
grep -qF 'const oneSignalWebAppId = "";' "$TMP_ROOT/jubileum2025/web/index.html"
grep -qF "static const String appName = 'Jubileum mládeže 2025';" "$TMP_ROOT/jubileum2025/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 9' "$TMP_ROOT/jubileum2025/web_client/src/app_config.js"
grep -qF 'forceOccasionLink = "jm2025"' "$TMP_ROOT/jubileum2025/web_client/src/app_config.js"
grep -qF "supportedLanguages = ['cs']" "$TMP_ROOT/jubileum2025/web_client/src/app_config.js"
grep -qF "static const String appName = 'CSA 2024';" "$TMP_ROOT/aksmcz/lib/app_config.dart"
grep -qF "static const String oneSignalAppId = '';" "$TMP_ROOT/aksmcz/lib/app_config.dart"
grep -qF "static const String oneSignalWebAppId = '';" "$TMP_ROOT/aksmcz/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 4' "$TMP_ROOT/aksmcz/web_client/src/app_config.js"
grep -qF 'forceOccasionLink = "csa2024"' "$TMP_ROOT/aksmcz/web_client/src/app_config.js"
grep -qE 'fixturehm' "$TMP_ROOT/hvezdamorska/lib/app_config.dart"
grep -qF "supabaseUrl = 'https://fixtureslunovrat.supabase.co'" "$TMP_ROOT/festivalslunovrat/lib/app_config.dart"
grep -qE 'organization = 1' "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js"
grep -qF "backendActivationTenantId = 'festivalslunovrat'" "$TMP_ROOT/festivalslunovrat/lib/app_config.dart"
grep -qF "backendActivationCanonicalSupabaseUrl = 'https://api.festapp.net'" "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js"
grep -qF 'backendActivationCanonicalOrganizationId = 19' "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js"
! grep -qF "backendActivationCanonicalSupabaseUrl = 'https://fixtureslunovrat.supabase.co'" "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js"
cmp "$TMP_ROOT/festivalslunovrat/web/backend-activation.json" \
  "$TMP_ROOT/festivalslunovrat/web_client/public/backend-activation.json"
grep -qF '"generation":0,"backend":"legacy"' \
  "$TMP_ROOT/festivalslunovrat/web/backend-activation.json"
grep -qE "supportedLanguages = \['cs', 'en', 'pl'\]" "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js"
grep -qE 'organization = 4' "$TMP_ROOT/hvezdamorska/web_client/src/app_config.js"
grep -qE 'organization = 3' "$TMP_ROOT/cavfotofest/web_client/src/app_config.js"
grep -qE 'organization = 3' "$TMP_ROOT/festapptickets/web_client/src/app_config.js"
grep -qE 'static const bool isAppSupported = false;' "$TMP_ROOT/festapptickets/lib/app_config.dart"
grep -qF "backendActivationTenantId = 'festapptickets'" "$TMP_ROOT/festapptickets/web_client/src/app_config.js"
grep -qF '"backend":"legacy"' "$TMP_ROOT/festapptickets/web_client/public/backend-activation.json"
grep -qF "backendActivationTenantId = 'cavfotofest'" "$TMP_ROOT/cavfotofest/lib/app_config.dart"
grep -qF 'backendActivationCanonicalOrganizationId = 6' "$TMP_ROOT/cavfotofest/web_client/src/app_config.js"
grep -qE 'static const bool isAllUnit = true;' "$TMP_ROOT/hvezdamorska/lib/app_config.dart"
grep -qE "supportedLanguages = \['cs', 'en'\]" "$TMP_ROOT/hvezdamorska/web_client/src/app_config.js"
grep -qE 'CSM Fixture' "$TMP_ROOT/csmostrava2026/web/delete-account/index.html"
grep -qE 'fixturecsm.supabase.co/functions/v1/confirm-account-deletion' "$TMP_ROOT/csmostrava2026/web/delete-account/index.html"
grep -qE '"flutter": "3\.47\.2"' "$TMP_ROOT/csmostrava2026/.fvmrc"
grep -qE '"dart\.flutterSdkPath": "\.fvm/versions/3\.47\.2"' "$TMP_ROOT/hvezdamorska/.vscode/settings.json"
grep -qE 'HM Fixture' "$TMP_ROOT/hvezdamorska/web/delete-account/index.html"
grep -qE 'fixturehm.supabase.co/functions/v1/confirm-account-deletion' "$TMP_ROOT/hvezdamorska/web/delete-account/index.html"
! grep -qE 'fixturecsm|csmostrava2026|fixture_csm|CSM Fixture' "$TMP_ROOT/hvezdamorska/lib/app_config.dart" "$TMP_ROOT/hvezdamorska/web_client/src/app_config.js" "$TMP_ROOT/hvezdamorska/web/index.html" "$TMP_ROOT/hvezdamorska/web/delete-account/index.html"
! grep -qE 'fixturehm|fixture_hm|HM Fixture' "$TMP_ROOT/csmostrava2026/lib/app_config.dart" "$TMP_ROOT/csmostrava2026/web_client/src/app_config.js" "$TMP_ROOT/csmostrava2026/web/index.html" "$TMP_ROOT/csmostrava2026/web/delete-account/index.html"
! grep -qE 'fixturecsm|fixturehm|fixture_csm|fixture_hm|CSM Fixture|HM Fixture' "$TMP_ROOT/cavfotofest/lib/app_config.dart" "$TMP_ROOT/cavfotofest/web_client/src/app_config.js" "$TMP_ROOT/cavfotofest/web/index.html" "$TMP_ROOT/cavfotofest/web/delete-account/index.html"
! grep -qE 'fixturecsm|fixturehm|fixture_csm|fixture_hm|CSM Fixture|HM Fixture' "$TMP_ROOT/festivalslunovrat/lib/app_config.dart" "$TMP_ROOT/festivalslunovrat/web_client/src/app_config.js" "$TMP_ROOT/festivalslunovrat/web/index.html" "$TMP_ROOT/festivalslunovrat/web/delete-account/index.html"

echo "Tenant config matrix passed"
