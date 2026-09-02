#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_BACKUP_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly CONFIG_FILE="${FESTAPP_BACKUP_CONFIG:-/etc/festapp-backup/r2.env}"
readonly BACKUP_ROOT="${FESTAPP_BACKUP_ROOT:-/var/backups/festapp-supabase}"
readonly EVIDENCE_ROOT="${FESTAPP_BACKUP_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly RETENTION_DAYS="${FESTAPP_BACKUP_RETENTION_DAYS:-30}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ -f "$CONFIG_FILE" && "$(stat -c '%U:%G' "$CONFIG_FILE")" == "root:root" &&
   "$(stat -c '%a' "$CONFIG_FILE")" == "600" ]] || fail "backup config must be root-owned mode 0600"
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ && "$RETENTION_DAYS" -ge 7 ]] || fail "retention must be at least 7 days"
for dependency in age docker flock jq rclone sha256sum tar; do
  command -v "$dependency" >/dev/null || fail "$dependency is required"
done

# This file is root-only and contains simple generated KEY=value values.
# shellcheck disable=SC1090
set -a; source "$CONFIG_FILE"; set +a
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY R2_ACCOUNT_ID R2_BUCKET R2_ENDPOINT AGE_RECIPIENT; do
  [[ -n "${!name:-}" ]] || fail "$name is missing from the backup config"
done
[[ "$AGE_RECIPIENT" == age1* ]] || fail "AGE_RECIPIENT is invalid"
[[ "$R2_BUCKET" == "festapp-supabase-backups" ]] || fail "unexpected backup bucket"

install -d -o root -g root -m 0700 "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.lock"
flock -n 9 || fail "another scheduled backup is active"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$BACKUP_ROOT/$RUN_ID"
readonly EVIDENCE_DIR="$EVIDENCE_ROOT/scheduled-backup-$RUN_ID"
readonly RCLONE_CONFIG="/run/festapp-backup-rclone-$RUN_ID.conf"
[[ ! -e "$RUN_DIR" && ! -e "$EVIDENCE_DIR" ]] || fail "backup run already exists"
install -d -o root -g root -m 0700 "$RUN_DIR" "$EVIDENCE_DIR"
cleanup() { rm -f "$RCLONE_CONFIG"; }
trap cleanup EXIT
umask 077
cat >"$RCLONE_CONFIG" <<EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = $AWS_ACCESS_KEY_ID
secret_access_key = $AWS_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT
no_check_bucket = true
EOF

readonly DATABASE="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' "$COMPOSE_DIR/.env")"
[[ "$DATABASE" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fail "runtime database is invalid"
cd "$COMPOSE_DIR"
docker compose exec -T db pg_dump -U postgres -d "$DATABASE" -Fc |
  age -r "$AGE_RECIPIENT" -o "$RUN_DIR/postgres.dump.age"
docker compose exec -T db pg_dumpall -U postgres --globals-only |
  age -r "$AGE_RECIPIENT" -o "$RUN_DIR/globals.sql.age"
COPYFILE_DISABLE=1 tar -C volumes/storage -cf - . |
  age -r "$AGE_RECIPIENT" -o "$RUN_DIR/storage.tar.age"
COPYFILE_DISABLE=1 tar -C /opt/festapp-supabase -cf - \
  docker/.env docker/docker-compose.yml docker/docker-compose.festapp.yml \
  docker/docker-compose.database-target.yml docker/caddy/Caddyfile docker/volumes/functions \
  docker/volumes/proxy | age -r "$AGE_RECIPIENT" -o "$RUN_DIR/runtime.tar.age"

artifacts='{}'
for file in postgres.dump.age globals.sql.age storage.tar.age runtime.tar.age; do
  [[ -s "$RUN_DIR/$file" ]] || fail "empty encrypted artifact: $file"
  artifacts="$(jq -c --arg name "$file" --arg sha "$(sha256sum "$RUN_DIR/$file" | awk '{print $1}')" \
    --argjson bytes "$(stat -c %s "$RUN_DIR/$file")" '. + {($name):{sha256:$sha,bytes:$bytes}}' <<<"$artifacts")"
done
jq -n --arg run_id "$RUN_ID" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg source_host "$EXPECTED_HOSTNAME" --arg source_database "$DATABASE" \
  --arg bucket "$R2_BUCKET" --arg prefix "backups/$EXPECTED_HOSTNAME/$RUN_ID" \
  --argjson retention_days "$RETENTION_DAYS" --argjson artifacts "$artifacts" \
  '{version:1,run_id:$run_id,created_at:$created_at,source_host:$source_host,
    source_database:$source_database,encrypted:true,plaintext_artifacts_written:false,
    consistency:"online-operational-backup-not-promotion-rpo0",destination:{provider:"cloudflare-r2",
    bucket:$bucket,prefix:$prefix,independent_failure_domain:true},retention_days:$retention_days,
    artifacts:$artifacts}' >"$RUN_DIR/manifest.json"

readonly REMOTE="r2:$R2_BUCKET/backups/$EXPECTED_HOSTNAME/$RUN_ID"
rclone --config "$RCLONE_CONFIG" copy "$RUN_DIR" "$REMOTE" --immutable --retries 3
rclone --config "$RCLONE_CONFIG" check "$RUN_DIR" "$REMOTE" --size-only --one-way
rclone --config "$RCLONE_CONFIG" delete "r2:$R2_BUCKET/backups/$EXPECTED_HOSTNAME" \
  --min-age "${RETENTION_DAYS}d" --rmdirs
jq --arg uploaded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '. + {uploaded_at:$uploaded_at,off_host_verified:true,production_cutover_authorized:false}' \
  "$RUN_DIR/manifest.json" >"$EVIDENCE_DIR/result.json"
chmod 0600 "$RUN_DIR"/* "$EVIDENCE_DIR/result.json"
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec rm -rf -- {} +
echo "Encrypted online backup uploaded and verified: $RUN_ID"
