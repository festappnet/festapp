#!/usr/bin/env bash
# Install the exact browser build used by the declared Playwright dependency.
set -euo pipefail
pnpm --package=playwright@1.65.0 dlx playwright install --with-deps chromium
browser_path="$(command -v google-chrome)"
printf 'CHROME_EXECUTABLE=%s\n' "$browser_path" >> "${GITHUB_ENV:?}"
