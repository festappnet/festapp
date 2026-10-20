#!/usr/bin/env bash
set -euo pipefail

tenant_id="${1:-}"
[[ "${FESTAPP_NETLIFY_RETIRE_ACK:-}" == "retire-registered-netlify-origin-to-canonical-domain" ]] || {
  echo "ERROR: set FESTAPP_NETLIFY_RETIRE_ACK=retire-registered-netlify-origin-to-canonical-domain" >&2
  exit 1
}
[[ "$tenant_id" =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || {
  echo "ERROR: pass a registered tenant ID" >&2
  exit 1
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
registry="$root/automation/netlify-retirements.json"
site_id="$(jq -er --arg tenant "$tenant_id" '.sites[] | select(.tenant_id == $tenant) | .site_id' "$registry")"
legacy_origin="$(jq -er --arg tenant "$tenant_id" '.sites[] | select(.tenant_id == $tenant) | .legacy_origin' "$registry")"
canonical_origin="$(jq -er --arg tenant "$tenant_id" '.sites[] | select(.tenant_id == $tenant) | .canonical_origin' "$registry")"
work_root="$(mktemp -d "/tmp/festapp-${tenant_id}-netlify-retirement.XXXXXX")"
bundle="$work_root/bundle"

node "$root/automation/build_netlify_retirement.mjs" "$tenant_id" "$bundle" >/dev/null
(
  cd "$bundle"
  npx --yes netlify-cli deploy --site "$site_id" --dir . --prod --no-build \
    --message "Retire $legacy_origin in favor of $canonical_origin"
)

probe="retirement-probe-${tenant_id}"
headers="$(curl -fsSI --max-time 20 "$legacy_origin/$probe?source=legacy")"
grep -Eq '^HTTP/[0-9.]+ 301' <<<"$headers"
grep -Fqi "location: $canonical_origin/$probe?source=legacy" <<<"$headers"
for route in festapp_service_worker.js flutter_service_worker.js push/OneSignalSDKWorker.js; do
  body="$(curl -fsS --max-time 20 "$legacy_origin/$route")"
  grep -Eq 'unregister|caches' <<<"$body"
done

echo "Netlify retirement passed: $legacy_origin -> $canonical_origin (site $site_id)"
