#!/bin/bash
# ==============================================================================
# APPLY CONFIGURATION
# Purpose: Reads configuration from project.conf and applies it to:
#          - web_client/src/app_config.js (Web Client)
#          - lib/app_config.dart (Flutter App)
#          - web_client/index.html (Meta tags)
#          - web/index.html (Flutter web template title + iOS app title)
#          - web/delete-account/index.html (Tenant account deletion page)
#          - web_client/public/CNAME (Domain)
# Usage: ./automation/apply_config.sh
# ==============================================================================
set -e

# Portable in-place sed (GNU on Linux CI, BSD on macOS dev).
if sed --version >/dev/null 2>&1; then
    sed_inplace() { sed -i "$@"; }
else
    sed_inplace() { sed -i '' "$@"; }
fi

# Usage: ./scripts/configure_project.sh [optional_config_path]

# 1. Load Configuration
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CONFIG_FILE="${1:-$PROJECT_ROOT/automation/project.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Source the config (DOMAIN)
source "$CONFIG_FILE"

for required_key in DOMAIN APP_NAME APP_TITLE_SHORT APP_DESCRIPTION VERSION FLUTTER_VERSION \
    ANDROID_APPLICATION_ID IOS_BUNDLE_ID IOS_DEVELOPMENT_TEAM \
    IOS_ONESIGNAL_APP_GROUP IOS_ASSOCIATED_DOMAIN LOGO_ASSET DARK_LOGO_ASSET \
    PROGRAM_LOGO_ASSET WEB_LOADING_LOGO_ASSET WEB_IS_ALL_UNIT \
    WEB_SUPPORTED_LANGUAGES SUPABASE_URL SUPABASE_ANON_KEY ORGANIZATION_ID \
    IS_APP_SUPPORTED WEB_LINK THEME_SEED_1 THEME_SEED_2 THEME_SEED_3 \
    THEME_SEED_4 FONT_FAMILY_BASE FORM_FONT_SCALE IMAGE_API_URL \
    IMAGE_PROJECT_ID PWA_CORE_CACHE_BUDGET_BYTES \
    PWA_KNOWN_CACHE_BUDGET_BYTES PRIVACY_URL PRIVACY_CHOICES_URL TERMS_URL \
    SUPPORT_URL DELETE_ACCOUNT_URL; do
    if [ -z "${!required_key}" ]; then
        echo "Error: $required_key must be defined in $CONFIG_FILE"
        exit 1
    fi
done

LEGAL_RENDERER="$PROJECT_ROOT/automation/release/render_legal_pages.mjs"
if [ ! -f "$LEGAL_RENDERER" ]; then
    echo "Error: required legal page renderer not found at $LEGAL_RENDERER"
    exit 1
fi
node "$LEGAL_RENDERER" --config "$CONFIG_FILE" --validate

case "${DEPLOY_TARGET:-skip}" in cloudflare|skip|'') ;; *)
    echo "Error: DEPLOY_TARGET must be cloudflare or skip"; exit 1 ;;
esac
case "$WEB_IS_ALL_UNIT:$IS_APP_SUPPORTED" in
    true:true|true:false|false:true|false:false) ;;
    *) echo "Error: WEB_IS_ALL_UNIT and IS_APP_SUPPORTED must be true or false"; exit 1 ;;
esac
[[ "$ORGANIZATION_ID" =~ ^[1-9][0-9]*$ ]] || {
    echo "Error: ORGANIZATION_ID must be a positive integer"; exit 1;
}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || {
    echo "Error: VERSION must use semantic-version+build format"; exit 1;
}
[[ "$FLUTTER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Error: FLUTTER_VERSION must use semantic version format"; exit 1;
}

# project.conf is the sole Flutter SDK pin. FVM files are generated adapters
# for local tools and IDEs, never independent version owners.
python3 - "$PROJECT_ROOT" "$FLUTTER_VERSION" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
version = sys.argv[2]
(root / '.fvm').mkdir(exist_ok=True)
(root / '.vscode').mkdir(exist_ok=True)
(root / '.fvmrc').write_text(json.dumps({'flutter': version}, indent=2) + '\n')
(root / '.fvm' / 'fvm_config.json').write_text(
    json.dumps({'flutterSdkVersion': version}, indent=2) + '\n'
)
(root / '.fvm' / 'release').write_text(version + '\n')
settings_path = root / '.vscode' / 'settings.json'
settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
settings['dart.flutterSdkPath'] = f'.fvm/versions/{version}'
settings_path.write_text(json.dumps(settings, indent=2) + '\n')
PY
[[ "$ANDROID_APPLICATION_ID" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]] || {
    echo "Error: invalid ANDROID_APPLICATION_ID"; exit 1;
}
[[ "$IOS_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || {
    echo "Error: invalid IOS_BUNDLE_ID"; exit 1;
}
SUPABASE_ORIGIN="$(node "$PROJECT_ROOT/automation/lib/supabase_client_config.mjs" origin "$SUPABASE_URL")" || {
    echo "Error: SUPABASE_URL must be an HTTPS origin without credentials, path, query, or fragment"; exit 1;
}
CONFIGURED_AUTH_STORAGE_KEY="$(sed -n 's/^SUPABASE_AUTH_STORAGE_KEY=//p' "$CONFIG_FILE" | tail -1 | tr -d '\r')"
CONFIGURED_AUTH_STORAGE_KEY="${CONFIGURED_AUTH_STORAGE_KEY#\"}"
CONFIGURED_AUTH_STORAGE_KEY="${CONFIGURED_AUTH_STORAGE_KEY%\"}"
CONFIGURED_AUTH_STORAGE_KEY="${CONFIGURED_AUTH_STORAGE_KEY#\'}"
CONFIGURED_AUTH_STORAGE_KEY="${CONFIGURED_AUTH_STORAGE_KEY%\'}"
SUPABASE_AUTH_STORAGE_KEY="$(node "$PROJECT_ROOT/automation/lib/supabase_client_config.mjs" auth-key \
    "$SUPABASE_ORIGIN" "$CONFIGURED_AUTH_STORAGE_KEY")" || exit 1
BACKEND_ACTIVATION_TENANT_ID="${BACKEND_ACTIVATION_TENANT_ID:-}"
BACKEND_ACTIVATION_PHASE="${BACKEND_ACTIVATION_PHASE:-}"
BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL="${BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL:-}"
BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY="${BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY:-}"
BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID="${BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID:-}"
BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256=""
if [ -n "$BACKEND_ACTIVATION_TENANT_ID$BACKEND_ACTIVATION_PHASE$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL$BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY$BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID" ]; then
    [ -n "$BACKEND_ACTIVATION_TENANT_ID" ] && [ -n "$BACKEND_ACTIVATION_PHASE" ] && \
        [ -n "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL" ] && \
        [ -n "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY" ] && \
        [ -n "$BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID" ] || {
        echo "Error: backend activation configuration must be complete"; exit 1;
    }
    [[ "$BACKEND_ACTIVATION_TENANT_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
        echo "Error: BACKEND_ACTIVATION_TENANT_ID must be a lowercase slug"; exit 1;
    }
    case "$BACKEND_ACTIVATION_PHASE" in legacy|canonical) ;; *)
        echo "Error: BACKEND_ACTIVATION_PHASE must be legacy or canonical"; exit 1 ;;
    esac
    [[ "$BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID" =~ ^[1-9][0-9]*$ ]] || {
        echo "Error: BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID must be a positive integer"; exit 1;
    }
    BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL="$(node \
        "$PROJECT_ROOT/automation/lib/supabase_client_config.mjs" origin \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL")" || exit 1
    [ "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL" != "$SUPABASE_ORIGIN" ] || {
        echo "Error: backend activation canonical origin must differ from the legacy origin"; exit 1;
    }
    BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256="$(node \
        "$PROJECT_ROOT/automation/release/generate_backend_profile_fingerprint.mjs" \
        "$BACKEND_ACTIVATION_TENANT_ID" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY" \
        "$BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID")" || exit 1
fi
BACKEND_ACTIVATION_MANIFEST_URL="${WEB_LINK%/}/backend-activation.json"
BACKEND_ACTIVATION_CANONICAL_MANIFEST_SHA256="$(node \
    "$PROJECT_ROOT/automation/release/generate_backend_activation_manifest.mjs" \
    "$BACKEND_ACTIVATION_TENANT_ID" "$BACKEND_ACTIVATION_PHASE" \
    "$PROJECT_ROOT/web/backend-activation.json" \
    "$PROJECT_ROOT/web_client/public/backend-activation.json")"
if [ "$BACKEND_ACTIVATION_CANONICAL_MANIFEST_SHA256" = disabled ]; then
    BACKEND_ACTIVATION_CANONICAL_MANIFEST_SHA256=""
    BACKEND_ACTIVATION_MANIFEST_URL=""
fi
[[ "$WEB_LINK" =~ ^https?://[^[:space:]]+$ ]] || {
    echo "Error: WEB_LINK must be an absolute HTTP(S) URL"; exit 1;
}
for color_key in THEME_SEED_1 THEME_SEED_2 THEME_SEED_3 THEME_SEED_4; do
    [[ "${!color_key}" =~ ^#[0-9A-Fa-f]{6}$ ]] || {
        echo "Error: $color_key must use #RRGGBB format"; exit 1;
    }
done
[[ "$FORM_FONT_SCALE" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    echo "Error: FORM_FONT_SCALE must be numeric"; exit 1;
}
for budget_key in PWA_CORE_CACHE_BUDGET_BYTES PWA_KNOWN_CACHE_BUDGET_BYTES; do
    if ! [[ "${!budget_key}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: $budget_key must be a positive integer"; exit 1
    fi
done
for asset_path in "$LOGO_ASSET" "$DARK_LOGO_ASSET" "$PROGRAM_LOGO_ASSET"; do
    [ -f "$PROJECT_ROOT/$asset_path" ] || {
        echo "Error: configured asset does not exist: $asset_path"; exit 1;
    }
done
[ -f "$PROJECT_ROOT/web/$WEB_LOADING_LOGO_ASSET" ] || {
    echo "Error: configured web loading asset does not exist: $WEB_LOADING_LOGO_ASSET"; exit 1;
}
SOURCE_REGISTRY="$PROJECT_ROOT/automation/hetzner-supabase/merge/source-registry.json"
if ! jq -e --arg source "$IMAGE_PROJECT_ID" '.sources | any(.alias == $source)' "$SOURCE_REGISTRY" >/dev/null; then
    echo "Error: IMAGE_PROJECT_ID must be a registered canonical migration source alias"
    exit 1
fi
if ! printf '%s' "$IMAGE_API_URL" | grep -Eq '^https://[^/]+$'; then
    echo "Error: IMAGE_API_URL must be an https origin without a path"
    exit 1
fi

echo "Detailed Configuration:"
echo "  - Domain: $DOMAIN"
echo "  - Supabase URL: $SUPABASE_URL"
echo "  - Organization ID: $ORGANIZATION_ID"
echo "  - Android application ID: $ANDROID_APPLICATION_ID"
echo "  - iOS bundle ID: $IOS_BUNDLE_ID"



# 2. Update index.html meta tags (Domain)
INDEX_FILE="$PROJECT_ROOT/web_client/index.html"
if [ -f "$INDEX_FILE" ]; then
    echo "Updating $INDEX_FILE..."
    # Replace content="https://<anything>/" with content="https://$DOMAIN/" in meta tags
    sed_inplace "s|content=\"https://[^/]*|content=\"https://$DOMAIN|g" "$INDEX_FILE"
    # The web-client shell is also the server-rendered document seen by social
    # crawlers before a forced-occasion tenant hands off to Flutter. Keep its
    # title and descriptions tenant-owned instead of leaking the generic
    # vstupenky.online branding into every production application.
    python3 - "$INDEX_FILE" "$APP_NAME" "$APP_DESCRIPTION" "$DOMAIN" <<'PY'
import html
import re
import sys

path, app_name, app_description, domain = sys.argv[1:]
source = open(path, encoding="utf-8").read()
title = html.escape(app_name, quote=True)
description = html.escape(app_description, quote=True)
origin = f"https://{domain}"
source = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", source, count=1, flags=re.DOTALL)

def replace_meta(attribute, key, value):
    global source
    pattern = re.compile(
        rf'(<meta\s+[^>]*{attribute}=["\']{re.escape(key)}["\'][^>]*content=["\'])(.*?)(["\'][^>]*>)',
        re.IGNORECASE,
    )
    source, count = pattern.subn(lambda match: match.group(1) + value + match.group(3), source, count=1)
    if count != 1:
        raise SystemExit(f"missing {attribute}={key} metadata in {path}")

replace_meta("name", "description", description)
for property_name, value in (
    ("og:url", origin + "/"),
    ("og:title", title),
    ("og:description", description),
    ("twitter:url", origin + "/"),
    ("twitter:title", title),
    ("twitter:description", description),
):
    replace_meta("property", property_name, value)

# This is the one WebSite name in the static JSON-LD template. URLs were
# already rewritten above by the canonical DOMAIN propagation.
source, count = re.subn(
    r'("@type"\s*:\s*"WebSite"\s*,\s*"name"\s*:\s*)"[^"]*"',
    lambda match: match.group(1) + __import__("json").dumps(app_name, ensure_ascii=False),
    source,
    count=1,
)
if count != 1:
    raise SystemExit(f"missing WebSite JSON-LD name in {path}")
source, count = re.subn(
    r'("url"\s*:\s*)"[^"]*"',
    lambda match: match.group(1) + __import__("json").dumps(origin + "/"),
    source,
    count=1,
)
if count != 1:
    raise SystemExit(f"missing WebSite JSON-LD URL in {path}")
source, count = re.subn(
    r'("target"\s*:\s*)"[^"]*"',
    lambda match: match.group(1) + __import__("json").dumps(origin + "/?q={search_term_string}"),
    source,
    count=1,
)
if count != 1:
    raise SystemExit(f"missing WebSite JSON-LD search target in {path}")
source, count = re.subn(
    r'(<link\s+[^>]*rel=["\']canonical["\'][^>]*href=["\'])[^"\']*(["\'][^>]*>)',
    lambda match: match.group(1) + origin + "/" + match.group(2),
    source,
    count=1,
    flags=re.IGNORECASE,
)
if count != 1:
    raise SystemExit(f"missing canonical link in {path}")
open(path, "w", encoding="utf-8").write(source)
PY
    echo "✔ Updated meta tags"
else
    echo "Warning: $INDEX_FILE not found."
fi

# 2b. Update Flutter web template (web/index.html): <title> and the
#     iOS apple-mobile-web-app-title meta tag. Two app-title metas may exist;
#     only the second (override, self-closing /> variant) is rewritten so the
#     upstream Flutter default stays put.
FLUTTER_INDEX="$PROJECT_ROOT/web/index.html"
if [ -f "$FLUTTER_INDEX" ]; then
    if [ ! -z "$APP_NAME" ]; then
        echo "Updating $FLUTTER_INDEX title to '$APP_NAME'..."
        sed_inplace "s|<title>.*</title>|<title>$APP_NAME</title>|" "$FLUTTER_INDEX"
    fi
    if [ ! -z "$APP_TITLE_SHORT" ]; then
        # Match both `<meta ... content="X">` and `<meta ... content="X" />`.
        sed_inplace "s|<meta name=\"apple-mobile-web-app-title\" content=\"[^\"]*\"[[:space:]]*/\{0,1\}>|<meta name=\"apple-mobile-web-app-title\" content=\"$APP_TITLE_SHORT\">|g" "$FLUTTER_INDEX"
    fi
    python3 - "$FLUTTER_INDEX" "${ONESIGNAL_WEB_APP_ID:-}" \
        "${ONESIGNAL_SAFARI_WEB_ID:-}" "${PUSH_APP_GENERATION:-}" \
        "${FORCE_OCCASION_LINK:-}" <<'PY'
import re
import sys

path, app_id, safari_id, generation, occasion = sys.argv[1:]
source = open(path, encoding="utf-8").read()
source, count = re.subn(
    r'const oneSignalWebAppId = "[^"]*";',
    f'const oneSignalWebAppId = "{app_id}";',
    source,
    count=1,
)
if count != 1:
    raise SystemExit(f"missing OneSignal web app ID constant in {path}")
source = re.sub(r'safari_web_id: "[^"]*"', f'safari_web_id: "{safari_id}"', source)
source = re.sub(r"app_generation: '[^']*'", f"app_generation: '{generation}'", source)
source = re.sub(r"occasion: '[^']*'", f"occasion: '{occasion}'", source)
open(path, "w", encoding="utf-8").write(source)
PY
    sed_inplace "s|<img class=\"initial-logo\" src=\"[^\"]*\"|<img class=\"initial-logo\" src=\"$WEB_LOADING_LOGO_ASSET\"|" "$FLUTTER_INDEX"
    echo "✔ Updated web/index.html"
else
    echo "Warning: $FLUTTER_INDEX not found."
fi

# 2c. Generate the public account-deletion page from tenant configuration.
# The anon key is intentionally a public client credential; privileged access
# remains enforced by the Edge Function and database authorization boundaries.
DELETE_ACCOUNT_TEMPLATE="$PROJECT_ROOT/automation/templates/web/delete-account/index.html"
DELETE_ACCOUNT_FILE="$PROJECT_ROOT/web/delete-account/index.html"
if [ ! -f "$DELETE_ACCOUNT_TEMPLATE" ]; then
    echo "Error: account deletion template not found at $DELETE_ACCOUNT_TEMPLATE"
    exit 1
fi
mkdir -p "$(dirname "$DELETE_ACCOUNT_FILE")"
python3 - "$DELETE_ACCOUNT_TEMPLATE" "$DELETE_ACCOUNT_FILE" "$APP_NAME" \
    "$SUPABASE_URL" "$SUPABASE_ANON_KEY" <<'PY'
import html
import json
import sys

template_path, output_path, app_name, supabase_url, anon_key = sys.argv[1:]
source = open(template_path, encoding="utf-8").read()
replacements = {
    "__FESTAPP_APP_NAME_HTML__": html.escape(app_name),
    "__FESTAPP_DELETE_ENDPOINT__": json.dumps(
        supabase_url.rstrip("/") + "/functions/v1/confirm-account-deletion"
    ),
    "__FESTAPP_ANON_KEY__": json.dumps(anon_key),
}
for token, value in replacements.items():
    if token not in source:
        raise SystemExit(f"Error: missing account deletion template token: {token}")
    source = source.replace(token, value)
if "__FESTAPP_" in source:
    raise SystemExit("Error: unresolved account deletion template token")
open(output_path, "w", encoding="utf-8").write(source.rstrip() + "\n")
PY
echo "✔ Generated account deletion page"

# 3. Update CNAME file (Domain)
# Generate the installable PWA identity from the same brand source.
for PWA_MANIFEST in "$PROJECT_ROOT/web/site.webmanifest" "$PROJECT_ROOT/web_client/public/site.webmanifest"; do
    if [ -f "$PWA_MANIFEST" ] && [ -n "$APP_NAME" ] && [ -n "$APP_DESCRIPTION" ]; then
        node -e 'const fs=require("fs");const p=process.argv[1];const m=JSON.parse(fs.readFileSync(p,"utf8"));const slug=process.argv[5].replace(/^\/+|\/+$/g,"");const start=slug?"/"+slug+"/event":"/";m.name=process.argv[2];m.short_name=process.argv[3];m.description=process.argv[4];m.id="/";m.start_url=start;m.scope="/";fs.writeFileSync(p,JSON.stringify(m,null,2)+"\n")' "$PWA_MANIFEST" "$APP_NAME" "$APP_TITLE_SHORT" "$APP_DESCRIPTION" "$FORCE_OCCASION_LINK"
        echo "✔ Updated PWA manifest: $PWA_MANIFEST"
    fi
done

# 3. Update CNAME file (Domain)
CNAME_FILE="$PROJECT_ROOT/web_client/public/CNAME"
mkdir -p "$(dirname "$CNAME_FILE")"
echo "$DOMAIN" > "$CNAME_FILE"
echo "✔ Updated CNAME"


# 4. Update app_config.js (Entry Point)
APP_CONFIG="$PROJECT_ROOT/web_client/src/app_config.js"
if [ -f "$APP_CONFIG" ]; then
    echo "Updating $APP_CONFIG..."

    sed_inplace "s|static appName = '.*';|static appName = '$APP_NAME';|g" "$APP_CONFIG"
    sed_inplace "s|static appTitleShort = '.*';|static appTitleShort = '$APP_TITLE_SHORT';|g" "$APP_CONFIG"

    # Update Supabase URL
    if [ ! -z "$SUPABASE_URL" ]; then
        sed_inplace "s|static supabaseUrl = '.*';|static supabaseUrl = '$SUPABASE_URL';|g" "$APP_CONFIG"

        sed_inplace "s|auth: 'sb-[^']*-auth-token'|auth: '$SUPABASE_AUTH_STORAGE_KEY'|g" "$APP_CONFIG"

        AUTH_BRIDGE="$PROJECT_ROOT/web_client/public/auth_bridge.html"
        if [ -f "$AUTH_BRIDGE" ]; then
            sed_inplace "s|const SUPABASE_KEY = 'sb-[^']*-auth-token';|const SUPABASE_KEY = '$SUPABASE_AUTH_STORAGE_KEY';|g" "$AUTH_BRIDGE"
        fi
    fi
    
    # Update Anon Key
    if [ ! -z "$SUPABASE_ANON_KEY" ]; then
        sed_inplace "s|static anonKey = '.*';|static anonKey = '$SUPABASE_ANON_KEY';|g" "$APP_CONFIG"
    fi

    python3 - "$APP_CONFIG" "$BACKEND_ACTIVATION_TENANT_ID" \
        "$BACKEND_ACTIVATION_MANIFEST_URL" \
        "$BACKEND_ACTIVATION_CANONICAL_MANIFEST_SHA256" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY" \
        "$BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
names = [
    "backendActivationTenantId", "backendActivationManifestUrl",
    "backendActivationCanonicalManifestSha256",
    "backendActivationCanonicalSupabaseUrl", "backendActivationCanonicalAnonKey",
    "backendActivationCanonicalProfileSha256",
]
source = path.read_text(encoding="utf-8")
for name, value in zip(names, sys.argv[2:]):
    source, count = re.subn(
        rf"static {name} = '[^']*';", f"static {name} = '{value}';", source, count=1
    )
    if count != 1:
        raise SystemExit(f"Could not update web {name}")
path.write_text(source, encoding="utf-8")
PY
    sed_inplace "s|static backendActivationCanonicalOrganizationId = .*;|static backendActivationCanonicalOrganizationId = ${BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID:-0};|g" "$APP_CONFIG"

    # Update Organization
    if [ ! -z "$ORGANIZATION_ID" ]; then
        sed_inplace "s|static organization = .*;|static organization = $ORGANIZATION_ID;|g" "$APP_CONFIG"
    fi
    
    # Update Flutter App URL
    if [ ! -z "${FLUTTER_APP_URL+x}" ]; then
         sed_inplace "s|static flutterAppUrl = '.*';|static flutterAppUrl = '$FLUTTER_APP_URL';|g" "$APP_CONFIG"
    fi

    # Update Is App Supported
    if [ ! -z "$IS_APP_SUPPORTED" ]; then
        sed_inplace "s|static isAppSupported = .*;|static isAppSupported = $IS_APP_SUPPORTED;|g" "$APP_CONFIG"
    fi

    # Update tenant-specific web behavior from the canonical configuration.
    python3 - "$APP_CONFIG" "$WEB_IS_ALL_UNIT" "$WEB_SUPPORTED_LANGUAGES" <<'PY'
import re
import sys

path, is_all_unit, supported_languages = sys.argv[1:]
if is_all_unit not in {"true", "false"}:
    raise SystemExit("WEB_IS_ALL_UNIT must be true or false")
languages = supported_languages.split(",")
if not languages or any(not re.fullmatch(r"[a-z]{2}", language) for language in languages):
    raise SystemExit("WEB_SUPPORTED_LANGUAGES must be comma-separated ISO 639-1 codes")
source = open(path, encoding="utf-8").read()
source = re.sub(r"static isAllUnit = .*;", f"static isAllUnit = {is_all_unit};", source)
language_list = ", ".join(repr(language) for language in languages)
source = re.sub(r"static supportedLanguages = .*;", f"static supportedLanguages = [{language_list}];", source)
open(path, "w", encoding="utf-8").write(source)
PY

    # Update Web Link
    if [ ! -z "$WEB_LINK" ]; then
        sed_inplace "s|static webLink = \".*\";|static webLink = \"$WEB_LINK\";|g" "$APP_CONFIG"
    fi
    sed_inplace "s|static privacyUrl = \".*\";|static privacyUrl = \"$PRIVACY_URL\";|g" "$APP_CONFIG"
    sed_inplace "s|static privacyChoicesUrl = \".*\";|static privacyChoicesUrl = \"$PRIVACY_CHOICES_URL\";|g" "$APP_CONFIG"
    sed_inplace "s|static termsUrl = \".*\";|static termsUrl = \"$TERMS_URL\";|g" "$APP_CONFIG"
    sed_inplace "s|static supportUrl = \".*\";|static supportUrl = \"$SUPPORT_URL\";|g" "$APP_CONFIG"
    sed_inplace "s|static deleteAccountUrl = \".*\";|static deleteAccountUrl = \"$DELETE_ACCOUNT_URL\";|g" "$APP_CONFIG"
    sed_inplace "s|static imageApiUrl = '.*';|static imageApiUrl = '$IMAGE_API_URL';|g" "$APP_CONFIG"
    sed_inplace "s|static imageProjectId = '.*';|static imageProjectId = '$IMAGE_PROJECT_ID';|g" "$APP_CONFIG"

    # Update Force Occasion Link (empty value -> null)
    if [ -z "$FORCE_OCCASION_LINK" ]; then
        sed_inplace "s|static forceOccasionLink = .*;|static forceOccasionLink = null;|g" "$APP_CONFIG"
    else
        sed_inplace "s|static forceOccasionLink = .*;|static forceOccasionLink = \"$FORCE_OCCASION_LINK\";|g" "$APP_CONFIG"
    fi

    echo "✔ Updated app_config.js (tenant identity, behavior, and endpoints)"
else
    echo "Warning: $APP_CONFIG not found."
fi



# 5. Update lib/app_config.dart (Flutter App)
FLUTTER_CONFIG="$PROJECT_ROOT/lib/app_config.dart"
if [ -f "$FLUTTER_CONFIG" ]; then
    echo "Updating $FLUTTER_CONFIG..."

    # Update Supabase URL
    if [ ! -z "$SUPABASE_URL" ]; then
        sed_inplace "s|static const String supabaseUrl = '.*';|static const String supabaseUrl = '$SUPABASE_URL';|g" "$FLUTTER_CONFIG"
    fi

    # Update Anon Key. Keep this multiline-safe because dart format wraps the
    # long JWT after `=`; a line-based sed silently left the previous tenant's
    # key in production.
    if [ ! -z "$SUPABASE_ANON_KEY" ]; then
        python3 - "$FLUTTER_CONFIG" "$SUPABASE_ANON_KEY" <<'PY'
import pathlib
import re
import sys

path, anon_key = sys.argv[1:]
source = pathlib.Path(path).read_text(encoding="utf-8")
source, count = re.subn(
    r"static const String anonKey\s*=\s*'[^']*';",
    f"static const String anonKey = '{anon_key}';",
    source,
    count=1,
)
if count != 1:
    raise SystemExit("Could not update Flutter anonKey")
pathlib.Path(path).write_text(source, encoding="utf-8")
PY
    fi

    python3 - "$FLUTTER_CONFIG" "$SUPABASE_AUTH_STORAGE_KEY" \
        "$BACKEND_ACTIVATION_TENANT_ID" "$BACKEND_ACTIVATION_MANIFEST_URL" \
        "$BACKEND_ACTIVATION_CANONICAL_MANIFEST_SHA256" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL" \
        "$BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY" \
        "$BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
names = [
    "supabaseAuthStorageKey", "backendActivationTenantId",
    "backendActivationManifestUrl", "backendActivationCanonicalManifestSha256",
    "backendActivationCanonicalSupabaseUrl", "backendActivationCanonicalAnonKey",
    "backendActivationCanonicalProfileSha256",
]
source = path.read_text(encoding="utf-8")
for name, value in zip(names, sys.argv[2:]):
    source, count = re.subn(
        rf"static const String {name}\s*=\s*'[^']*';",
        f"static const String {name} = '{value}';", source, count=1,
    )
    if count != 1:
        raise SystemExit(f"Could not update Flutter {name}")
path.write_text(source, encoding="utf-8")
PY
    sed_inplace "s|static const int backendActivationCanonicalOrganizationId = .*;|static const int backendActivationCanonicalOrganizationId = ${BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID:-0};|g" "$FLUTTER_CONFIG"

    # Update App Name (used as the app title / OccasionHomePage.homePageTitle)
    if [ ! -z "$APP_NAME" ]; then
        sed_inplace "s|static const String appName = '.*';|static const String appName = '$APP_NAME';|g" "$FLUTTER_CONFIG"
    fi

    sed_inplace "s|static const String oneSignalAppId = '.*';|static const String oneSignalAppId = '${ONESIGNAL_NATIVE_APP_ID:-}';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String oneSignalWebAppId = '.*';|static const String oneSignalWebAppId = '${ONESIGNAL_WEB_APP_ID:-}';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String pushAppGeneration = '.*';|static const String pushAppGeneration = '${PUSH_APP_GENERATION:-}';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String logoAsset = '.*';|static const String logoAsset = '$LOGO_ASSET';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String darkLogoAsset = '.*';|static const String darkLogoAsset = '$DARK_LOGO_ASSET';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String programLogoAsset = '.*';|static const String programLogoAsset = '$PROGRAM_LOGO_ASSET';|g" "$FLUTTER_CONFIG"

    # Update Organization
    if [ ! -z "$ORGANIZATION_ID" ]; then
        sed_inplace "s|static int organization = .*;|static int organization = $ORGANIZATION_ID;|g" "$FLUTTER_CONFIG"
    fi

    # Update Is App Supported
    if [ ! -z "$IS_APP_SUPPORTED" ]; then
        sed_inplace "s|static const bool isAppSupported = .*;|static const bool isAppSupported = $IS_APP_SUPPORTED;|g" "$FLUTTER_CONFIG"
    fi

    # Keep Flutter's unit-level startup mode on the same canonical tenant flag
    # as the web client. Missing this propagation makes an all-unit deployment
    # query an occasion from the bare host and render a blank application.
    sed_inplace "s|static const bool isAllUnit = .*;|static const bool isAllUnit = $WEB_IS_ALL_UNIT;|g" "$FLUTTER_CONFIG"

    # Update Web Link
    if [ ! -z "$WEB_LINK" ]; then
        sed_inplace "s|static const String webLink = \".*\";|static const String webLink = \"$WEB_LINK\";|g" "$FLUTTER_CONFIG"
    fi
    python3 - "$FLUTTER_CONFIG" "$PRIVACY_URL" "$PRIVACY_CHOICES_URL" \
        "$TERMS_URL" "$SUPPORT_URL" "$DELETE_ACCOUNT_URL" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
values = dict(zip(
    ["privacyUrl", "privacyChoicesUrl", "termsUrl", "supportUrl", "deleteAccountUrl"],
    sys.argv[2:],
))
source = path.read_text(encoding="utf-8")
for name, value in values.items():
    source, count = re.subn(
        rf"static const String {name}\s*=\s*\"[^\"]*\";",
        f'static const String {name} = "{value}";',
        source,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"Could not update Flutter {name}")
path.write_text(source, encoding="utf-8")
PY

    sed_inplace "s|static const String syncHeadOrigin = \".*\";|static const String syncHeadOrigin = \"${SYNC_HEAD_ORIGIN:-}\";|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String syncAssetOrigin = \".*\";|static const String syncAssetOrigin = \"${SYNC_ASSET_ORIGIN:-}\";|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String imageApiUrl = '.*';|static const String imageApiUrl = '$IMAGE_API_URL';|g" "$FLUTTER_CONFIG"
    sed_inplace "s|static const String imageProjectId = '.*';|static const String imageProjectId = '$IMAGE_PROJECT_ID';|g" "$FLUTTER_CONFIG"

    # Update Force Occasion Link (empty value -> null)
    if [ -z "$FORCE_OCCASION_LINK" ]; then
        sed_inplace "s|static const String? forceOccasionLink = .*;|static const String? forceOccasionLink = null;|g" "$FLUTTER_CONFIG"
    else
        sed_inplace "s|static const String? forceOccasionLink = .*;|static const String? forceOccasionLink = \"$FORCE_OCCASION_LINK\";|g" "$FLUTTER_CONFIG"
    fi

    echo "✔ Updated lib/app_config.dart"
else
    echo "Warning: $FLUTTER_CONFIG not found."
fi

# 5a. Generate native tenant identity from project.conf. Source paths are
# deliberately stable; Java/Kotlin packages do not need to mirror directories.
ANDROID_GRADLE="$PROJECT_ROOT/android/app/build.gradle"
ANDROID_MANIFEST="$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml"
IOS_PROJECT_FILE="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj"
python3 - "$ANDROID_GRADLE" "$ANDROID_MANIFEST" "$PROJECT_ROOT/android/app/src/main/kotlin" \
    "$IOS_PROJECT_FILE" "$ANDROID_APPLICATION_ID" "$IOS_BUNDLE_ID" \
    "$IOS_DEVELOPMENT_TEAM" "${IOS_PROVISIONING_PROFILE:-}" \
    "${IOS_ONESIGNAL_PROVISIONING_PROFILE:-}" "$APP_NAME" <<'PY'
import pathlib
import re
import sys

(gradle_path, manifest_path, kotlin_root, pbx_path, android_id, ios_id,
 team_id, app_profile, extension_profile, app_name) = sys.argv[1:]

gradle = pathlib.Path(gradle_path)
if gradle.exists():
    source = gradle.read_text(encoding="utf-8")
    source = re.sub(r'namespace = "[^"]+"', f'namespace = "{android_id}"', source)
    source = re.sub(r'applicationId = "[^"]+"', f'applicationId = "{android_id}"', source)
    gradle.write_text(source, encoding="utf-8")

manifest = pathlib.Path(manifest_path)
if manifest.exists():
    source = manifest.read_text(encoding="utf-8")
    source = re.sub(r'android:label="[^"]*"', f'android:label="{app_name}"', source, count=1)
    manifest.write_text(source, encoding="utf-8")

for activity in pathlib.Path(kotlin_root).glob("**/MainActivity.kt"):
    source = activity.read_text(encoding="utf-8")
    source = re.sub(r'^package\s+\S+', f'package {android_id}', source, count=1, flags=re.M)
    activity.write_text(source, encoding="utf-8")

pbx = pathlib.Path(pbx_path)
if pbx.exists():
    source = pbx.read_text(encoding="utf-8")
    source = re.sub(r'DEVELOPMENT_TEAM = [^;]+;', f'DEVELOPMENT_TEAM = {team_id};', source)
    source = re.sub(r'INFOPLIST_KEY_CFBundleDisplayName = (?:"[^"]*"|[^;]+);',
                    f'INFOPLIST_KEY_CFBundleDisplayName = "{app_name}";', source)

    def identity(match):
        value = match.group(1)
        if value.endswith('.RunnerTests'):
            return match.group(0)
        if value.endswith('.OneSignalNotificationServiceExtension'):
            return f'PRODUCT_BUNDLE_IDENTIFIER = {ios_id}.OneSignalNotificationServiceExtension;'
        return f'PRODUCT_BUNDLE_IDENTIFIER = {ios_id};'

    source = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', identity, source)

    def signing(block_match):
        block = block_match.group(0)
        is_extension = f'{ios_id}.OneSignalNotificationServiceExtension;' in block
        is_app = f'PRODUCT_BUNDLE_IDENTIFIER = {ios_id};' in block
        if not (is_extension or is_app):
            return block
        profile = extension_profile if is_extension else app_profile
        block = re.sub(r'^\s*PROVISIONING_PROFILE_SPECIFIER = .*\n', '', block, flags=re.M)
        if profile:
            block = re.sub(r'CODE_SIGN_STYLE = \w+;', 'CODE_SIGN_STYLE = Manual;', block)
            line = f'\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile}";'
            block = re.sub(r'(PRODUCT_BUNDLE_IDENTIFIER = [^;]+;)', r'\1' + line, block, count=1)
        else:
            block = re.sub(r'CODE_SIGN_STYLE = Manual;', 'CODE_SIGN_STYLE = Automatic;', block)
            block = re.sub(r'^\s*"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = .*\n', '', block, flags=re.M)
        return block

    source = re.sub(r'buildSettings = \{[\s\S]*?\n\s*\};', signing, source)
    pbx.write_text(source, encoding="utf-8")
PY

# Public associated-domain and OneSignal app-group files are generated too.
python3 - "$PROJECT_ROOT" "$IOS_DEVELOPMENT_TEAM" "$IOS_BUNDLE_ID" \
    "$IOS_ONESIGNAL_APP_GROUP" "$IOS_ASSOCIATED_DOMAIN" <<'PY'
import json
import pathlib
import plistlib
import sys

root, team, bundle, app_group, associated_domain = sys.argv[1:]
root = pathlib.Path(root)
for relative in ('web/apple-app-site-association', 'web/.well-known/apple-app-site-association'):
    path = root / relative
    if not path.exists():
        continue
    data = json.loads(path.read_text(encoding='utf-8'))
    def replace_identifiers(value, key=None):
        if isinstance(value, dict):
            return {child_key: replace_identifiers(item, child_key) for child_key, item in value.items()}
        if isinstance(value, list):
            if key in {'appIDs', 'apps'}:
                return [f'{team}.{bundle}']
            return [replace_identifiers(item) for item in value]
        if isinstance(value, str) and key == 'appID':
            return f'{team}.{bundle}'
        return value
    data = replace_identifiers(data)
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

for relative in (
    'ios/Runner/Info.plist',
    'ios/Runner/Runner.entitlements',
    'ios/OneSignalNotificationServiceExtension/Info.plist',
    'ios/OneSignalNotificationServiceExtension/OneSignalNotificationServiceExtensionRelease.entitlements',
):
    path = root / relative
    if not path.exists():
        continue
    with path.open('rb') as source:
        data = plistlib.load(source)
    if 'OneSignal_app_groups_key' in data:
        data['OneSignal_app_groups_key'] = app_group
    if 'com.apple.security.application-groups' in data:
        data['com.apple.security.application-groups'] = [app_group]
    if 'com.apple.developer.associated-domains' in data:
        data['com.apple.developer.associated-domains'] = [f'applinks:{associated_domain}']
    with path.open('wb') as destination:
        plistlib.dump(data, destination, sort_keys=False)
PY

# 5b. Update lib/theme_config.dart (Flutter Theme — seed colors live here, not in app_config.dart).
# Generate visible/internal iOS names while preserving the bundle ID.
IOS_INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"
if [ -f "$IOS_INFO_PLIST" ] && [ -n "$APP_NAME" ] && [ -n "$IOS_BUNDLE_NAME" ]; then
    python3 - "$IOS_INFO_PLIST" "$APP_NAME" "$IOS_BUNDLE_NAME" <<'PY'
import plistlib
import sys

path, display_name, bundle_name = sys.argv[1:]
with open(path, "rb") as source:
    plist = plistlib.load(source)
plist["CFBundleDisplayName"] = display_name
plist["CFBundleName"] = bundle_name
with open(path, "wb") as destination:
    plistlib.dump(plist, destination, sort_keys=False)
PY
    echo "✔ Updated iOS display and bundle names"
fi

# 5b. Update lib/theme_config.dart (Flutter Theme — seed colors live here, not in app_config.dart).
FLUTTER_THEME="$PROJECT_ROOT/lib/theme_config.dart"
if [ -f "$FLUTTER_THEME" ]; then
    echo "Updating $FLUTTER_THEME..."
    # Convert #RRGGBB to 0xFFRRGGBB
    if [ ! -z "$THEME_SEED_1" ]; then
        VAL="0xFF${THEME_SEED_1:1}"
        sed_inplace "s|static Color seed1 = const Color(.*);|static Color seed1 = const Color($VAL);|g" "$FLUTTER_THEME"
    fi
    if [ ! -z "$THEME_SEED_2" ]; then
        VAL="0xFF${THEME_SEED_2:1}"
        sed_inplace "s|static Color seed2 = const Color(.*);|static Color seed2 = const Color($VAL);|g" "$FLUTTER_THEME"
    fi
    if [ ! -z "$THEME_SEED_3" ]; then
        VAL="0xFF${THEME_SEED_3:1}"
        sed_inplace "s|static Color seed3 = const Color(.*);|static Color seed3 = const Color($VAL);|g" "$FLUTTER_THEME"
    fi
    if [ ! -z "$THEME_SEED_4" ]; then
        VAL="0xFF${THEME_SEED_4:1}"
        sed_inplace "s|static Color seed4 = const Color(.*);|static Color seed4 = const Color($VAL);|g" "$FLUTTER_THEME"
    fi
    echo "✔ Updated lib/theme_config.dart seed colors"
else
    echo "Warning: $FLUTTER_THEME not found."
fi

# 6. Update web_client/src/theme_config.css (Web Client Theme)
WEB_THEME="$PROJECT_ROOT/web_client/src/theme_config.css"
if [ -f "$WEB_THEME" ]; then
    echo "Updating $WEB_THEME..."

    if [ ! -z "$THEME_SEED_1" ]; then
        sed_inplace "s|--seed-1: .*;|--seed-1: $THEME_SEED_1;|g" "$WEB_THEME"
    fi
    if [ ! -z "$THEME_SEED_2" ]; then
        sed_inplace "s|--seed-2: .*;|--seed-2: $THEME_SEED_2;|g" "$WEB_THEME"
    fi
    if [ ! -z "$THEME_SEED_3" ]; then
        sed_inplace "s|--seed-3: .*;|--seed-3: $THEME_SEED_3;|g" "$WEB_THEME"
    fi

    if [ ! -z "$FORM_FONT_SCALE" ]; then
        sed_inplace "s|--font-scale: .*;|--font-scale: $FORM_FONT_SCALE;|g" "$WEB_THEME"
    fi

    echo "✔ Updated web_client/src/theme_config.css"
else
    echo "Warning: $WEB_THEME not found."
fi

# Legal and support pages are deterministic generated leaves. Their URLs and
# tenant identity come from the same project.conf used for the application.
node "$LEGAL_RENDERER" --config "$CONFIG_FILE"

echo "Project configuration applied successfully."

# 7. Font Configuration (Handled by configure_fonts.js)
# We invoke the helper script to handle dynamic file detection and rewrites
NODE_SCRIPT="$PROJECT_ROOT/automation/configure_fonts.js"

if [ -f "$NODE_SCRIPT" ] && [ -d "$PROJECT_ROOT/automation/fonts" ]; then
    echo "Running Dynamic Font Configuration..."
    node "$NODE_SCRIPT" "$PROJECT_ROOT" "$FONT_FAMILY_BASE"
else
    echo "Skipping Font Configuration (Script or fonts/ dir missing)"
fi

# 8. Version Configuration (Handled by configure_version.js)
VERSION_SCRIPT="$PROJECT_ROOT/automation/configure_version.js"
if [ -f "$VERSION_SCRIPT" ] && [ -n "$VERSION" ]; then
    echo "Running Version Configuration ($VERSION)..."
    node "$VERSION_SCRIPT" "$VERSION"
else
    echo "Skipping Version Configuration (Script missing or VERSION not set)"
fi
