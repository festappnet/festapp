#!/bin/bash
# ==============================================================================
# DIRECT CLOUDFLARE PAGES DEPLOY (no git push)
#
# Builds the site locally (automation/cloudflare_build.sh: Flutter web +
# Web Client + _worker.js) and uploads it straight to the Cloudflare Pages
# project via Wrangler. This is the canonical production web deployment path.
#
# Requirements:
#   - CLOUDFLARE_API_TOKEN in the environment, OR pass --env-file <path> to a
#     dotenv file that defines it (e.g. ~/source/roman_seznamka/.env).
#   - CLOUDFLARE_ACCOUNT_ID (defaults to the festapp account below).
#   - Run from a checkout/worktree of the branch you want to deploy. The Pages
#     project name is read from automation/project.conf (CLOUDFLARE_PROJECT_NAME).
#
# The deploy is tagged with --branch = the current git branch so that, when it
# equals the project's production branch (prod/<instance>), Cloudflare promotes
# it to the production custom domain.
# ==============================================================================
set -euo pipefail

ACCOUNT_ID_DEFAULT="84b32318ac235bf6738bdf1c8caa0795"
ENV_FILE=""
SKIP_BUILD=0
BRANCH_OVERRIDE=""
USE_WRANGLER_OAUTH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --branch) BRANCH_OVERRIDE="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --wrangler-oauth) USE_WRANGLER_OAUTH=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Load the CF token from a dotenv file if requested.
if [ -n "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  CLOUDFLARE_API_TOKEN="$(grep -E '^CLOUDFLARE_API_TOKEN=' "$ENV_FILE" | head -1 | sed 's/^CLOUDFLARE_API_TOKEN=//' | tr -d '"'"'"'\r ')"
  export CLOUDFLARE_API_TOKEN
fi

if [ "$USE_WRANGLER_OAUTH" -eq 0 ] && [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "ERROR: CLOUDFLARE_API_TOKEN not set (use --env-file or export it)." >&2
  exit 1
fi
if [ "$USE_WRANGLER_OAUTH" -eq 1 ]; then
  # Do not let an unrelated or expired environment token shadow Wrangler's
  # encrypted OAuth credential from the macOS/Linux credential store.
  unset CLOUDFLARE_API_TOKEN CF_API_TOKEN
fi
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-$ACCOUNT_ID_DEFAULT}"

# Read the target Pages project from project.conf.
# shellcheck disable=SC1091
PROJECT_NAME="$(grep -E '^CLOUDFLARE_PROJECT_NAME=' automation/project.conf | head -1 | sed 's/^CLOUDFLARE_PROJECT_NAME=//' | tr -d '"'"'"'\r ')"
if [ -z "$PROJECT_NAME" ]; then
  echo "ERROR: CLOUDFLARE_PROJECT_NAME missing in automation/project.conf." >&2
  exit 1
fi
DOMAIN="$(grep -E '^DOMAIN=' automation/project.conf | head -1 | sed 's/^DOMAIN=//' | tr -d '"'"'"'\r ')"
VERSION="$(grep -E '^VERSION=' automation/project.conf | head -1 | sed 's/^VERSION=//' | tr -d '"'"'"'\r ')"
if [ -z "$DOMAIN" ] || [ -z "$VERSION" ]; then
  echo "ERROR: DOMAIN and VERSION are required in automation/project.conf." >&2
  exit 1
fi

BRANCH="${BRANCH_OVERRIDE:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)}"
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  echo "ERROR: detached deploy requires --branch prod/<tenant>; project and branch names may differ." >&2
  exit 1
fi
if [[ ! "$BRANCH" =~ ^prod/[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: deploy branch must match prod/<tenant>." >&2
  exit 1
fi

echo "Project: ${PROJECT_NAME} | Branch tag: ${BRANCH} | Account: ${CLOUDFLARE_ACCOUNT_ID}"

# The regular build performs this check; prebuilt uploads need the same gate.
if [ "$SKIP_BUILD" -eq 1 ]; then
  node automation/verify_image_service.mjs
fi

# Export the complete public tenant config for the Pages worker and make the
# project/domain setup identical to the GitHub Actions path.
set -a
# shellcheck disable=SC1091
source automation/project.conf
set +a
export CF_ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID"
export CF_PROJECT="$PROJECT_NAME"
export BRANCH
if [ "$USE_WRANGLER_OAUTH" -eq 1 ]; then
  # OAuth is deliberately a routine-deploy path only. It may update an already
  # bound Pages project, but it must not silently create projects or DNS.
  PROJECTS_JSON="$(pnpm dlx wrangler@latest pages project list --json)"
  node - "$PROJECT_NAME" "$DOMAIN" "$PROJECTS_JSON" <<'NODE'
const [projectName, domain, source] = process.argv.slice(2);
const projects = JSON.parse(source);
const project = projects.find((item) => item['Project Name'] === projectName);
if (!project) throw new Error(`Wrangler OAuth cannot find Pages project ${projectName}`);
const domains = String(project['Project Domains'] || '')
  .split(',').map((value) => value.trim()).filter(Boolean);
if (!domains.includes(`${projectName}.pages.dev`) || !domains.includes(domain)) {
  throw new Error(`Pages project ${projectName} is not bound to ${domain}`);
}
NODE
  echo "Verified existing Pages project and custom domain through Wrangler OAuth."
else
  export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
  node automation/cloudflare/ensure-pages-project.mjs
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "Building (automation/cloudflare_build.sh)..."
  bash automation/cloudflare_build.sh
else
  echo "Skipping build (--skip-build); using existing build/web."
fi

if [ ! -f build/web/_worker.js ]; then
  echo "ERROR: build/web/_worker.js missing — build did not complete." >&2
  exit 1
fi

echo "Deploying build/web to Cloudflare Pages project '${PROJECT_NAME}'..."
pnpm dlx wrangler@latest pages deploy build/web \
  --project-name "${PROJECT_NAME}" \
  --branch "${BRANCH}" \
  --commit-dirty=true

echo "Verifying coherent production release at https://${DOMAIN}..."
node automation/verify_web_deployment.mjs "https://${DOMAIN}" "${VERSION}"
