#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"
readonly ACTION="${1:-}"
readonly WRITER_SERVICES=(auth rest realtime storage meta functions studio)

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "$ACTION" == "close" || "$ACTION" == "open" ]] || fail "usage: $0 close|open"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "FESTAPP_RUNTIME_DATABASE must be the exact timestamped promotion target"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime upgrade, promotion or write-authority change is active"

psql_control() {
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

restart_target_sessions() {
  local runtime_database
  runtime_database="$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)"
  if [[ "$runtime_database" == "$TARGET_DATABASE" ]]; then
    docker compose up -d --force-recreate "${WRITER_SERVICES[@]}" >/dev/null
  fi
}

verify_barrier() {
  docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres \
    -d "$TARGET_DATABASE" -Atqc 'SHOW default_transaction_read_only'
}

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly CHANGE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/production-write-barrier-$ACTION-$CHANGE_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"

case "$ACTION" in
  close)
    [[ "${FESTAPP_WRITE_BARRIER_ACK:-}" == "close-target-writes-before-production-promotion" ]] ||
      fail "set FESTAPP_WRITE_BARRIER_ACK=close-target-writes-before-production-promotion"
    psql_control -c "ALTER DATABASE \"$TARGET_DATABASE\" SET default_transaction_read_only = on" >/dev/null
    psql_control -Atqc "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$TARGET_DATABASE' AND pid<>pg_backend_pid()" >/dev/null
    restart_target_sessions
    [[ "$(verify_barrier)" == "on" ]] || fail "target write barrier did not close"
    ;;
  open)
    [[ "${FESTAPP_WRITE_BARRIER_ACK:-}" == "open-canonical-writes-after-final-go-no-go" ]] ||
      fail "set FESTAPP_WRITE_BARRIER_ACK=open-canonical-writes-after-final-go-no-go"
    readonly PROMOTION_RESULT="${FESTAPP_PRODUCTION_PROMOTION_RESULT:-}"
    readonly FINAL_MARKER="${FESTAPP_FINAL_MARKER_DECISION:-}"
    for evidence in "$PROMOTION_RESULT" "$FINAL_MARKER"; do
      [[ "$evidence" == /* && -f "$evidence" && "$(stat -c '%a' "$evidence")" == "600" ]] ||
        fail "open requires absolute mode-0600 promotion and final-marker evidence"
    done
    [[ "$(jq -r '[.target_database,.external_write_authority_opened,.target_write_barrier]|join("|")' "$PROMOTION_RESULT")" == \
      "$TARGET_DATABASE|false|database-default-read-only" ]] || fail "promotion result does not authorize this target"
    [[ "$(jq -r .target_database "$FINAL_MARKER")" == "$TARGET_DATABASE" ]] ||
      fail "final marker does not bind this target"
    [[ "$(date -u +%s)" -le "$(date -u -d "$(jq -r .authorized_until "$FINAL_MARKER")" +%s)" ]] ||
      fail "final-marker promotion authorization has expired"
    [[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] ||
      fail "production runtime is not promoted to the target database"
    [[ "$(verify_barrier)" == "on" ]] || fail "target write barrier was not closed before opening"
    psql_control -c "ALTER DATABASE \"$TARGET_DATABASE\" RESET default_transaction_read_only" >/dev/null
    psql_control -Atqc "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$TARGET_DATABASE' AND pid<>pg_backend_pid()" >/dev/null
    restart_target_sessions
    [[ "$(verify_barrier)" == "off" ]] || fail "target write barrier did not open"
    ;;
esac

jq -n --arg changed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg action "$ACTION" \
  --arg target_database "$TARGET_DATABASE" \
  --arg observed "$([[ "$ACTION" == "close" ]] && printf on || printf off)" \
  '{version:1,changed_at:$changed_at,action:$action,target_database:$target_database,
    default_transaction_read_only:$observed,client_activation_mutated:false,
    cloud_write_authority_mutated:false,deleted_paths:[]}' >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Canonical target write barrier action passed: action=$ACTION database=$TARGET_DATABASE"
echo "Evidence: $RUN_DIR/result.json"
