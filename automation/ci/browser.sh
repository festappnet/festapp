#!/usr/bin/env bash
# Hosted Ubuntu images already provide Chrome and its system libraries.
# Keep Playwright's pinned headless shell without reinstalling OS packages.
# Repeating apt here adds an unrelated DNS/mirror dependency to every browser lane.
set -euo pipefail
pnpm --package=playwright@1.65.0 dlx playwright install --only-shell chromium
browser_path="$(command -v google-chrome)"
printf 'CHROME_EXECUTABLE=%s\n' "$browser_path" >> "${GITHUB_ENV:?}"
