#!/usr/bin/env bash
set -euo pipefail

version=2.111.0
archive="supabase_${version}_linux_amd64.tar.gz"
sha256=31ee8a152e9c8c8eddae072c6bc7c9119748a96c8cdaf21a6d31c9ce7e62cc18
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This CI installer requires Linux x86_64.' >&2
  exit 1
fi
directory="${RUNNER_TEMP:?}/festapp-supabase-${version}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
curl --fail --location --silent --show-error --retry 2 --max-time 60 \
  "https://github.com/supabase/cli/releases/download/v${version}/${archive}" -o "$temporary/$archive"
printf '%s  %s\n' "$sha256" "$temporary/$archive" | sha256sum --check --status
tar -xzf "$temporary/$archive" -C "$temporary" supabase
mkdir -p "$directory"
install -m 755 "$temporary/supabase" "$directory/supabase"
installed_version="$("$directory/supabase" --version)"
[[ "$installed_version" == "$version" ]]
printf '%s\n' "$directory" >> "${GITHUB_PATH:?}"
printf 'Supabase CLI %s installed (verified SHA-256)\n' "$version"
