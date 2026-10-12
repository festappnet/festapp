#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/festapp-legal-config.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/automation/release/legal" "$TMP_ROOT/web"
cp "$PROJECT_ROOT/automation/release/render_legal_pages.mjs" "$TMP_ROOT/automation/release/render_legal_pages.mjs"
cp "$PROJECT_ROOT"/automation/release/legal/*.md "$TMP_ROOT/automation/release/legal/"

write_valid_config() {
  cp "$PROJECT_ROOT/automation/tests/fixtures/project.conf" "$TMP_ROOT/automation/project.conf"
}

write_valid_config
node "$TMP_ROOT/automation/release/render_legal_pages.mjs" --validate >/dev/null
node "$TMP_ROOT/automation/release/render_legal_pages.mjs" >/dev/null
node "$TMP_ROOT/automation/release/render_legal_pages.mjs" --check >/dev/null

node --input-type=module - "$TMP_ROOT" <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const root = process.argv[2];
const policy = fs.readFileSync(`${root}/web/privacy/index.html`, 'utf8');
assert.match(policy, /<h2>Kdo odpovídá za vaše údaje<\/h2>/);
assert.match(policy, /href="mailto:info@festapp.net"/);
assert.match(policy, /href="\/privacy\/" data-legal-link aria-current="page"/);
assert.match(policy, /class="app-close"/);
assert.match(policy, /class="theme-toggle"/);
assert.doesNotMatch(policy, /<p>## /);
JS

sed -i.bak '/^TERMS_URL=/d' "$TMP_ROOT/automation/project.conf"
if node "$TMP_ROOT/automation/release/render_legal_pages.mjs" --validate >/dev/null 2>&1; then
  echo "Missing TERMS_URL unexpectedly passed"
  exit 1
fi

write_valid_config
sed -i.bak 's#^SUPPORT_URL=.*#SUPPORT_URL=https://foreign.example/support/#' "$TMP_ROOT/automation/project.conf"
if node "$TMP_ROOT/automation/release/render_legal_pages.mjs" --validate >/dev/null 2>&1; then
  echo "Foreign SUPPORT_URL unexpectedly passed"
  exit 1
fi

write_valid_config
node "$TMP_ROOT/automation/release/render_legal_pages.mjs" >/dev/null
printf '\ncorrupt\n' >> "$TMP_ROOT/web/privacy/index.html"
if node "$TMP_ROOT/automation/release/render_legal_pages.mjs" --check >/dev/null 2>&1; then
  echo "Stale legal output unexpectedly passed"
  exit 1
fi

echo "Required legal configuration tests passed"
