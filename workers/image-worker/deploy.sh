#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

npm run typecheck
npm test
DRY_RUN_DIR="$(mktemp -d)"
trap 'rm -rf "$DRY_RUN_DIR"' EXIT
npx wrangler deploy --dry-run --outdir "$DRY_RUN_DIR" >/dev/null
echo "image-worker local validation and dry-run passed"

if [[ "${1:-}" != "--deploy-control" ]]; then
  echo "No deployment performed. Use --deploy-control only at an authorized P1 checkpoint."
  exit 0
fi

for required in FESTAPP_IMAGE_DEPLOY_AUTHORITY FESTAPP_IMAGE_ROLLBACK_VERSION FESTAPP_IMAGE_PRESTATE_FILE; do
  if [[ -z "${!required:-}" ]]; then
    echo "Missing P1 checkpoint variable: $required" >&2
    exit 1
  fi
done
if [[ "$FESTAPP_IMAGE_DEPLOY_AUTHORITY" != "approved" ]]; then
  echo "FESTAPP_IMAGE_DEPLOY_AUTHORITY must equal approved" >&2
  exit 1
fi

npx wrangler deploy
