#!/bin/bash
set -euo pipefail

ENV_FILE=""
BRANCH=""
readonly WRANGLER_VERSION="4.159.0"
ONLY=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file|--branch|--only)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "Missing option value" >&2; exit 2; fi
      case "$1" in
        --env-file) ENV_FILE="$2" ;;
        --branch) BRANCH="$2" ;;
        --only) ONLY="$2" ;;
      esac
      shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown option" >&2; exit 2 ;;
  esac
done
[[ -z "$BRANCH" || "$BRANCH" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]] || { echo "Invalid branch" >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
PROJECTS="$(node --input-type=module - "$ONLY" <<'NODE'
import {readRuntimes} from './automation/lib/measurement_runtimes.mjs';
console.log((await readRuntimes(process.argv[2] || undefined)).map(entry => entry.project).join('\n'));
NODE
)"
PROJECT_ARRAY=()
while IFS= read -r project; do PROJECT_ARRAY+=("$project"); done <<< "$PROJECTS"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Build: node web_client/scripts/build_measurement_worker.mjs (checks generated runtime first)"
  for project in "${PROJECT_ARRAY[@]}"; do
    echo "Deploy: pnpm dlx wrangler@$WRANGLER_VERSION pages deploy workers/form-measurement/dist --project-name=$project --branch=<discovered-production-branch> --commit-hash=<origin/main> (branch assertion: ${BRANCH:-none})"
    echo "Verify: https://$project.pages.dev/runtime.js"
  done
  exit 0
fi

# A lock in the shared git directory also covers other linked worktrees.
LOCK="$(git rev-parse --git-common-dir)/measurement-runtime-deploy.lock"
if ! mkdir "$LOCK" 2>/dev/null; then echo "Runtime deployment already locked: $LOCK" >&2; exit 1; fi
trap 'rmdir "$LOCK"' EXIT
canonical_source() {
  [ "$(git branch --show-current)" = main ] || { echo "Runtime release requires branch main (no detached HEAD or tenant branches)" >&2; return 1; }
  [ -z "$(git status --porcelain --untracked-files=normal)" ] || { echo "Release requires a clean checkout" >&2; return 1; }
}
canonical_source
git fetch origin main
SOURCE_SHA="$(git rev-parse HEAD)"
[ "$SOURCE_SHA" = "$(git rev-parse refs/remotes/origin/main)" ] || { echo "HEAD must equal origin/main" >&2; exit 1; }
release_gate() {
  canonical_source
  [ "$(git rev-parse HEAD)" = "$SOURCE_SHA" ] && [ "$(git rev-parse refs/remotes/origin/main)" = "$SOURCE_SHA" ] || { echo "Canonical source changed during release" >&2; return 1; }
  python3 automation/ci/release_gate.py --source-sha "$SOURCE_SHA"
}
release_gate
if [ -n "$ENV_FILE" ]; then
  # Parse only the named credential; never execute an env file or print its contents.
  CLOUDFLARE_API_TOKEN="$(node automation/lib/measurement_env.mjs "$ENV_FILE")"
  export CLOUDFLARE_API_TOKEN
fi
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "CLOUDFLARE_API_TOKEN required (export it or use --env-file)" >&2; exit 1
fi
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-84b32318ac235bf6738bdf1c8caa0795}"
wrangler() { pnpm dlx "wrangler@$WRANGLER_VERSION" "$@" </dev/null; }
# Discover every target before uploading any artifact.
PROJECTS_JSON="$(wrangler pages project list --json)"
PRODUCTION_BRANCHES=()
for project in "${PROJECT_ARRAY[@]}"; do
  production_branch="$(node --input-type=module - "$project" "$PROJECTS_JSON" <<'NODE'
const entry = JSON.parse(process.argv[3]).find(e => (e['Project Name'] ?? e.name) === process.argv[2]);
if (!entry) { console.error('Pages project missing; provision it manually'); process.exit(1); }
process.stdout.write(entry.production_branch ?? entry['Production Branch'] ?? '');
NODE
)"
  if [ -z "$production_branch" ]; then
    [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || { echo "Production branch unavailable; export CLOUDFLARE_API_TOKEN for Pages project API lookup" >&2; exit 1; }
    project_json="$(curl --silent --show-error --fail --config - "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$project" <<EOF_AUTH | node automation/lib/measurement_project.mjs
header = "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
EOF_AUTH
)"
    production_branch="$(node --input-type=module - "$project_json" <<'NODE'
const data=JSON.parse(process.argv[2]);
if (!data.success || !data.result?.production_branch) { console.error('Project API did not supply production branch'); process.exit(1); }
process.stdout.write(data.result.production_branch);
NODE
)"
  fi
  [[ "$production_branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]] || { echo "Invalid production branch" >&2; exit 1; }
  [ -z "$BRANCH" ] || [ "$BRANCH" = "$production_branch" ] || { echo "--branch does not match production branch for $project" >&2; exit 1; }
  PRODUCTION_BRANCHES+=("$production_branch")
done
node web_client/scripts/build_measurement_worker.mjs
for index in "${!PROJECT_ARRAY[@]}"; do
  project="${PROJECT_ARRAY[$index]}"
  release_gate
  # The active deployment can be older than the first page of history.
  # Resolve its ID from project metadata and verify that deployment directly.
  project_json="$(curl --silent --show-error --fail --config - "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$project" <<EOF_AUTH | node automation/lib/measurement_project.mjs
header = "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
EOF_AUTH
)"
  previous="$(node --input-type=module - "$project_json" <<'NODE'
const project = JSON.parse(process.argv[2]);
const active = project.result?.canonical_deployment;
if (active === null) process.exit(0);
if (!project.success || active?.environment !== 'production' || active?.latest_stage?.status !== 'success' ||
    !/^[a-zA-Z0-9-]+$/.test(active?.id ?? '')) {
  console.error('Current production deployment metadata invalid; stop before upload'); process.exit(1);
}
process.stdout.write(active.id);
NODE
)"
  if [ -n "$previous" ]; then
    curl --silent --show-error --fail --config - "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$project/deployments/$previous" <<EOF_AUTH | node automation/lib/measurement_project.mjs --deployment "$previous"
header = "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
EOF_AUTH
    echo "$project previous production deployment: $previous"
  else
    deployments="$(wrangler pages deployment list --project-name "$project" --environment production --json)"
    node --input-type=module - "$deployments" <<'NODE'
const rows = JSON.parse(process.argv[2]);
if (!Array.isArray(rows) || rows.length !== 0) {
  console.error('No active deployment but production history exists or is invalid; stop before upload'); process.exit(1);
}
NODE
    echo "$project first production deployment: rollback is unavailable (no previous version)"
  fi
  if ! wrangler pages deploy workers/form-measurement/dist --project-name="$project" --branch="${PRODUCTION_BRANCHES[$index]}" --commit-hash="$SOURCE_SHA" ||
     ! node automation/verify_measurement_runtimes.mjs --only "$project"; then
    if [ -n "$previous" ]; then
      echo "Deployment or verification failed for $project. Restore the previous production deployment:" >&2
      printf 'curl --fail-with-body -X POST "https://api.cloudflare.com/client/v4/accounts/%s/pages/projects/%s/deployments/%s/rollback" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"\n' "$CLOUDFLARE_ACCOUNT_ID" "$project" "$previous" >&2
      echo "Requires an API token in env; alternatively select this deployment in the Pages dashboard." >&2
    else
      echo "First deployment or verification failed for $project; rollback is unavailable. Keep measurement disabled, correct the configuration or artifact, then rerun deployment and verification before enabling measurement or releasing the web client." >&2
    fi
    echo "Remaining projects were not uploaded." >&2
    exit 1
  fi
done
