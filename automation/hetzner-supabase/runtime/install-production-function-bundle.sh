#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly MANIFEST="${FESTAPP_FUNCTION_BUNDLE_MANIFEST:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_FUNCTION_BUNDLE_INSTALL_ACK:-}" == "stage-verified-function-bundle-without-restarting-runtime" ]] ||
  fail "set FESTAPP_FUNCTION_BUNDLE_INSTALL_ACK=stage-verified-function-bundle-without-restarting-runtime"
[[ "$(id -u)" == "0" && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"
[[ "$MANIFEST" == /* && -f "$MANIFEST" && "$(stat -c '%a' "$MANIFEST")" == "600" ]] ||
  fail "FESTAPP_FUNCTION_BUNDLE_MANIFEST must be an absolute mode-0600 file"
readonly ARTIFACT="$(dirname "$MANIFEST")/$(jq -r .archive.file "$MANIFEST")"
[[ "$(jq -r '[.version,(.source_sha|test("^[0-9a-f]{40}$")),.host_router_directory,
  (.excluded_directories|sort|join(","))]|join("|")' "$MANIFEST")" ==
  "1|true|main|hello,instance-install" ]] || fail "Function bundle manifest contract is invalid"
[[ -f "$ARTIFACT" && "$(sha256sum "$ARTIFACT" | awk '{print $1}')" ==
  "$(jq -r .archive.sha256 "$MANIFEST")" ]] || fail "Function bundle artifact digest mismatch"

cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime upgrade, promotion or bundle install is active"
[[ -f festapp-runtime-writer-policy.json && "$(sha256sum festapp-runtime-writer-policy.json | awk '{print $1}')" ==
  "$(jq -r .runtime_writer_policy_sha256 "$MANIFEST")" ]] || fail "installed writer policy mismatch"
[[ -d volumes/functions/main && -f volumes/functions/main/index.ts ]] || fail "upstream Function router is missing"
if tar -tzf "$ARTIFACT" | awk '/^\// || /(^|\/)\.\.($|\/)/ {unsafe=1} END {exit !unsafe}'; then
  fail "Function bundle contains an unsafe path"
fi
if tar -tvzf "$ARTIFACT" | awk 'substr($1,1,1) ~ /[lh]/ {unsafe=1} END {exit !unsafe}'; then
  fail "Function bundle contains a link entry"
fi

readonly INSTALL_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly STAGE="volumes/functions.stage-$INSTALL_ID"
readonly PREVIOUS="volumes/functions.pre-production-$INSTALL_ID"
[[ ! -e "$STAGE" && ! -e "$PREVIOUS" ]] || fail "Function staging path already exists"
install -d -o root -g root -m 0755 "$STAGE"
tar --no-same-owner --no-same-permissions -C "$STAGE" -xzf "$ARTIFACT"
cp -a volumes/functions/main "$STAGE/main"
[[ -z "$(find "$STAGE" -type l -print -quit)" ]] || fail "Function bundle contains symlinks"

mapfile -t EXPECTED < <({ printf '%s\n' _shared main; jq -r '
  (.canonical_function_security.excluded|keys) as $excluded |
  .edge_functions|keys[]|select(. as $name | ($excluded|index($name)|not))
' festapp-runtime-writer-policy.json; } | sort)
mapfile -t ACTUAL < <(find "$STAGE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ "${EXPECTED[*]}" == "${ACTUAL[*]}" ]] || fail "staged Function directory set is not canonical"
readonly BUNDLE_SHA256="$(cd "$STAGE" &&
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"

mv volumes/functions "$PREVIOUS"
restore_previous() {
  [[ -e volumes/functions ]] || mv "$PREVIOUS" volumes/functions
}
trap restore_previous ERR
mv "$STAGE" volumes/functions
chown -R root:root volumes/functions
find volumes/functions -type d -exec chmod 0755 {} +
find volumes/functions -type f -exec chmod 0644 {} +
trap - ERR
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/production-function-bundle-$INSTALL_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"
jq --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg function_bundle_sha256 "$BUNDLE_SHA256" \
  --arg previous_directory "$COMPOSE_DIR/$PREVIOUS" \
  '. + {installed_at:$installed_at,function_bundle_sha256:$function_bundle_sha256,
    previous_directory:$previous_directory,runtime_restarted:false,client_activation_mutated:false,
    external_write_authority_opened:false,deleted_paths:[]}' "$MANIFEST" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Verified Function bundle staged without runtime restart."
echo "Evidence: $RUN_DIR/result.json"
