#!/usr/bin/env bash
# Hosted Ubuntu already includes Chrome and its system libraries.
set -euo pipefail
export PATH="${PNPM_HOME:?}/bin:$PATH"
printf '%s\n' "$PNPM_HOME/bin" >> "${GITHUB_PATH:?}"
pnpm add --global --allow-build=agent-browser agent-browser@0.41.2
browser_path="$(command -v google-chrome)"
# agent-browser uses native Chrome discovery; match the local mirror launch.
printf 'CHROME_EXECUTABLE=%s\n' "$browser_path" >> "${GITHUB_ENV:?}"
