#!/bin/bash
# Canonical direct Cloudflare deploy contract smoke test.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_SH="$PROJECT_ROOT/automation/deploy_direct.sh"
BUILD_SH="$PROJECT_ROOT/automation/cloudflare_build.sh"

fail=0

require_executable() {
    local path="$1"
    if [ -x "$path" ]; then
        echo "  ok: $path is executable"
    else
        echo "  FAIL: $path missing or not executable"
        fail=1
    fi
}

require_text() {
    local path="$1"
    local needle="$2"
    local label="$3"
    if grep -F -q -- "$needle" "$path"; then
        echo "  ok: $label"
    else
        echo "  FAIL: $label"
        fail=1
    fi
}

require_executable "$DEPLOY_SH"
require_executable "$BUILD_SH"

# The deploy script owns the complete release path: canonical build, conf-driven
# project/branch selection, direct upload, and repeated custom-domain verification.
require_text "$DEPLOY_SH" 'bash automation/cloudflare_build.sh' 'deploy invokes the canonical web build'
require_text "$DEPLOY_SH" 'node automation/cloudflare/ensure-pages-project.mjs' 'deploy ensures project, runtime variables, and custom domain'
require_text "$DEPLOY_SH" "^CLOUDFLARE_PROJECT_NAME=" 'deploy reads the Pages project from project.conf'
require_text "$DEPLOY_SH" 'npx --yes wrangler@latest pages deploy build/web' 'deploy uploads build/web with Wrangler'
require_text "$DEPLOY_SH" '--project-name "${PROJECT_NAME}"' 'Wrangler project name is configuration-driven'
require_text "$DEPLOY_SH" '--branch "${BRANCH}"' 'deploy tags the current production branch'
require_text "$DEPLOY_SH" '--branch) BRANCH_OVERRIDE="$2"' 'detached deploy accepts an explicit production branch'
require_text "$DEPLOY_SH" 'detached deploy requires --branch prod/<tenant>' 'detached deploy never guesses branch from a different project name'
require_text "$DEPLOY_SH" '--commit-dirty=true' 'deploy supports a staged pre-commit release candidate'
require_text "$DEPLOY_SH" 'node automation/verify_web_deployment.mjs "https://${DOMAIN}" "${VERSION}"' 'deploy verifies the expected version on the custom domain'
require_text "$DEPLOY_SH" '--wrangler-oauth) USE_WRANGLER_OAUTH=1' 'routine deploy explicitly selects encrypted Wrangler OAuth'
require_text "$DEPLOY_SH" 'unset CLOUDFLARE_API_TOKEN CF_API_TOKEN' 'OAuth cannot be shadowed by an unrelated plaintext token'
require_text "$DEPLOY_SH" 'wrangler@latest pages project list --json' 'OAuth verifies the existing Pages project before upload'
require_text "$DEPLOY_SH" 'domains.includes(`${projectName}.pages.dev`)' 'OAuth requires the canonical Pages hostname'
require_text "$DEPLOY_SH" 'domains.includes(domain)' 'OAuth requires the configured custom domain binding'

# The generated worker remains the single routing owner for every web entry point.
for needle in '/sitemap.xml' '/form/' 'WEB_CLIENT_INDEX' 'FLUTTER_ENTRY' 'AUTH_BRIDGE' 'FORCED_OCCASION_PATH' 'FORCE_OCCASION_LINK' 'get_available_occasions' 'get_occasion_seo_data'; do
    require_text "$BUILD_SH" "$needle" "cloudflare_build.sh worker covers '$needle'"
done

echo
if [ "$fail" -ne 0 ]; then
    echo "❌ direct deploy contract test FAILED"
    exit 1
fi
echo "✅ direct deploy contract test passed"
