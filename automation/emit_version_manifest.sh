#!/bin/bash
# ==============================================================================
# EMIT VERSION MANIFEST
# Purpose: emit the automatic-update manifest into a built web output.
#
#   - build/web/festapp-version.json  {"version":"<ver>","main":"main.dart.<ver>.js"}
#   - build/web/main.dart.<ver>.js    version-stamped copy of main.dart.js
#   - Flutter bootstrap points at that immutable version-stamped entrypoint
#
# The client (web/festapp_update_prompt.js, copied into build/web by
# `flutter build web`) polls festapp-version.json and compares its "version"
# against window.__FESTAPP_BUILD_VERSION__ (baked into index.html by
# automation/configure_version.js). When they differ it shows a reload banner.
# The stamped main.dart copy lets a specific build be fetched cache-busted and
# matches deployed tenant layouts (main.dart.js AND main.dart.<ver>.js).
#
# Split out of cloudflare_build.sh so it can be unit tested without a Flutter
# build (see automation/tests/update_prompt.test.sh).
#
# Usage: emit_version_manifest.sh <build_web_dir> [version]
#   version defaults to VERSION= in automation/project.conf.
# ==============================================================================
set -e

BUILD_DIR="${1:-build/web}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION="${2:-$(grep -m1 '^VERSION=' "$SCRIPT_DIR/project.conf" | cut -d= -f2 | tr -d '[:space:]')}"

if [ -z "${VERSION}" ]; then
    echo "emit_version_manifest: VERSION empty (pass as \$2 or set it in project.conf)" >&2
    exit 1
fi

if [ ! -f "${BUILD_DIR}/main.dart.js" ]; then
    echo "emit_version_manifest: ${BUILD_DIR}/main.dart.js missing — run the Flutter web build first" >&2
    exit 1
fi

# Cloudflare/Netlify serve the JSON verbatim; the "+" in the build number is not
# URL-safe as a filename, so the stamped copy uses "-" (0.19.33+273 -> ...33-273).
VERSIONED_MAIN="main.dart.${VERSION//+/-}.js"
cp "${BUILD_DIR}/main.dart.js" "${BUILD_DIR}/${VERSIONED_MAIN}"

# The Flutter-generated HTML and bootstrap otherwise load the mutable
# /main.dart.js URL. Cloudflare Pages gives static assets a four-hour browser
# cache, so a freshly deployed HTML shell can execute the previous release's
# Dart bundle during web-client -> Flutter handoff. Bind both bootstrap copies
# to the immutable filename from this exact release instead. This is stronger
# than response-header tuning and keeps the deployment atomic on every host.
node - "$BUILD_DIR" "$VERSIONED_MAIN" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [buildDir, versionedMain] = process.argv.slice(2);
for (const relative of ['index.html', 'flutter_bootstrap.js']) {
  const file = path.join(buildDir, relative);
  if (!fs.existsSync(file)) {
    throw new Error(`emit_version_manifest: ${file} is missing`);
  }
  const source = fs.readFileSync(file, 'utf8');
  const marker = '"mainJsPath":"main.dart.js"';
  if (!source.includes(marker)) {
    throw new Error(`emit_version_manifest: ${relative} lacks ${marker}`);
  }
  fs.writeFileSync(
    file,
    source.replaceAll(marker, `"mainJsPath":"${versionedMain}"`),
  );
}
NODE

printf '{"version":"%s","main":"%s"}\n' "${VERSION}" "${VERSIONED_MAIN}" > "${BUILD_DIR}/festapp-version.json"

echo "emit_version_manifest: wrote ${BUILD_DIR}/festapp-version.json (${VERSION}) + ${VERSIONED_MAIN}"
