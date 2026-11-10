#!/usr/bin/env bash
# Native browser suites use Playwright's headless shell, never headed Chromium.
set -euo pipefail
pnpm --package=playwright@1.65.0 dlx playwright install --with-deps --only-shell chromium
browser_path="$(command -v google-chrome)"
printf 'CHROME_EXECUTABLE=%s\n' "$browser_path" >> "${GITHUB_ENV:?}"
