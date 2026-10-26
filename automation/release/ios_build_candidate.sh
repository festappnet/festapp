#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${FESTAPP_RELEASE_MANIFEST:?missing FESTAPP_RELEASE_MANIFEST}"

release_manifest="$(cd "$(dirname "$FESTAPP_RELEASE_MANIFEST")" && pwd)/$(basename "$FESTAPP_RELEASE_MANIFEST")"
if [ ! -f "$release_manifest" ]; then
  echo "Release manifest not found: $release_manifest"
  exit 1
fi

cd "$PROJECT_ROOT"
if [ -n "$(git status --porcelain=v1)" ]; then
  echo "iOS candidate build requires a clean committed source tree."
  exit 1
fi

bundle_id="$(node -e 'const m=require(process.argv[1]); if(!m.bundleId) process.exit(1); process.stdout.write(m.bundleId)' "$release_manifest")"
team_id="$(awk -F= '$1=="IOS_DEVELOPMENT_TEAM" {gsub(/^[[:space:]\"'\'' ]+|[[:space:]\"'\'' ]+$/, "", $2); print $2}' automation/project.conf)"
app_profile="$(awk -F= '$1=="IOS_PROVISIONING_PROFILE" {sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print}' automation/project.conf)"
extension_profile="$(awk -F= '$1=="IOS_ONESIGNAL_PROVISIONING_PROFILE" {sub(/^[^=]*=/, ""); gsub(/^\"|\"$/, ""); print}' automation/project.conf)"
if ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "IOS_DEVELOPMENT_TEAM must be a 10-character Apple team ID."
  exit 1
fi
if [ -z "$app_profile" ] || [ -z "$extension_profile" ]; then
  echo "Both App Store provisioning profile names are required for a build-only candidate."
  exit 1
fi
target_version="$(node automation/release/project_version.mjs --version)"
target_build="$(node automation/release/project_version.mjs --build)"
source_sha="$(git rev-parse HEAD)"

if ! rg -Fq "PRODUCT_BUNDLE_IDENTIFIER = $bundle_id;" ios/Runner.xcodeproj/project.pbxproj; then
  echo "Release manifest bundle ID does not match the iOS project."
  exit 1
fi

node automation/release/client_cutover_preflight.mjs --require-canonical-cutover
"$SCRIPT_DIR/prepare_signing_keychain.sh"
fvm flutter pub get --enforce-lockfile
if [ -n "$(git status --porcelain=v1)" ]; then
  echo "Release dependency resolution changed tracked files; commit the exact lockfile first."
  exit 1
fi

export_options="$(mktemp /tmp/festapp-ios-export-options.XXXXXX.plist)"
certificate_dir="$(mktemp -d /tmp/festapp-ios-candidate-cert.XXXXXX)"
trap 'trash "$export_options" "$certificate_dir" >/dev/null 2>&1 || true' EXIT
cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$team_id</string>
  <key>provisioningProfiles</key><dict>
    <key>$bundle_id</key><string>$app_profile</string>
    <key>$bundle_id.OneSignalNotificationServiceExtension</key><string>$extension_profile</string>
  </dict>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
plutil -lint "$export_options" >/dev/null

rm -rf build/ios/archive build/ios/ipa
fvm flutter build ipa --release \
  --no-pub \
  --build-name="$target_version" \
  --build-number="$target_build" \
  --export-options-plist="$export_options"

archive_app="$PROJECT_ROOT/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
if [ -d "$archive_app/Frameworks/OneSignalLocation.framework" ]; then
  echo "Release archive unexpectedly contains OneSignalLocation.framework."
  exit 1
fi

ipa_files=("$PROJECT_ROOT"/build/ios/ipa/*.ipa)
if [ "${#ipa_files[@]}" -ne 1 ] || [ ! -f "${ipa_files[0]}" ]; then
  echo "Expected exactly one IPA in build/ios/ipa."
  exit 1
fi

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$archive_app/Info.plist")"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$archive_app/Info.plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$archive_app/Info.plist")"
if [ "$actual_bundle_id|$actual_version|$actual_build" != "$bundle_id|$target_version|$target_build" ]; then
  echo "Built iOS identity or version does not match the release contract."
  exit 1
fi

certificate_sha256="$(codesign -d --extract-certificates="$certificate_dir/cert" "$archive_app" 2>/dev/null && \
  openssl x509 -inform DER -in "$certificate_dir/cert0" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')"
if ! [[ "$certificate_sha256" =~ ^[0-9A-Fa-f]{64}$ ]]; then
  echo "Could not verify the iOS signing certificate fingerprint."
  exit 1
fi

ipa="${ipa_files[0]}"
ipa_sha256="$(shasum -a 256 "$ipa" | awk '{print $1}')"
ipa_bytes="$(stat -f '%z' "$ipa")"
printf 'IOS_CUTOVER_CANDIDATE_READY\n'
printf 'Bundle ID: %s\nVersion: %s (%s)\nSource: %s\n' "$bundle_id" "$target_version" "$target_build" "$source_sha"
printf 'Signing certificate SHA-256: %s\nIPA SHA-256: %s\nIPA bytes: %s\nIPA: %s\n' \
  "$(printf '%s' "$certificate_sha256" | tr '[:upper:]' '[:lower:]')" "$ipa_sha256" "$ipa_bytes" "$ipa"
printf 'App Store Connect mutated: false\n'
