#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_REGISTRY="${FESTAPP_RUNTIME_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly REFERENCE_REGISTRY="${FESTAPP_RUNTIME_REFERENCE_REGISTRY:-$SCRIPT_DIR/../merge/reference-registry.json}"
readonly RUNTIME_WRITER_POLICY="${FESTAPP_RUNTIME_WRITER_POLICY:-$SCRIPT_DIR/../merge/runtime-writer-policy.json}"

fail() { echo "ERROR: $*" >&2; exit 1; }
readonly ACK="${FESTAPP_RUNTIME_UPGRADE_ACK:-}"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ -d "$COMPOSE_DIR" && -f "$COMPOSE_DIR/.env" ]] || fail "installed runtime is missing"
[[ -f "$SOURCE_REGISTRY" && -f "$REFERENCE_REGISTRY" && -f "$RUNTIME_WRITER_POLICY" ]] ||
  fail "repository registries or runtime writer policy are missing"
command -v flock >/dev/null || fail "flock is required"
command -v node >/dev/null || fail "node is required"

exec 9>"$COMPOSE_DIR/.festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime upgrade or promotion is active"

readonly SOURCE_INSTALLED="$COMPOSE_DIR/festapp-source-registry.json"
readonly REFERENCE_INSTALLED="$COMPOSE_DIR/festapp-reference-registry.json"
readonly REGISTRY_PRESENCE="$([[ -e "$SOURCE_INSTALLED" ]] && printf 1 || printf 0)$([[ -e "$REFERENCE_INSTALLED" ]] && printf 1 || printf 0)"
case "$REGISTRY_PRESENCE" in
  00)
    [[ "$ACK" == "bootstrap-missing-production-runtime-registries" ]] ||
      fail "both registries are absent; set FESTAPP_RUNTIME_UPGRADE_ACK=bootstrap-missing-production-runtime-registries"
    readonly BOOTSTRAP_ARGUMENT="--allow-bootstrap"
    ;;
  11)
    [[ "$ACK" == "upgrade-installed-production-runtime-additively" ]] ||
      fail "set FESTAPP_RUNTIME_UPGRADE_ACK=upgrade-installed-production-runtime-additively"
    readonly BOOTSTRAP_ARGUMENT=""
    for registry in "$SOURCE_INSTALLED" "$REFERENCE_INSTALLED"; do
      [[ -f "$registry" && "$(stat -c '%U:%G' "$registry")" == "root:root" ]] ||
        fail "installed registry must be a root-owned regular file"
      [[ "$(stat -c '%a' "$registry")" == "444" || "$(stat -c '%a' "$registry")" == "644" ]] ||
        fail "installed registry has unsafe permissions"
    done
    ;;
  *) fail "installed registries are in a forbidden partial state" ;;
esac

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/production-runtime-upgrade-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

node "$SCRIPT_DIR/install-runtime-registries.mjs" \
  --candidate-source="$SOURCE_REGISTRY" \
  --candidate-reference="$REFERENCE_REGISTRY" \
  --installed-source="$SOURCE_INSTALLED" \
  --installed-reference="$REFERENCE_INSTALLED" \
  ${BOOTSTRAP_ARGUMENT:+"$BOOTSTRAP_ARGUMENT"} \
  >"$RUN_DIR/registry-result.json"
chown root:root "$SOURCE_INSTALLED" "$REFERENCE_INSTALLED"
chmod 0444 "$SOURCE_INSTALLED" "$REFERENCE_INSTALLED"

install_runtime_file() {
  local source="$1" target="$2" mode="${3:-0700}"
  [[ "$(realpath "$source")" == "$(realpath -m "$target")" ]] ||
    install -o root -g root -m "$mode" "$source" "$target"
}
install_runtime_file "$SCRIPT_DIR/install-runtime-registries.mjs" "$COMPOSE_DIR/install-runtime-registries.mjs"
install_runtime_file "$SCRIPT_DIR/validate-production-promotion.mjs" "$COMPOSE_DIR/validate-production-promotion.mjs"
install_runtime_file "$SCRIPT_DIR/promote-production-runtime.sh" "$COMPOSE_DIR/promote-production-runtime.sh"
install_runtime_file "$SCRIPT_DIR/set-production-target-write-barrier.sh" "$COMPOSE_DIR/set-production-target-write-barrier.sh"
install_runtime_file "$SCRIPT_DIR/validate-operational-readiness.mjs" "$COMPOSE_DIR/validate-operational-readiness.mjs"
install_runtime_file "$SCRIPT_DIR/install-production-function-bundle.sh" "$COMPOSE_DIR/install-production-function-bundle.sh"
install_runtime_file "$SCRIPT_DIR/upgrade-installed-production-runtime.sh" "$COMPOSE_DIR/upgrade-installed-production-runtime.sh"
install_runtime_file "$SCRIPT_DIR/switch-rehearsal-runtime-database.sh" "$COMPOSE_DIR/switch-rehearsal-runtime-database.sh"
install_runtime_file "$SCRIPT_DIR/docker-compose.database-target.yml" "$COMPOSE_DIR/docker-compose.database-target.yml" 0644
install_runtime_file "$RUNTIME_WRITER_POLICY" "$COMPOSE_DIR/festapp-runtime-writer-policy.json" 0444

readonly EXPECTED_SOURCE_SHA="$(node "$SCRIPT_DIR/validate-production-promotion.mjs" --digest-json="$SOURCE_REGISTRY")"
readonly EXPECTED_REFERENCE_SHA="$(node "$SCRIPT_DIR/validate-production-promotion.mjs" --digest-json="$REFERENCE_REGISTRY")"
readonly INSTALLED_STATE="$(printf '%s|%s' \
  "$(node "$SCRIPT_DIR/validate-production-promotion.mjs" --digest-json="$SOURCE_INSTALLED")" \
  "$(node "$SCRIPT_DIR/validate-production-promotion.mjs" --digest-json="$REFERENCE_INSTALLED")")"
[[ "$INSTALLED_STATE" == "$EXPECTED_SOURCE_SHA|$EXPECTED_REFERENCE_SHA" ]] ||
  fail "installed registry checksums do not match the repository"
for dependency in install-runtime-registries.mjs validate-production-promotion.mjs \
  promote-production-runtime.sh upgrade-installed-production-runtime.sh \
  set-production-target-write-barrier.sh validate-operational-readiness.mjs \
  install-production-function-bundle.sh \
  switch-rehearsal-runtime-database.sh docker-compose.database-target.yml; do
  [[ "$(sha256sum "$COMPOSE_DIR/$dependency" | awk '{print $1}')" == \
     "$(sha256sum "$SCRIPT_DIR/$dependency" | awk '{print $1}')" ]] ||
    fail "installed runtime dependency mismatch: $dependency"
done
[[ "$(sha256sum "$COMPOSE_DIR/festapp-runtime-writer-policy.json" | awk '{print $1}')" == \
   "$(sha256sum "$RUNTIME_WRITER_POLICY" | awk '{print $1}')" ]] ||
  fail "installed runtime writer policy mismatch"

jq --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg source_sha256 "$EXPECTED_SOURCE_SHA" --arg reference_sha256 "$EXPECTED_REFERENCE_SHA" \
  '. + {installed_at:$installed_at,source_registry_sha256:$source_sha256,
    reference_registry_sha256:$reference_sha256,production_mutated:false}' \
  "$RUN_DIR/registry-result.json" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/registry-result.json" "$RUN_DIR/result.json"
echo "Installed production runtime contracts are current and immutable."
echo "Evidence: $RUN_DIR"
