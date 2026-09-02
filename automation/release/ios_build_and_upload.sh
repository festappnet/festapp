#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_SCRIPT="$SCRIPT_DIR/.set_appstore_env.sh"
if [ ! -f "$ENV_SCRIPT" ]; then echo "Missing $ENV_SCRIPT"; exit 1; fi
source "$ENV_SCRIPT"
: "${FESTAPP_RELEASE_MANIFEST:?missing FESTAPP_RELEASE_MANIFEST}"
: "${APP_STORE_CONNECT_KEY_ID:?missing APP_STORE_CONNECT_KEY_ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?missing APP_STORE_CONNECT_ISSUER_ID}"
: "${APP_STORE_CONNECT_KEY_PATH:?missing APP_STORE_CONNECT_KEY_PATH}"
if [ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]; then
  echo "App Store Connect key not found: $APP_STORE_CONNECT_KEY_PATH"
  exit 1
fi
case "$(cd "$(dirname "$APP_STORE_CONNECT_KEY_PATH")" && pwd)/$(basename "$APP_STORE_CONNECT_KEY_PATH")" in
  "$PROJECT_ROOT"/*)
    echo "App Store Connect key must be provisioned from FestappSeed and remain outside the repository."
    exit 1
    ;;
esac
key_mode="$(stat -f '%Lp' "$APP_STORE_CONNECT_KEY_PATH")"
if [ $((8#$key_mode & 077)) -ne 0 ]; then
  echo "App Store Connect key must not be accessible by group/others."
  exit 1
fi

cd "$PROJECT_ROOT"
node automation/release/store_preflight.mjs --local --read-only
if [ "${FESTAPP_CANONICAL_CUTOVER_RELEASE:-0}" = 1 ]; then
  node automation/release/client_cutover_preflight.mjs --require-canonical-cutover
else
  node automation/release/client_cutover_preflight.mjs
fi
release_manifest="$FESTAPP_RELEASE_MANIFEST"
if [ ! -f "$release_manifest" ]; then
  echo "Release manifest not found: $release_manifest"
  exit 1
fi
target_version="$(node automation/release/project_version.mjs --version)"
target_build="$(node automation/release/project_version.mjs --build)"
export_options="$(mktemp "${TMPDIR:-/tmp}/festapp-export-options.XXXXXX.plist")"
trap 'rm -f "$export_options"' EXIT
node "$SCRIPT_DIR/render_export_options.mjs" "$release_manifest" "$export_options"
"$SCRIPT_DIR/prepare_signing_keychain.sh"
fvm flutter pub get --enforce-lockfile
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Release dependency resolution changed tracked files; commit the exact lockfile first."
  exit 1
fi
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
export IPA_PATH="${ipa_files[0]}"
export FASTLANE_APP_IDENTIFIER="$(node -p "require(process.argv[1]).bundleId" "$release_manifest")"
echo "Uploading build only; submission and release are separate gates."
cd "$SCRIPT_DIR/fastlane"
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_SKIP_INIT=true fastlane upload_build
