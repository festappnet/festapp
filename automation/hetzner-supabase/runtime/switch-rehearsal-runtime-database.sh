#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
readonly SERVICES=(auth rest realtime storage meta functions studio)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_SOURCE_REGISTRY="$SCRIPT_DIR/../merge/source-registry.json"
readonly INSTALLED_SOURCE_REGISTRY="$SCRIPT_DIR/festapp-source-registry.json"
if [[ -f "$REPOSITORY_SOURCE_REGISTRY" ]]; then
  readonly SOURCE_REGISTRY="$REPOSITORY_SOURCE_REGISTRY"
else
  readonly SOURCE_REGISTRY="$INSTALLED_SOURCE_REGISTRY"
fi

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_RUNTIME_SWITCH_ACK:-}" == "switch-validated-rehearsal-runtime-database" ]] ||
  fail "set FESTAPP_RUNTIME_SWITCH_ACK=switch-validated-rehearsal-runtime-database"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "FESTAPP_RUNTIME_DATABASE must be postgres or a timestamped rehearsal database"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved rehearsal host"

cd "$COMPOSE_DIR"
[[ -f .env && "$(stat -c '%a' .env)" == "600" ]] || fail ".env must exist with mode 0600"
[[ -f docker-compose.database-target.yml ]] || fail "database target Compose override is missing"
[[ -f "$SOURCE_REGISTRY" ]] || fail "migration source registry is missing"
docker compose config -q

readonly CURRENT_DATABASE="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)"
[[ "$CURRENT_DATABASE" == "postgres" || "$CURRENT_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "current runtime database is missing or invalid"
[[ "$CURRENT_DATABASE" != "$TARGET_DATABASE" ]] || fail "runtime already targets $TARGET_DATABASE"

psql_target() {
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"
}
if [[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_ ]]; then
  mapfile -t SOURCE_ALIASES < <(jq -er '.sources[].alias' "$SOURCE_REGISTRY")
  [[ "${#SOURCE_ALIASES[@]}" -gt 0 ]] || fail "migration source registry is empty"
  for alias in "${SOURCE_ALIASES[@]}"; do
    [[ "$alias" =~ ^[a-z][a-z0-9_-]*$ ]] || fail "invalid migration source alias"
    [[ "$(psql_target -Atqc "SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='$alias' AND status='validated'")" == "1" ]] ||
      fail "target database does not contain exactly one validated $alias import"
  done
  readonly APPROVED_ALIASES_CSV="$(IFS=,; echo "${SOURCE_ALIASES[*]}")"
  readonly TARGET_STATE="$(psql_target -Atqc "SELECT concat_ws('|',
    (SELECT count(*) FROM festapp_merge.import_runs WHERE NOT (source_alias = ANY (string_to_array('$APPROVED_ALIASES_CSV', ',')))),
    (SELECT count(*) FROM festapp_merge.validation_results WHERE status<>'pass'),
    (SELECT count(*)>0 FROM auth.users),(SELECT count(*)>0 FROM storage.objects),
    (SELECT count(*) FROM realtime.schema_migrations)>0)")"
  [[ "$TARGET_STATE" == "0|0|t|t|t" ]] || fail "target database is not fully validated ($TARGET_STATE)"
fi

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly SWITCH_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/runtime-switch-$SWITCH_ID"
readonly ENV_BACKUP=".env.pre-runtime-target-$SWITCH_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"
install -o root -g root -m 0600 .env "$ENV_BACKUP"

set_runtime_database() {
  local database="$1"
  local staged_env
  staged_env="$(mktemp .env.runtime-target.XXXXXX)"
  awk -v value="$database" '
    BEGIN { written=0 }
    /^FESTAPP_RUNTIME_DATABASE=/ { print "FESTAPP_RUNTIME_DATABASE=" value; written=1; next }
    { print }
    END { if (!written) print "FESTAPP_RUNTIME_DATABASE=" value }
  ' .env >"$staged_env"
  chown root:root "$staged_env"
  chmod 0600 "$staged_env"
  mv -- "$staged_env" .env
}

wait_for_services() {
  local attempt unhealthy
  for attempt in $(seq 1 30); do
    unhealthy="$(docker compose ps --format json "${SERVICES[@]}" | jq -s '
      map(select(.State != "running" or (.Health != "" and .Health != "healthy"))) | length')"
    [[ "$unhealthy" == "0" ]] && return 0
    sleep 2
  done
  return 1
}

rollback() {
  install -o root -g root -m 0600 "$ENV_BACKUP" .env
  docker compose up -d --force-recreate "${SERVICES[@]}" >/dev/null
  wait_for_services || true
  echo "Runtime switch rolled back to $CURRENT_DATABASE; preserved evidence: $RUN_DIR" >&2
}
trap 'rollback' ERR

set_runtime_database "$TARGET_DATABASE"
docker compose config -q
docker compose up -d --force-recreate "${SERVICES[@]}" >/dev/null
wait_for_services

for spec in \
  auth:GOTRUE_DB_DATABASE_URL rest:PGRST_DB_URI realtime:DB_NAME storage:DATABASE_URL \
  meta:PG_META_DB_NAME functions:SUPABASE_DB_URL studio:POSTGRES_DB; do
  service="${spec%%:*}"
  variable="${spec#*:}"
  container="$(docker compose ps -q "$service")"
  value="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" |
    sed -n "s/^${variable}=//p")"
  case "$variable" in *URL|*URI) value="${value##*/}" ;; esac
  [[ "$value" == "$TARGET_DATABASE" ]] || fail "$service does not target the requested database"
done

readonly PUBLIC_HOSTNAME="$(sed -n 's/^FESTAPP_SUPABASE_HOSTNAME=//p' .env)"
readonly ANON_KEY="$(sed -n 's/^ANON_KEY=//p' .env)"
[[ "$PUBLIC_HOSTNAME" =~ ^[a-z0-9.-]+$ && -n "$ANON_KEY" ]] || fail "public canary configuration is invalid"
readonly API_ORIGIN="https://$PUBLIC_HOSTNAME"
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
  fail "public canary failed ($AUTH_STATUS|$REST_STATUS|$STORAGE_STATUS|$REALTIME_STATUS)"

trap - ERR
jq -n --arg switchedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg previousDatabase "$CURRENT_DATABASE" --arg targetDatabase "$TARGET_DATABASE" \
  --arg envBackup "$COMPOSE_DIR/$ENV_BACKUP" \
  --arg authStatus "$AUTH_STATUS" --arg restStatus "$REST_STATUS" --arg storageStatus "$STORAGE_STATUS" --arg realtimeStatus "$REALTIME_STATUS" \
  '{switched_at:$switchedAt,previous_database:$previousDatabase,target_database:$targetDatabase,
    env_backup:$envBackup,services_recreated:7,public_canary:{auth:$authStatus,rest:$restStatus,storage:$storageStatus,realtime:$realtimeStatus},
    production_dns_mutated:false,deleted_databases:[],deleted_paths:[]}' >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Rehearsal runtime switched to $TARGET_DATABASE with public canaries passing."
echo "Rollback env: $COMPOSE_DIR/$ENV_BACKUP"
echo "Evidence: $RUN_DIR"
