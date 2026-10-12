#!/bin/bash
# ==============================================================================
# deploy.yml smoke test
#
# Cheap sanity checks that don't require actionlint to be installed:
#   1. YAML parses (via python).
#   2. Required top-level keys exist (on, jobs).
#   3. Each deploy target has an `if:` so only one branch ever runs.
#   4. The Cloudflare job references the secrets and conf keys we expect.
#   5. The Cloudflare job's wrangler command uses the conf-driven project name.
# ==============================================================================
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW="$PROJECT_ROOT/.github/workflows/deploy.yml"

if [ ! -f "$WORKFLOW" ]; then
    echo "Workflow not found: $WORKFLOW"
    exit 1
fi

if [ -e "$PROJECT_ROOT/.github/workflows/web.yml" ]; then
    echo "Legacy GitHub Pages workflow must not exist"
    exit 1
fi

fail=0

# Every production build must pass the same regressions as main CI.
if ! grep -F -q 'bash automation/test_web_startup.sh' "$PROJECT_ROOT/automation/build_web_bundle.sh"; then
    echo "  FAIL: shared production build is missing WebView regression gate"
    fail=1
fi
if ! grep -F -q 'bash automation/test_web_startup.sh' "$PROJECT_ROOT/.github/workflows/web-startup-regressions.yml"; then
    echo "  FAIL: main CI is missing WebView regressions"
    fail=1
fi

# 1. YAML parse when the optional PyYAML parser is available. The structural
# checks below remain the dependency-free fallback.
if ! command -v python3 >/dev/null 2>&1; then
    echo "  skip: python3 not available, using structural checks"
elif ! python3 -c "import yaml" 2>/dev/null; then
    echo "  skip: PyYAML not available, using structural checks"
elif ! python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        echo "  FAIL: deploy.yml is not valid YAML"
        python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" || true
        fail=1
else
    echo "  ok: deploy.yml parses as YAML"
fi

# 2. Required top-level keys.
for needle in 'on:' 'jobs:' 'tenant-drift:' 'legal-contract:' 'detect:' 'cloudflare:' 'skipped:'; do
    if grep -F -q "$needle" "$WORKFLOW"; then
        echo "  ok: workflow has '$needle'"
    else
        echo "  FAIL: workflow missing '$needle'"
        fail=1
    fi
done

if grep -F -q 'CLOUDFLARE_MANAGE_DNS=false node automation/cloudflare/ensure-pages-project.mjs' "$WORKFLOW"; then
    echo "  ok: project preparation cannot mutate DNS"
else
    echo "  FAIL: project preparation can inherit tenant DNS mutation settings"
    fail=1
fi

# Production builds are release operations, not a side effect of pushing an
# intermediate overlay commit. Keep the GitHub workflow available as an
# explicit fallback, while the canonical deploy_direct.sh path remains usable
# without GitHub Actions.
TRIGGERS=$(awk '
    /^on:$/ { inside=1; next }
    inside && /^[^[:space:]]/ { exit }
    inside { print }
' "$WORKFLOW")
if grep -F -q 'workflow_dispatch:' <<<"$TRIGGERS"; then
    echo "  ok: production deploy supports explicit workflow dispatch"
else
    echo "  FAIL: production deploy must support explicit workflow dispatch"
    fail=1
fi
if grep -Eq '^[[:space:]]+push:' <<<"$TRIGGERS"; then
    echo "  FAIL: production deploy must not run automatically on git push"
    fail=1
else
    echo "  ok: git push does not trigger a production build"
fi

# The config-backed legal pages are a prerequisite of target detection, so a
# production branch cannot silently deploy an SPA fallback at store URLs.
for needle in 'needs: [tenant-drift, legal-contract]' 'render_legal_pages.mjs --validate' 'render_legal_pages.mjs --check'; do
    if grep -F -q "$needle" "$WORKFLOW"; then
        echo "  ok: legal contract contains '$needle'"
    else
        echo "  FAIL: legal contract missing '$needle'"
        fail=1
    fi
done

# 3. Each target job has if:.
for job in cloudflare skipped; do
    # Match `<job>:` block start and look for `if:` within ~10 lines.
    if awk -v job="$job:" '$0 ~ "^  "job {found=1; n=0} found {n++; if($0 ~ "if:") {print "ok"; exit} if(n>15){exit}}' "$WORKFLOW" | grep -q ok; then
        echo "  ok: $job job has if:"
    else
        echo "  FAIL: $job job missing if:"
        fail=1
    fi
done

# 4. Cloudflare job references the right secrets / conf keys. Each production
# tenant must materialize its own private release manifest before the shared
# build preflight runs; one cross-tenant manifest would fail closed.
for needle in \
    'CLOUDFLARE_API_TOKEN' \
    'CLOUDFLARE_ACCOUNT_ID' \
    'CLOUDFLARE_PROJECT_NAME' \
    'FESTAPP_RELEASE_MANIFEST_CSMOSTRAVA2026' \
    'FESTAPP_RELEASE_MANIFEST_HVEZDAMORSKA' \
    'FESTAPP_RELEASE_MANIFEST_CAVFOTOFEST' \
    'FESTAPP_RELEASE_MANIFEST_DOOBISCUP' \
    'FESTAPP_RELEASE_MANIFEST_FARNOSTOPAVA' \
    'FESTAPP_RELEASE_MANIFEST_ABSOLVENTSKYVELEHRAD' \
    'FESTAPP_RELEASE_MANIFEST_FESTAPP' \
    'FESTAPP_RELEASE_MANIFEST_FESTAPPTICKETS' \
    'FESTAPP_RELEASE_MANIFEST_FESTIVALSLUNOVRAT' \
    'FESTAPP_RELEASE_MANIFEST_JUBILEUM2025' \
    'FESTAPP_RELEASE_MANIFEST_AKSMCZ' \
    'Backend activation is disabled; cloud release preflight needs no private manifest.' \
    'FESTAPP_RELEASE_MANIFEST=$RELEASE_MANIFEST_PATH' \
    'ensure-pages-project.mjs'; do
    if grep -F -q "$needle" "$WORKFLOW"; then
        echo "  ok: cloudflare job references '$needle'"
    else
        echo "  FAIL: cloudflare job missing reference to '$needle'"
        fail=1
    fi
done

# 5. Wrangler command uses the conf-driven project name (not a hardcoded slug).
if grep -F -q "pages deploy build/web --project-name=\${{ needs.detect.outputs.cf_project }}" "$WORKFLOW"; then
    echo "  ok: wrangler deploy uses needs.detect.outputs.cf_project"
else
    echo "  FAIL: wrangler deploy must use needs.detect.outputs.cf_project (no hardcoded project name)"
    fail=1
fi

# 6. cloudflare_build.sh exists and is executable — deploy.yml depends on it.
BUILD_SH="$PROJECT_ROOT/automation/cloudflare_build.sh"
if [ -x "$BUILD_SH" ]; then
    echo "  ok: $BUILD_SH is executable"
else
    echo "  FAIL: $BUILD_SH missing or not executable"
    fail=1
fi

# Removed hosting targets must stay unreachable from CI and configuration.
if grep -Eq '^  (netlify|gh-pages):|DEPLOY_TARGET=.*(netlify|gh-pages)|web\.yml' "$WORKFLOW"; then
    echo "  FAIL: a removed Netlify/GitHub Pages build path is still reachable"
    fail=1
else
    echo "  ok: Cloudflare is the only production build target"
fi

# 7. _worker.js heredoc covers sitemap + form OG inject + extension-less entries.
for needle in '/sitemap.xml' '/form/' 'WEB_CLIENT_INDEX' 'FLUTTER_ENTRY' 'AUTH_BRIDGE' 'FORCED_OCCASION_PATH' 'FORCE_OCCASION_LINK' 'get_available_occasions' 'get_occasion_seo_data' 'const WEB_CLIENT_EXACT = new Set(["/"]);' 'const FLUTTER_PREFIXES = ['; do
    if grep -F -q "$needle" "$BUILD_SH"; then
        echo "  ok: cloudflare_build.sh worker covers '$needle'"
    else
        echo "  FAIL: cloudflare_build.sh worker missing '$needle'"
        fail=1
    fi
done

# Social crawlers must always receive a real image asset. Event-specific images
# still come from get_occasion_seo_data; this only validates the no-image
# fallback shared by Cloudflare, Netlify, and the base web-client document.
for social_source in \
    "$BUILD_SH" \
    "$PROJECT_ROOT/netlify/edge-functions/inject-og.js" \
    "$PROJECT_ROOT/web_client/index.html"; do
    if grep -F -q 'android-chrome-512x512.png' "$social_source" &&
        ! grep -F -q '/og_image.jpg' "$social_source"; then
        echo "  ok: $(basename "$social_source") uses a published social-image fallback"
    else
        echo "  FAIL: $(basename "$social_source") references a missing social-image fallback"
        fail=1
    fi
done

# 8. A deploy is not successful until its active origin repeatedly serves one
# coherent HTML/manifest/main/service-worker generation. External-DNS tenants
# prove the Pages origin without pretending the custom hostname has moved.
for needle in \
    'verify_web_deployment.mjs' \
    'CLOUDFLARE_MANAGE_DNS:-true' \
    'VERIFY_ORIGIN="https://${CLOUDFLARE_PROJECT_NAME}.pages.dev"' \
    'PUBLIC_ORIGIN="https://${DOMAIN}"' \
    'VERIFY_ORIGIN="https://${DOMAIN}"'; do
    if grep -F -q "$needle" "$WORKFLOW"; then
        echo "  ok: deploy workflow contains release gate '$needle'"
    else
        echo "  FAIL: deploy workflow missing release gate '$needle'"
        fail=1
    fi
done

# 9. Unified production branches replay main-owned drift/schema policy and the
# tenant identity matrix before any target-specific deploy job can run.
for needle in 'tenant-drift:' 'check_tenant_branch_drift.sh' 'tenant-overlay.schema.json' 'tenant_config_matrix.test.sh'; do
    if grep -F -q "$needle" "$WORKFLOW" "$PROJECT_ROOT/automation/check_tenant_branch_drift.sh"; then
        echo "  ok: tenant gate contains '$needle'"
    else
        echo "  FAIL: tenant gate missing '$needle'"
        fail=1
    fi
done

for branch_mapping in \
    'prod/cavfotofest) TENANT_ID=cavfotofest' \
    'prod/csmostrava2026) TENANT_ID=csmostrava2026' \
    'prod/doobiscup) TENANT_ID=doobiscup' \
    'prod/farnostopava) TENANT_ID=farnostopava' \
    'prod/festapp) TENANT_ID=festapp' \
    'prod/festapptickets) TENANT_ID=festapptickets' \
    'prod/hvezdamorska) TENANT_ID=hvezdamorska' \
    'prod/jubileum2025) TENANT_ID=jubileum2025' \
    'prod/aksmcz) TENANT_ID=aksmcz'; do
    if grep -F -q "$branch_mapping" "$WORKFLOW"; then
        echo "  ok: tenant gate routes '$branch_mapping'"
    else
        echo "  FAIL: tenant gate missing '$branch_mapping'"
        fail=1
    fi
done

if grep -F -q 'aksmcz|cavfotofest|csmostrava2026|doobiscup|farnostopava|festapp|festapptickets|festivalslunovrat|hvezdamorska|jubileum2025' \
    "$PROJECT_ROOT/automation/check_tenant_branch_drift.sh"; then
    echo "  ok: tenant drift checker recognizes the original Festapp tenant"
else
    echo "  FAIL: tenant drift checker does not recognize the original Festapp tenant"
    fail=1
fi

# Migrated Netlify tenants own their legacy-origin retirement boundary as an
# explicit overlay. This keeps redirects and service-worker retirement scoped
# to the matching production branch instead of leaking between tenants.
for tenant in aksmcz cavfotofest doobiscup farnostopava festapptickets festivalslunovrat hvezdamorska jubileum2025; do
    policy="$PROJECT_ROOT/automation/tenant-overlays/$tenant.paths"
    for path in netlify.toml web_client/public/netlify-retire-worker.js; do
        if grep -Fx -q "$path" "$policy"; then
            echo "  ok: $tenant overlay owns '$path'"
        else
            echo "  FAIL: $tenant overlay missing '$path'"
            fail=1
        fi
    done
done

echo
if [ $fail -ne 0 ]; then
    echo "❌ deploy workflow test FAILED"
    exit 1
fi
echo "✅ deploy workflow test passed"
