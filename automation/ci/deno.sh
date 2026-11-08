#!/usr/bin/env bash
set -euo pipefail

# The official distribution avoids a second dependency on GitHub release assets.
version=2.9.0
archive=deno-x86_64-unknown-linux-gnu.zip
sha256=96c9c73fc05ea57603bc28d8071d41e861bd40bcf2a9f849dd5969ed1a2c8498
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This CI installer requires Linux x86_64.' >&2
  exit 1
fi
directory="${RUNNER_TEMP:?}/festapp-deno-${version}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
curl --fail --location --silent --show-error --retry 2 --max-time 120 \
  "https://dl.deno.land/release/v${version}/${archive}" -o "$temporary/$archive"
printf '%s  %s\n' "$sha256" "$temporary/$archive" | sha256sum --check --status
unzip -q "$temporary/$archive" -d "$temporary"
mkdir -p "$directory"
install -m 755 "$temporary/deno" "$directory/deno"
installed_version="$("$directory/deno" --version)"
[[ "$installed_version" == "deno ${version} "* ]]
printf '%s\n' "$directory" >> "${GITHUB_PATH:?}"
printf 'Deno %s installed (verified SHA-256)\n' "$version"
