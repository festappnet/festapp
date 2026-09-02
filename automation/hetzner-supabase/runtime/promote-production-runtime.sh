#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
readonly FINAL_MARKER="${FESTAPP_FINAL_MARKER_DECISION:-}"
readonly BACKUP_MANIFEST="${FESTAPP_PROMOTION_BACKUP_MANIFEST:-}"
readonly RESTORE_RESULT="${FESTAPP_PROMOTION_RESTORE_RESULT:-}"
readonly RUNTIME_CONFIG="${FESTAPP_PRODUCTION_RUNTIME_CONFIG:-}"
readonly SERVICES=(caddy api-gw auth rest realtime storage meta functions studio)

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_PRODUCTION_PROMOTION_ACK:-}" == "promote-validated-runtime-without-opening-write-authority" ]] ||
  fail "set FESTAPP_PRODUCTION_PROMOTION_ACK=promote-validated-runtime-without-opening-write-authority"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "FESTAPP_RUNTIME_DATABASE must be the exact timestamped promotion target"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
for evidence in "$FINAL_MARKER" "$BACKUP_MANIFEST" "$RESTORE_RESULT" "$RUNTIME_CONFIG"; do
  [[ "$evidence" == /* && -f "$evidence" && "$(stat -c '%a' "$evidence")" == "600" ]] ||
    fail "promotion inputs must be absolute existing files with mode 0600"
done
command -v flock >/dev/null || fail "flock is required"

cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime upgrade or promotion is active"
[[ -f .env && "$(stat -c '%U:%G|%a' .env)" == "root:root|600" ]] ||
  fail ".env must be root-owned with mode 0600"
for installed in festapp-source-registry.json festapp-reference-registry.json; do
  [[ -f "$installed" && "$(stat -c '%U:%G|%a' "$installed")" == "root:root|444" ]] ||
    fail "$installed is not an immutable installed registry"
done
for installed in validate-production-promotion.mjs docker-compose.database-target.yml; do
  [[ -f "$installed" ]] || fail "$installed is not installed"
done
[[ ! -e "$COMPOSE_DIR/volumes/functions/instance-install" ]] ||
  fail "instance-install must not be present in the production Function bundle"
docker compose config -q

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly SWITCH_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/production-runtime-promotion-$SWITCH_ID"
readonly ENV_BACKUP="$COMPOSE_DIR/.env.pre-production-promotion-$SWITCH_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"

node "$COMPOSE_DIR/validate-production-promotion.mjs" \
  --target-database="$TARGET_DATABASE" \
  --source-registry="$COMPOSE_DIR/festapp-source-registry.json" \
  --reference-registry="$COMPOSE_DIR/festapp-reference-registry.json" \
  --final-marker="$FINAL_MARKER" --backup-manifest="$BACKUP_MANIFEST" \
  --restore-result="$RESTORE_RESULT" --runtime-config="$RUNTIME_CONFIG" \
  --output="$RUN_DIR/preflight.json"

mapfile -t EXPECTED_IMPORTS < <(jq -r '.sources[]|[.alias,.project_ref]|@tsv' festapp-source-registry.json | sort)
mapfile -t ACTUAL_IMPORTS < <(docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres \
  -d "$TARGET_DATABASE" -AtF $'\t' -c \
  "SELECT source_alias,source_project_ref FROM festapp_merge.import_runs WHERE status='validated' ORDER BY source_alias")
[[ "${EXPECTED_IMPORTS[*]}" == "${ACTUAL_IMPORTS[*]}" ]] || fail "target import registry mismatch"
readonly REFERENCE_VERSION="$(jq -r .version festapp-reference-registry.json)"
mapfile -t MERGE_SOURCE_ALIASES < <(jq -er '.sources[]|select(.role=="merge-source")|.alias' festapp-source-registry.json | sort)
readonly EXPECTED_REFERENCE_PASSES="${#MERGE_SOURCE_ALIASES[@]}"
[[ "$EXPECTED_REFERENCE_PASSES" -gt 0 ]] || fail "source registry contains no merge-source reference gates"
readonly MERGE_SOURCE_ALIASES_CSV="$(IFS=,; echo "${MERGE_SOURCE_ALIASES[*]}")"
readonly TARGET_STATE="$(docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres \
  -d "$TARGET_DATABASE" -Atqc "SELECT concat_ws('|',
    (SELECT count(*) FROM festapp_merge.import_runs),
    (SELECT count(*) FROM festapp_merge.validation_results WHERE status<>'pass'),
    (SELECT count(*) FROM festapp_merge.validation_results v
      JOIN festapp_merge.import_runs r USING(run_id)
      WHERE r.source_alias=ANY(string_to_array('$MERGE_SOURCE_ALIASES_CSV',','))
        AND v.check_name=r.source_alias||'-reference-registry-completeness'
        AND v.observed->>'registry_version'='$REFERENCE_VERSION' AND v.status='pass'),
    (SELECT count(DISTINCT r.source_alias) FROM festapp_merge.validation_results v
      JOIN festapp_merge.import_runs r USING(run_id)
      WHERE r.source_alias=ANY(string_to_array('$MERGE_SOURCE_ALIASES_CSV',','))
        AND v.check_name=r.source_alias||'-reference-registry-completeness'
        AND v.observed->>'registry_version'='$REFERENCE_VERSION' AND v.status='pass'),
    (SELECT count(*)>0 FROM auth.users),(SELECT count(*)>0 FROM storage.objects),
    (SELECT count(*)>0 FROM realtime.schema_migrations),
    (SELECT count(*) FROM pg_trigger WHERE tgname='push_log_notifications' AND NOT tgisinternal))")"
[[ "$TARGET_STATE" == "3|0|$EXPECTED_REFERENCE_PASSES|$EXPECTED_REFERENCE_PASSES|t|t|t|0" ]] ||
  fail "target database is not promotion-ready ($TARGET_STATE)"

readonly CURRENT_DATABASE="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)"
[[ "$CURRENT_DATABASE" == "postgres" || "$CURRENT_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "current runtime database is invalid"
install -o root -g root -m 0600 .env "$ENV_BACKUP"

set_env_value() {
  local key="$1" value="$2" staged
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "invalid newline in $key"
  staged="$(mktemp .env.production.XXXXXX)"
  awk -v key="$key" -v value="$value" '
    BEGIN { written=0 }
    index($0,key "=")==1 { print key "=" value; written=1; next }
    { print }
    END { if (!written) print key "=" value }
  ' .env >"$staged"
  chown root:root "$staged"
  chmod 0600 "$staged"
  mv -- "$staged" .env
}

wait_for_services() {
  local attempt unhealthy
  for attempt in $(seq 1 45); do
    unhealthy="$(docker compose ps --format json "${SERVICES[@]}" | jq -s \
      'map(select(.State != "running" or (.Health != "" and .Health != "healthy"))) | length')"
    [[ "$unhealthy" == "0" ]] && return 0
    sleep 2
  done
  return 1
}

rollback() {
  install -o root -g root -m 0600 "$ENV_BACKUP" .env
  docker compose up -d --force-recreate "${SERVICES[@]}" >/dev/null || true
  wait_for_services || true
  echo "Production promotion rolled back to the preserved runtime configuration: $ENV_BACKUP" >&2
}
trap rollback ERR

set_env_value FESTAPP_RUNTIME_DATABASE "$TARGET_DATABASE"
set_env_value FESTAPP_SUPABASE_HOSTNAME "$(jq -r .public_hostname "$RUNTIME_CONFIG")"
set_env_value FESTAPP_SUPABASE_SITE_ADDRESSES "$(jq -r .public_hostname "$RUNTIME_CONFIG")"
set_env_value SUPABASE_PUBLIC_URL "$(jq -r .supabase_public_url "$RUNTIME_CONFIG")"
set_env_value API_EXTERNAL_URL "$(jq -r .api_external_url "$RUNTIME_CONFIG")"
set_env_value SITE_URL "$(jq -r .site_url "$RUNTIME_CONFIG")"
set_env_value ADDITIONAL_REDIRECT_URLS "$(jq -r '.auth_redirect_urls|join(",")' "$RUNTIME_CONFIG")"
set_env_value FESTAPP_ALLOWED_WEB_ORIGINS "$(jq -r '.allowed_web_origins|join(",")' "$RUNTIME_CONFIG")"
set_env_value AWS_SNS_TOPIC_ARN "$(jq -r .aws_sns_topic_arn "$RUNTIME_CONFIG")"
docker compose config -q
docker compose up -d --force-recreate "${SERVICES[@]}" >/dev/null
wait_for_services

for spec in auth:GOTRUE_DB_DATABASE_URL rest:PGRST_DB_URI realtime:DB_NAME storage:DATABASE_URL \
  meta:PG_META_DB_NAME functions:SUPABASE_DB_URL studio:POSTGRES_DB; do
  service="${spec%%:*}"; variable="${spec#*:}"
  container="$(docker compose ps -q "$service")"
  value="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" |
    sed -n "s/^${variable}=//p")"
  case "$variable" in *URL|*URI) value="${value##*/}" ;; esac
  [[ "$value" == "$TARGET_DATABASE" ]] || fail "$service does not target $TARGET_DATABASE"
done

container_env() {
  local service="$1" variable="$2" container
  container="$(docker compose ps -q "$service")"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" |
    sed -n "s/^${variable}=//p"
}
readonly EXPECTED_SITE_URL="$(jq -r .site_url "$RUNTIME_CONFIG")"
readonly EXPECTED_REDIRECTS="$(jq -r '.auth_redirect_urls|join(",")' "$RUNTIME_CONFIG")"
readonly EXPECTED_ORIGINS="$(jq -r '.allowed_web_origins|join(",")' "$RUNTIME_CONFIG")"
readonly EXPECTED_SNS_TOPIC="$(container_env functions AWS_SNS_TOPIC_ARN)"
readonly EXPECTED_NOTIFY_TOKEN="$(container_env functions NOTIFY_WEBHOOK_TOKEN)"
readonly EXPECTED_NOTIFY_TOKEN_SHA="$(printf '%s' "$EXPECTED_NOTIFY_TOKEN" | sha256sum | awk '{print $1}')"
[[ "$(container_env caddy FESTAPP_SUPABASE_HOSTNAME)" == "api.festapp.net" &&
   "$(container_env caddy FESTAPP_SUPABASE_SITE_ADDRESSES)" == "api.festapp.net" &&
   "$(container_env auth API_EXTERNAL_URL)" == "https://api.festapp.net" &&
   "$(container_env auth GOTRUE_SITE_URL)" == "$EXPECTED_SITE_URL" &&
   "$(container_env auth GOTRUE_URI_ALLOW_LIST)" == "$EXPECTED_REDIRECTS" &&
   "$(container_env functions FESTAPP_ALLOWED_WEB_ORIGINS)" == "$EXPECTED_ORIGINS" &&
   "$EXPECTED_SNS_TOPIC" =~ ^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$ &&
   "${#EXPECTED_NOTIFY_TOKEN}" -ge 32 &&
   "$EXPECTED_NOTIFY_TOKEN_SHA" == "$(jq -r .notify_webhook_token_sha256 "$RUNTIME_CONFIG")" &&
   "$(container_env studio SUPABASE_PUBLIC_URL)" == "https://api.festapp.net" ]] ||
  fail "runtime external URL, Auth redirect or CORS configuration is incoherent"

readonly ANON_KEY="$(sed -n 's/^ANON_KEY=//p' .env)"
readonly API_ORIGIN="https://api.festapp.net"
[[ -n "$ANON_KEY" ]] || fail "public anon key is missing"
readonly AUTH_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  -H "apikey: $ANON_KEY" "$API_ORIGIN/auth/v1/settings")"
readonly REST_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  "$API_ORIGIN/rest/v1/occasions?select=id&limit=1")"
readonly STORAGE_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
  "$API_ORIGIN/storage/v1/status")"
readonly REALTIME_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --http1.1 --max-time 10 \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==' \
  "$API_ORIGIN/realtime/v1/websocket?apikey=$ANON_KEY&vsn=1.0.0" 2>/dev/null || true)"
[[ "$AUTH_STATUS|$REST_STATUS|$STORAGE_STATUS|$REALTIME_STATUS" == "200|200|200|101" ]] ||
  fail "canonical API canary failed ($AUTH_STATUS|$REST_STATUS|$STORAGE_STATUS|$REALTIME_STATUS)"

readonly CANARY_COUNT="$(jq '.tenant_canaries|length' "$RUNTIME_CONFIG")"
while IFS=$'\t' read -r tenant organization occasion web_origin manifest_url manifest_sha; do
  [[ "$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 20 "$web_origin/")" == "200" ]] ||
    fail "$tenant web canary failed"
  manifest_file="$RUN_DIR/$tenant-backend-activation.json"
  curl -fsS --max-time 20 -o "$manifest_file" "$manifest_url"
  chmod 0600 "$manifest_file"
  [[ "$(sha256sum "$manifest_file" | awk '{print $1}')" == "$manifest_sha" ]] ||
    fail "$tenant activation manifest digest changed"
  [[ "$(jq -r '[.tenant,.phase]|join("|")' "$manifest_file")" == "$tenant|legacy" ]] ||
    fail "$tenant activation is not pinned to legacy"
  occasion_body="$(curl -fsS --max-time 20 --get \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
    --data-urlencode 'select=id,organization,link' --data-urlencode "organization=eq.$organization" \
    --data-urlencode "link=eq.$occasion" "$API_ORIGIN/rest/v1/occasions")"
  [[ "$(jq -r 'length' <<<"$occasion_body")" == "1" ]] || fail "$tenant canonical occasion canary failed"
done < <(jq -r '.tenant_canaries[]|[.tenant_id,.organization_id,.occasion_link,.web_origin,
  .activation_manifest_url,.legacy_activation_sha256]|@tsv' "$RUNTIME_CONFIG")

trap - ERR
jq -n --arg promoted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg previous_database "$CURRENT_DATABASE" --arg target_database "$TARGET_DATABASE" \
  --arg rollback_env "$ENV_BACKUP" --argjson tenant_canaries "$CANARY_COUNT" \
  --arg auth "$AUTH_STATUS" --arg rest "$REST_STATUS" --arg storage "$STORAGE_STATUS" \
  --arg realtime "$REALTIME_STATUS" \
  '{promoted_at:$promoted_at,previous_database:$previous_database,target_database:$target_database,
    rollback_env:$rollback_env,canonical_api_canary:{auth:$auth,rest:$rest,storage:$storage,realtime:$realtime},
    tenant_canaries:$tenant_canaries,client_activation_documents_published:false,
    external_write_authority_opened:false,production_dns_mutated:false,
    deleted_databases:[],deleted_paths:[]}' >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Canonical runtime promotion passed without publishing client activation or opening write authority."
echo "Rollback env: $ENV_BACKUP"
echo "Evidence: $RUN_DIR"
