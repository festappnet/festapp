#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly ADMIN_HOSTNAME="supabase.festapp.net"
readonly ADMIN_SITE="https://$ADMIN_HOSTNAME"
readonly API_ORIGIN="https://api.festapp.net"
readonly ADMIN_ORIGIN="http://127.0.0.1:8999"
readonly TUNNEL_ID="40e1a9a2-d1d5-4789-a691-20818d648b95"
readonly TUNNEL_TOKEN_FILE="${FESTAPP_ADMIN_TUNNEL_TOKEN_FILE:-/etc/festapp-cloudflared/admin-tunnel.token}"
readonly CANDIDATE_DIR="${FESTAPP_ADMIN_DASHBOARD_CANDIDATE_DIR:-$COMPOSE_DIR/festapp-admin-dashboard}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_ADMIN_DASHBOARD_ACK:-}" == "activate-cloudflare-access-protected-supabase-dashboard" ]] ||
  fail "set FESTAPP_ADMIN_DASHBOARD_ACK=activate-cloudflare-access-protected-supabase-dashboard"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ -f "$COMPOSE_DIR/.env" && "$(stat -c '%U:%G|%a' "$COMPOSE_DIR/.env")" == "root:root|600" ]] ||
  fail ".env must be root-owned with mode 0600"
for candidate in Caddyfile docker-compose.festapp.yml; do
  [[ -f "$CANDIDATE_DIR/$candidate" && "$(stat -c '%U:%G' "$CANDIDATE_DIR/$candidate")" == "root:root" ]] ||
    fail "missing root-owned administrator dashboard candidate: $candidate"
done
[[ -f "$TUNNEL_TOKEN_FILE" && "$(stat -c '%U:%G|%a' "$TUNNEL_TOKEN_FILE")" == "root:root|600" ]] ||
  fail "administrator tunnel token must be root-owned with mode 0600"
base64 -d <"$TUNNEL_TOKEN_FILE" 2>/dev/null |
  jq -e --arg tunnel_id "$TUNNEL_ID" '.t == $tunnel_id and (.s | type == "string" and length > 0)' >/dev/null ||
  fail "administrator tunnel token does not belong to the approved tunnel"
for dependency in base64 curl docker flock jq rg ss; do
  command -v "$dependency" >/dev/null || fail "$dependency is required"
done

cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime upgrade, promotion or dashboard activation is active"

readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/admin-dashboard-activation-$RUN_ID"
readonly ENV_BACKUP="$RUN_DIR/env.before"
readonly CADDY_BACKUP="$RUN_DIR/Caddyfile.before"
readonly COMPOSE_BACKUP="$RUN_DIR/docker-compose.festapp.yml.before"
readonly ACCESS_HEADERS="$RUN_DIR/cloudflare-access.headers"
install -d -o root -g root -m 0700 "$RUN_DIR"
install -o root -g root -m 0600 .env "$ENV_BACKUP"
install -o root -g root -m 0600 caddy/Caddyfile "$CADDY_BACKUP"
install -o root -g root -m 0600 docker-compose.festapp.yml "$COMPOSE_BACKUP"

api_canary() {
  local anon_key auth_status rest_status storage_status realtime_status
  anon_key="$(sed -n 's/^ANON_KEY=//p' .env)"
  [[ -n "$anon_key" ]] || return 1
  auth_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "apikey: $anon_key" "$API_ORIGIN/auth/v1/settings")"
  rest_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "apikey: $anon_key" -H "Authorization: Bearer $anon_key" \
    "$API_ORIGIN/rest/v1/occasions?select=id&limit=1")"
  storage_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    "$API_ORIGIN/storage/v1/status")"
  realtime_status="$(curl -sS -o /dev/null -w '%{http_code}' --http1.1 --max-time 10 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==' \
    "$API_ORIGIN/realtime/v1/websocket?apikey=$anon_key&vsn=1.0.0" 2>/dev/null || true)"
  [[ "$auth_status|$rest_status|$storage_status|$realtime_status" == "200|200|200|101" ]]
}

# Access must already intercept the hostname. This prevents an accidental
# public Studio deployment if DNS exists but the identity policy does not.
readonly ACCESS_STATUS="$(curl -sS -o /dev/null -D "$ACCESS_HEADERS" -w '%{http_code}' \
  --max-time 20 "$ADMIN_SITE/")"
chmod 0600 "$ACCESS_HEADERS"
[[ "$ACCESS_STATUS" == "302" &&
   "$(sed -n 's/^location: //Ip' "$ACCESS_HEADERS" | tr -d '\r')" == https://*.cloudflareaccess.com/cdn-cgi/access/login/* ]] ||
  fail "$ADMIN_SITE is not intercepted by a Cloudflare Access login policy"

api_canary || fail "canonical API baseline canary failed before dashboard activation"

rollback() {
  docker compose --profile admin-dashboard stop admin-tunnel >/dev/null 2>&1 || true
  install -o root -g root -m 0600 "$ENV_BACKUP" .env
  install -o root -g root -m 0644 "$CADDY_BACKUP" caddy/Caddyfile
  install -o root -g root -m 0644 "$COMPOSE_BACKUP" docker-compose.festapp.yml
  docker compose up -d --force-recreate caddy >/dev/null || true
  echo "Administrator dashboard activation rolled back; evidence: $RUN_DIR" >&2
}
trap rollback ERR

install -o root -g root -m 0644 "$CANDIDATE_DIR/Caddyfile" caddy/Caddyfile
install -o root -g root -m 0644 "$CANDIDATE_DIR/docker-compose.festapp.yml" docker-compose.festapp.yml
docker compose config -q
docker compose --profile admin-dashboard up -d --force-recreate caddy admin-tunnel >/dev/null
readonly CADDY_CONTAINER="$(docker compose ps -q caddy)"
readonly OBSERVED_ADMIN_SITE="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CADDY_CONTAINER" |
  sed -n 's/^FESTAPP_SUPABASE_ADMIN_SITE=//p')"
[[ "$OBSERVED_ADMIN_SITE" == "$ADMIN_ORIGIN" ]] ||
  fail "administrator Caddy listener is not confined to loopback"
readonly ADMIN_LISTENERS="$(ss -H -lnt 'sport = :8999' | awk '{print $4}' | sort -u)"
[[ "$ADMIN_LISTENERS" == "127.0.0.1:8999" ]] ||
  fail "administrator Caddy socket is not bound exclusively to IPv4 loopback"

TUNNEL_CONNECTED=false
for _attempt in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:20241/metrics 2>/dev/null |
    awk '/^cloudflared_tunnel_ha_connections(\{| )/{total += $NF} END {exit !(total > 0)}'; then
    TUNNEL_CONNECTED=true
    break
  fi
  sleep 2
done
[[ "$TUNNEL_CONNECTED" == true ]] || fail "administrator tunnel did not establish a Cloudflare connection"

readonly LOCAL_ADMIN_STATUS="$(curl -sS -o /dev/null -D "$RUN_DIR/local-admin.headers" \
  -w '%{http_code}' --max-time 10 "$ADMIN_ORIGIN/")"
chmod 0600 "$RUN_DIR/local-admin.headers"
[[ "$LOCAL_ADMIN_STATUS" == "401" ]] || fail "loopback administrator origin is not protected by Supabase Basic authentication"
rg -qi '^www-authenticate: Basic ' "$RUN_DIR/local-admin.headers" ||
  fail "loopback administrator origin did not request Basic authentication"

api_canary || fail "canonical API canary failed after dashboard activation"
readonly API_ROOT_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$API_ORIGIN/")"
readonly API_META_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$API_ORIGIN/pg/")"
readonly POST_ACCESS_STATUS="$(curl -sS -o /dev/null -D "$ACCESS_HEADERS" -w '%{http_code}' \
  --max-time 20 "$ADMIN_SITE/")"
[[ "$API_ROOT_STATUS|$API_META_STATUS" == "404|404" ]] ||
  fail "Studio or postgres-meta is still exposed on the public API hostname"
[[ "$POST_ACCESS_STATUS" == "302" &&
   "$(sed -n 's/^location: //Ip' "$ACCESS_HEADERS" | tr -d '\r')" == https://*.cloudflareaccess.com/cdn-cgi/access/login/* ]] ||
  fail "Cloudflare Access stopped intercepting the administrator hostname"

trap - ERR
jq -n --arg activated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg admin_hostname "$ADMIN_HOSTNAME" --arg access_status "$POST_ACCESS_STATUS" \
  --arg api_root_status "$API_ROOT_STATUS" --arg api_meta_status "$API_META_STATUS" \
  --arg tunnel_id "$TUNNEL_ID" --arg local_admin_status "$LOCAL_ADMIN_STATUS" \
  '{version:1,activated_at:$activated_at,admin_hostname:$admin_hostname,
    cloudflare_access_intercept_status:$access_status,
    tunnel:{id:$tunnel_id,connected:true,origin:"http://127.0.0.1:8999"},
    local_basic_auth_status:$local_admin_status,
    canonical_api_canary:{auth:"200",rest:"200",storage:"200",realtime:"101"},
    public_dashboard_routes:{root:$api_root_status,postgres_meta:$api_meta_status},
    database_mutated:false,api_credentials_rotated:false}' >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Cloudflare Access-protected administrator dashboard activated: $ADMIN_SITE"
echo "Evidence: $RUN_DIR"
