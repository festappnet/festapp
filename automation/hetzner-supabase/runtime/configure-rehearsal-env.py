#!/usr/bin/env python3
import os
import re
import secrets
from pathlib import Path
from shlex import quote
from urllib.parse import urlsplit

path = Path(".env")
runtime_database = os.environ.get("FESTAPP_RUNTIME_DATABASE", "postgres")
if runtime_database != "postgres" and not re.fullmatch(r"festapp_rehearsal_[0-9]{14}", runtime_database):
    raise SystemExit("FESTAPP_RUNTIME_DATABASE must be postgres or a timestamped rehearsal database")

auth_site_url = os.environ.get(
    "FESTAPP_AUTH_SITE_URL", "https://festapp-rehearsal-client.pages.dev"
)
auth_additional_origins = os.environ.get(
    "FESTAPP_AUTH_ADDITIONAL_ORIGINS",
    ",".join((
        "https://csmostrava.festapp.net",
        "https://hvezdamorska.festapp.net",
        "https://csa2024.festapp.net",
        "https://jubileum2025.festapp.net",
        "https://clovekavira.festapp.net",
        "https://rezervace.farnostopava.cz",
        "https://app.festivalslunovrat.cz",
        "https://csmostrava2026.pages.dev",
        "https://hvezdamorska.pages.dev",
        "https://aksmcz.pages.dev",
        "https://jubileum2025.pages.dev",
        "https://clovekavira.pages.dev",
        "https://farnostopava.pages.dev",
        "https://aksmcz.netlify.app",
        "https://hvezdamorska.netlify.app",
        "https://jubileum2025.netlify.app",
        "https://clovekavira.netlify.app",
    )),
)
auth_redirect_urls = os.environ.get("FESTAPP_AUTH_REDIRECT_URLS", "")


def existing_value(key: str) -> str | None:
    prefix = f"{key}="
    for line in path.read_text().splitlines():
        if line.startswith(prefix):
            value = line[len(prefix):].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1]
            return value
    return None


def https_origin(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
        raise SystemExit("FESTAPP_AUTH_SITE_URL must be an HTTPS origin")
    return f"https://{parsed.netloc}"


auth_site_url = https_origin(auth_site_url)
allowed_origins = [auth_site_url]
for origin in filter(None, (item.strip() for item in auth_additional_origins.split(","))):
    normalized = https_origin(origin)
    if normalized not in allowed_origins:
        allowed_origins.append(normalized)

redirect_urls = [
    f"{origin}{path}"
    for origin in allowed_origins
    for path in ("/reset-password", "/resetPassword", "/auth_bridge", "/auth_bridge.html")
]
for redirect in filter(None, (item.strip() for item in auth_redirect_urls.split(","))):
    parsed = urlsplit(redirect)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or not parsed.path.startswith("/")):
        raise SystemExit("FESTAPP_AUTH_REDIRECT_URLS contains an invalid HTTPS callback URL")
    if f"https://{parsed.netloc}" not in allowed_origins:
        raise SystemExit("Auth redirect callbacks must use an approved Auth origin")
    if redirect not in redirect_urls:
        redirect_urls.append(redirect)
updates = {
    "COMPOSE_FILE": "docker-compose.yml:docker-compose.festapp.yml:docker-compose.database-target.yml",
    "FESTAPP_RUNTIME_DATABASE": runtime_database,
    "FESTAPP_SUPABASE_HOSTNAME": "rehearsal-api.festapp.net",
    # Prepare the canonical hostname without changing the runtime-generated
    # public URL or activating any client. The one-way activation manifest is
    # still the only switch from legacy to canonical writers.
    "FESTAPP_SUPABASE_SITE_ADDRESSES": "rehearsal-api.festapp.net, api.festapp.net",
    "SUPABASE_PUBLIC_URL": "https://rehearsal-api.festapp.net",
    "API_EXTERNAL_URL": "https://rehearsal-api.festapp.net",
    "SITE_URL": auth_site_url,
    "ADDITIONAL_REDIRECT_URLS": ",".join(redirect_urls),
    "FESTAPP_ALLOWED_WEB_ORIGINS": ",".join(allowed_origins),
    # Stable secret used only to hash reception QR rate-limit identifiers. Keep
    # the existing value on repeat runs and never commit it to the repository.
    "QR_RATE_SALT": existing_value("QR_RATE_SALT") or secrets.token_urlsafe(32),
    "AWS_SNS_TOPIC_ARN": existing_value("AWS_SNS_TOPIC_ARN") or
        "arn:aws:sns:eu-central-1:000000000000:festapp-rehearsal-disabled",
    "NOTIFY_WEBHOOK_TOKEN": existing_value("NOTIFY_WEBHOOK_TOKEN") or secrets.token_urlsafe(48),
    "DISABLE_SIGNUP": "true",
    "ENABLE_PHONE_SIGNUP": "false",
    "ENABLE_PHONE_AUTOCONFIRM": "false",
    "DASHBOARD_USERNAME": "festapp-rehearsal",
    "STUDIO_DEFAULT_ORGANIZATION": "Festapp Rehearsal",
    "STUDIO_DEFAULT_PROJECT": "Canonical Merge Rehearsal",
}

lines = path.read_text().splitlines()
seen = set()
output = []
for line in lines:
    key = line.split("=", 1)[0] if "=" in line and not line.lstrip().startswith("#") else None
    if key in updates:
        output.append(f"{key}={quote(updates[key])}")
        seen.add(key)
    else:
        output.append(line)
for key, value in updates.items():
    if key not in seen:
        output.append(f"{key}={quote(value)}")
path.write_text("\n".join(output) + "\n")
path.chmod(0o600)
