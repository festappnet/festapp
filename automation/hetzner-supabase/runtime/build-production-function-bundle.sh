#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly POLICY="$PROJECT_ROOT/automation/hetzner-supabase/merge/runtime-writer-policy.json"
readonly SOURCE_ROOT="$PROJECT_ROOT/supabase/functions"
readonly OUTPUT_ROOT="${FESTAPP_FUNCTION_BUNDLE_OUTPUT_DIR:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_FUNCTION_BUNDLE_ACK:-}" == "build-reviewed-production-function-bundle" ]] ||
  fail "set FESTAPP_FUNCTION_BUNDLE_ACK=build-reviewed-production-function-bundle"
[[ "$OUTPUT_ROOT" == /* && "$OUTPUT_ROOT" != "/" ]] ||
  fail "FESTAPP_FUNCTION_BUNDLE_OUTPUT_DIR must be a bounded absolute directory"
case "$OUTPUT_ROOT/" in "$PROJECT_ROOT/"*) fail "bundle output must be outside the repository";; esac
[[ "$(git -C "$PROJECT_ROOT" branch --show-current)" == "main" &&
   "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" == "$(git -C "$PROJECT_ROOT" rev-parse origin/main)" &&
   -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] ||
  fail "production Function bundle requires clean synchronized main"

readonly SOURCE_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
readonly BUNDLE_ID="${SOURCE_SHA:0:12}-$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$OUTPUT_ROOT/$BUNDLE_ID"
readonly STAGE="$RUN_DIR/functions"
[[ ! -e "$RUN_DIR" ]] || fail "bundle output already exists"
install -d -m 0700 "$STAGE"

mapfile_compat() {
  while IFS= read -r line; do FUNCTION_NAMES[${#FUNCTION_NAMES[@]}]="$line"; done
}
FUNCTION_NAMES=()
mapfile_compat < <(jq -r '(.canonical_function_security.excluded|keys) as $excluded |
  .edge_functions|keys[]|select(. as $name | ($excluded|index($name)|not))' "$POLICY" | sort)
FUNCTION_NAMES+=("_shared")
for name in "${FUNCTION_NAMES[@]}"; do [[ -d "$SOURCE_ROOT/$name" ]] || fail "missing source Function: $name"; done

COPYFILE_DISABLE=1 tar -C "$SOURCE_ROOT" -cf - "${FUNCTION_NAMES[@]}" | tar -C "$STAGE" -xf -
[[ -z "$(find "$STAGE" -type l -print -quit)" ]] || fail "Function bundle must not contain symlinks"
readonly ARCHIVE="$RUN_DIR/functions.tar.gz"
COPYFILE_DISABLE=1 tar -C "$STAGE" -czf "$ARCHIVE" .
chmod 0600 "$ARCHIVE"
readonly ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
readonly POLICY_SHA256="$(shasum -a 256 "$POLICY" | awk '{print $1}')"

jq -n --arg bundle_id "$BUNDLE_ID" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg source_sha "$SOURCE_SHA" --arg archive_file "$(basename "$ARCHIVE")" \
  --arg archive_sha256 "$ARCHIVE_SHA256" --arg policy_sha256 "$POLICY_SHA256" \
  --argjson functions "$(printf '%s\n' "${FUNCTION_NAMES[@]}" | sort | jq -R . | jq -s .)" \
  '{version:1,bundle_id:$bundle_id,created_at:$created_at,source_sha:$source_sha,
    archive:{file:$archive_file,sha256:$archive_sha256},runtime_writer_policy_sha256:$policy_sha256,
    packaged_directories:$functions,host_router_directory:"main",excluded_directories:["hello","instance-install"]}' \
  >"$RUN_DIR/manifest.json"
chmod 0600 "$RUN_DIR/manifest.json"
rm -rf "$STAGE"
echo "Production Function bundle created without deployment: $RUN_DIR"
