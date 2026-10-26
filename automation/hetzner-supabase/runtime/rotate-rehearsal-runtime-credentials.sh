#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly ACK="${FESTAPP_REHEARSAL_ACK:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$ACK" == "rotate-exposed-rehearsal-runtime-credentials" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=rotate-exposed-rehearsal-runtime-credentials"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved rehearsal host"

cd "$COMPOSE_DIR"
[[ "$(stat -c '%a' .env)" == "600" ]] || fail ".env must be mode 0600"
TARGET_DATABASE="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)"
readonly TARGET_DATABASE
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "the active database must be a timestamped rehearsal target"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_ID
readonly WORK_DIR="/run/festapp-runtime-credential-rotation-$RUN_ID"
readonly RUN_DIR="$EVIDENCE_ROOT/runtime-credential-rotation-$RUN_ID"
readonly ENV_BACKUP="$COMPOSE_DIR/.env.pre-credential-rotation-$RUN_ID"
readonly ENV_NEXT="$WORK_DIR/env.next"
readonly OLD_POSTGRES="$WORK_DIR/old-postgres"
readonly OLD_JWT="$WORK_DIR/old-jwt"
readonly OLD_ANON="$WORK_DIR/old-anon"
readonly OLD_SERVICE="$WORK_DIR/old-service"
readonly NEW_POSTGRES="$WORK_DIR/new-postgres"
readonly NEW_JWT="$WORK_DIR/new-jwt"
readonly NEW_ANON="$WORK_DIR/new-anon"
readonly NEW_SERVICE="$WORK_DIR/new-service"

install -d -o root -g root -m 0700 "$WORK_DIR" "$RUN_DIR"
install -o root -g root -m 0600 .env "$ENV_BACKUP"

python3 - "$ENV_BACKUP" "$OLD_POSTGRES" "$OLD_JWT" "$OLD_ANON" "$OLD_SERVICE" <<'PY'
from pathlib import Path
import sys

values = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        values[key] = value.strip().strip("'").strip('"')
for key, path in zip(
    ("POSTGRES_PASSWORD", "JWT_SECRET", "ANON_KEY", "SERVICE_ROLE_KEY"),
    sys.argv[2:],
):
    value = values.get(key, "")
    if not value:
        raise SystemExit(f"missing required environment key: {key}")
    Path(path).write_text(value)
    Path(path).chmod(0o600)
PY

openssl rand -hex 32 >"$NEW_POSTGRES"
openssl rand -base64 48 | tr -d '\n' >"$NEW_JWT"
chmod 0600 "$NEW_POSTGRES" "$NEW_JWT"

base64_url_encode() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
generate_token() {
  local role="$1" output="$2" jwt_secret header payload signed signature now expires
  jwt_secret="$(<"$NEW_JWT")"
  header="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | base64_url_encode)"
  now="$(date +%s)"
  expires="$((now + 5 * 365 * 24 * 3600))"
  payload="$(printf '{"role":"%s","iss":"supabase","iat":%s,"exp":%s}' "$role" "$now" "$expires" | base64_url_encode)"
  signed="$header.$payload"
  signature="$(printf '%s' "$signed" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | base64_url_encode)"
  printf '%s' "$signed.$signature" >"$output"
  chmod 0600 "$output"
}
generate_token anon "$NEW_ANON"
generate_token service_role "$NEW_SERVICE"

python3 - "$ENV_BACKUP" "$ENV_NEXT" "$NEW_POSTGRES" "$NEW_JWT" "$NEW_ANON" "$NEW_SERVICE" <<'PY'
from pathlib import Path
import sys

source, target = map(Path, sys.argv[1:3])
replacement_files = dict(zip(
    ("POSTGRES_PASSWORD", "JWT_SECRET", "ANON_KEY", "SERVICE_ROLE_KEY"),
    map(Path, sys.argv[3:]),
))
replacements = {key: path.read_text() for key, path in replacement_files.items()}
seen = set()
out = []
for line in source.read_text().splitlines():
    key = line.split("=", 1)[0] if "=" in line and not line.lstrip().startswith("#") else None
    if key in replacements:
        out.append(f"{key}={replacements[key]}")
        seen.add(key)
    else:
        out.append(line)
if seen != set(replacements):
    raise SystemExit("the existing environment is missing a credential key")
target.write_text("\n".join(out) + "\n")
target.chmod(0o600)
PY

docker compose --env-file "$ENV_NEXT" config -q

roles_changed=false
env_changed=false
cleanup() {
  rm -f "$OLD_POSTGRES" "$OLD_JWT" "$OLD_ANON" "$OLD_SERVICE" \
    "$NEW_POSTGRES" "$NEW_JWT" "$NEW_ANON" "$NEW_SERVICE" "$ENV_NEXT"
  rmdir "$WORK_DIR" 2>/dev/null || true
}
rollback() {
  local exit_code=$?
  trap - EXIT
  docker compose stop caddy >/dev/null 2>&1 || true
  if [[ "$env_changed" == true ]]; then install -o root -g root -m 0600 "$ENV_BACKUP" .env; fi
  if [[ "$roles_changed" == true ]]; then
    apply_database_credentials "$OLD_POSTGRES" "$OLD_JWT" || true
  fi
  if [[ "$env_changed" == true || "$roles_changed" == true ]]; then
    docker compose up -d --force-recreate db api-gw auth rest realtime storage meta functions studio supavisor >/dev/null 2>&1 || true
  fi
  docker compose up -d caddy >/dev/null 2>&1 || true
  cleanup
  echo "ERROR: rehearsal credential rotation failed and rollback was attempted" >&2
  exit "$exit_code"
}
trap rollback EXIT

apply_database_credentials() {
  local password_file="$1" jwt_file="$2" password jwt
  password="$(<"$password_file")"
  jwt="$(<"$jwt_file")"
  {
    printf 'BEGIN;\n'
    for role in postgres authenticator pgbouncer supabase_admin supabase_auth_admin supabase_functions_admin supabase_storage_admin; do
      printf "ALTER ROLE %s PASSWORD '%s';\n" "$role" "$password"
    done
    printf "ALTER DATABASE postgres SET \"app.settings.jwt_secret\" TO '%s';\n" "$jwt"
    printf "ALTER DATABASE %s SET \"app.settings.jwt_secret\" TO '%s';\n" "$TARGET_DATABASE" "$jwt"
    printf 'COMMIT;\n'
  } | docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres >/dev/null
}

docker compose stop caddy >/dev/null
apply_database_credentials "$NEW_POSTGRES" "$NEW_JWT"
roles_changed=true
install -o root -g root -m 0600 "$ENV_NEXT" .env
env_changed=true

docker compose up -d --force-recreate db api-gw auth rest realtime storage meta functions studio supavisor >/dev/null

for _ in $(seq 1 60); do
  unhealthy="$(docker compose ps --format json | jq -s '[.[] | select(.State != "running" or ((.Health // "") != "" and .Health != "healthy"))] | length')"
  [[ "$unhealthy" == "0" ]] && break
  sleep 2
done
[[ "$unhealthy" == "0" ]] || fail "one or more runtime services did not become healthy"

docker compose up -d caddy >/dev/null

new_password="$(<"$NEW_POSTGRES")"
database_network="$(docker inspect supabase-db --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}')"
database_image="$(docker inspect supabase-db --format '{{.Config.Image}}')"
for role in postgres authenticator pgbouncer supabase_admin supabase_auth_admin supabase_functions_admin supabase_storage_admin; do
  login_database="$TARGET_DATABASE"
  if [[ "$role" == "pgbouncer" || "$role" == "supabase_functions_admin" ]]; then
    login_database="postgres"
  fi
  printf '%s\n' "$new_password" | docker run --rm -i --network "$database_network" "$database_image" sh -c \
    "IFS= read -r PGPASSWORD; export PGPASSWORD; psql -X -h db -U '$role' -d '$login_database' -Atqc 'SELECT 1' >/dev/null"
done
old_password="$(<"$OLD_POSTGRES")"
if printf '%s\n' "$old_password" | docker run --rm -i --network "$database_network" "$database_image" sh -c \
  "IFS= read -r PGPASSWORD; export PGPASSWORD; psql -X -h db -U postgres -d '$TARGET_DATABASE' -Atqc 'SELECT 1' >/dev/null 2>&1"; then
  fail "the old PostgreSQL password is still accepted"
fi

new_jwt_md5="$(md5sum "$NEW_JWT" | awk '{print $1}')"
postgres_jwt_md5="$(docker compose exec -T db psql -X -U postgres -d postgres -Atqc "SELECT md5(current_setting('app.settings.jwt_secret'))")"
target_jwt_md5="$(docker compose exec -T db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc "SELECT md5(current_setting('app.settings.jwt_secret'))")"
[[ "$postgres_jwt_md5" == "$new_jwt_md5" && "$target_jwt_md5" == "$new_jwt_md5" ]] ||
  fail "database JWT settings do not match the rotated secret"

public_hostname="$(sed -n 's/^FESTAPP_SUPABASE_HOSTNAME=//p' .env)"
[[ "$public_hostname" =~ ^[a-z0-9.-]+$ ]] || fail "invalid public hostname"
api_origin="https://$public_hostname"
new_anon="$(<"$NEW_ANON")"
old_anon="$(<"$OLD_ANON")"
new_service="$(<"$NEW_SERVICE")"
old_service="$(<"$OLD_SERVICE")"
new_auth_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $new_anon" "$api_origin/auth/v1/settings")"
new_rest_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $new_anon" -H "Authorization: Bearer $new_anon" "$api_origin/rest/v1/organizations?select=id&limit=1")"
old_auth_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $old_anon" "$api_origin/auth/v1/settings")"
new_service_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $new_service" -H "Authorization: Bearer $new_service" "$api_origin/rest/v1/organizations?select=id&limit=1")"
old_service_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $old_service" -H "Authorization: Bearer $old_service" "$api_origin/rest/v1/organizations?select=id&limit=1")"
[[ "$new_auth_status" == "200" && "$new_rest_status" == "200" && "$new_service_status" == "200" &&
   "$old_auth_status" == "401" && "$old_service_status" == "401" ]] ||
  fail "public credential canary failed (new auth=$new_auth_status new rest=$new_rest_status new service=$new_service_status old auth=$old_auth_status old service=$old_service_status)"

install -o root -g root -m 0600 "$NEW_ANON" "$RUN_DIR/anon-key.txt"
jq -n \
  --arg run_id "$RUN_ID" \
  --arg database "$TARGET_DATABASE" \
  --arg anon_sha256 "$(sha256sum "$NEW_ANON" | awk '{print $1}')" \
  --arg service_sha256 "$(sha256sum "$NEW_SERVICE" | awk '{print $1}')" \
  --arg postgres_sha256 "$(printf '%s' "$new_password" | sha256sum | awk '{print $1}')" \
  --arg old_anon_status "$old_auth_status" \
  --arg old_service_status "$old_service_status" \
  --arg new_auth_status "$new_auth_status" \
  --arg new_rest_status "$new_rest_status" \
  '{run_id:$run_id,database:$database,credentials_rotated:["POSTGRES_PASSWORD","JWT_SECRET","ANON_KEY","SERVICE_ROLE_KEY"],unrelated_persistent_secrets_rotated:false,anon_key_sha256:$anon_sha256,service_role_key_sha256:$service_sha256,postgres_password_sha256:$postgres_sha256,old_anon_http_status:($old_anon_status|tonumber),old_service_role_http_status:($old_service_status|tonumber),new_auth_http_status:($new_auth_status|tonumber),new_rest_http_status:($new_rest_status|tonumber),database_logins_verified:7,database_jwt_settings_verified:2,services_healthy:true,secret_credentials_in_evidence:false,public_anon_key_file:"anon-key.txt",production_target_mutated:false,deleted_paths:[]}' \
  >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"

trap - EXIT
cleanup
echo "Rehearsal runtime credentials rotated; old anon key rejected and all services are healthy."
echo "Evidence: $RUN_DIR"
