#!/usr/bin/env bash
# Hosted Ubuntu already includes Chrome and its system libraries.
set -euo pipefail
export PATH="${PNPM_HOME:?}/bin:$PATH"
printf '%s\n' "$PNPM_HOME/bin" >> "${GITHUB_PATH:?}"
pnpm add --global --allow-build=agent-browser agent-browser@0.39.4
browser_path="$(command -v google-chrome)"
printf 'AGENT_BROWSER_EXECUTABLE_PATH=%s\n' "$browser_path" >> "${GITHUB_ENV:?}"
