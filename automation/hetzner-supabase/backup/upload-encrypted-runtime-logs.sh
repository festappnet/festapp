#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_LOG_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly CONFIG_FILE="${FESTAPP_LOG_CONFIG:-/etc/festapp-backup/r2.env}"
readonly LOG_ROOT="${FESTAPP_LOG_ROOT:-/var/backups/festapp-supabase-logs}"
readonly EVIDENCE_ROOT="${FESTAPP_LOG_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly RETENTION_DAYS="${FESTAPP_LOG_RETENTION_DAYS:-30}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ -f "$CONFIG_FILE" && "$(stat -c '%U:%G' "$CONFIG_FILE")" == "root:root" &&
   "$(stat -c '%a' "$CONFIG_FILE")" == "600" ]] || fail "log archive config must be root-owned mode 0600"
for dependency in age docker flock jq rclone sha256sum; do
  command -v "$dependency" >/dev/null || fail "$dependency is required"
done
# shellcheck disable=SC1090
set -a; source "$CONFIG_FILE"; set +a
for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY R2_BUCKET R2_ENDPOINT AGE_RECIPIENT; do
  [[ -n "${!name:-}" ]] || fail "$name is missing from the log archive config"
done
[[ "$R2_BUCKET" == "festapp-supabase-backups" && "$AGE_RECIPIENT" == age1* ]] ||
  fail "unexpected log archive destination or recipient"

install -d -o root -g root -m 0700 "$LOG_ROOT"
exec 9>"$LOG_ROOT/.lock"
flock -n 9 || fail "another log archive is active"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly DAY="${RUN_ID:0:8}"
readonly ARTIFACT="$LOG_ROOT/runtime-logs-$RUN_ID.txt.age"
readonly RCLONE_CONFIG="/run/festapp-log-rclone-$RUN_ID.conf"
cleanup() { shred -u "$RCLONE_CONFIG" 2>/dev/null || true; }
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

cd "$COMPOSE_DIR"
mapfile -t CONTAINERS < <(docker compose ps --format json | jq -r .Name | LC_ALL=C sort)
[[ "${#CONTAINERS[@]}" -ge 10 ]] || fail "runtime container inventory is incomplete"
{
  printf 'festapp encrypted runtime log archive v1\nrun_id=%s\nhost=%s\n' "$RUN_ID" "$EXPECTED_HOSTNAME"
  for container in "${CONTAINERS[@]}"; do
    printf '\n===== container:%s =====\n' "$container"
    docker logs --timestamps --since 70m "$container" 2>&1 || printf 'log-read-failed\n'
  done
  printf '\n===== systemd:docker =====\n'
  journalctl --no-pager --utc --since '70 minutes ago' -u docker.service 2>&1 || printf 'journal-read-failed\n'
} | age -r "$AGE_RECIPIENT" -o "$ARTIFACT"
[[ -s "$ARTIFACT" ]] || fail "encrypted log artifact is empty"
readonly SHA256="$(sha256sum "$ARTIFACT" | awk '{print $1}')"
readonly REMOTE="r2:$R2_BUCKET/logs/$EXPECTED_HOSTNAME/$DAY/$RUN_ID"
rclone --config "$RCLONE_CONFIG" copyto "$ARTIFACT" "$REMOTE/runtime-logs.txt.age" --immutable --retries 3
[[ "$(rclone --config "$RCLONE_CONFIG" size "$REMOTE" --json | jq -r .bytes)" == \
  "$(stat -c %s "$ARTIFACT")" ]] ||
  fail "off-host log artifact size mismatch"
rclone --config "$RCLONE_CONFIG" delete "r2:$R2_BUCKET/logs/$EXPECTED_HOSTNAME" \
  --min-age "${RETENTION_DAYS}d" --rmdirs
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT/runtime-log-upload-$RUN_ID"
jq -n --arg run_id "$RUN_ID" --arg uploaded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sha256 "$SHA256" --arg remote_prefix "logs/$EXPECTED_HOSTNAME/$DAY/$RUN_ID" \
  --argjson containers "${#CONTAINERS[@]}" \
  '{version:1,run_id:$run_id,uploaded_at:$uploaded_at,encrypted:true,plaintext_artifacts_written:false,
    container_count:$containers,sha256:$sha256,remote_prefix:$remote_prefix,off_host_verified:true,
    production_cutover_authorized:false}' >"$EVIDENCE_ROOT/runtime-log-upload-$RUN_ID/result.json"
find "$LOG_ROOT" -mindepth 1 -maxdepth 1 -type f -mtime +1 -delete
echo "Encrypted runtime logs uploaded and verified: $RUN_ID"
