#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 BASE_MAIN_SHA TENANT_ID [PROD_TIP]" >&2
  exit 64
}

[[ $# -ge 2 && $# -le 3 ]] || usage
BASE_MAIN_SHA=$1
TENANT_ID=$2
PROD_TIP=${3:-HEAD}
POLICY_ROOT=automation/tenant-overlays
CHECKER_PATH=automation/check_tenant_branch_drift.sh
METADATA_PATH=automation/tenant-overlay.json
SCHEMA_PATH=automation/tenant-overlays/tenant-overlay.schema.json
VALIDATOR_PATH=automation/validate_json_schema_subset.mjs
CANONICAL_MAIN_REF=${CANONICAL_MAIN_REF:-main}

case "$TENANT_ID" in
  absolventskyvelehrad|aksmcz|cavfotofest|csmostrava2026|doobiscup|farnostopava|festapp|festapptickets|festivalslunovrat|hvezdamorska|jubileum2025) ;;
  *) echo "Error: unsupported tenant ID: $TENANT_ID" >&2; exit 65 ;;
esac

git cat-file -e "${BASE_MAIN_SHA}^{commit}" 2>/dev/null || {
  echo "Error: BASE_MAIN_SHA is not a commit" >&2
  exit 66
}
git cat-file -e "${PROD_TIP}^{commit}" 2>/dev/null || {
  echo "Error: PROD_TIP is not a commit" >&2
  exit 66
}
git merge-base --is-ancestor "$BASE_MAIN_SHA" "$CANONICAL_MAIN_REF" || {
  echo "Error: BASE_MAIN_SHA is not contained in $CANONICAL_MAIN_REF" >&2
  exit 67
}
git merge-base --is-ancestor "$BASE_MAIN_SHA" "$PROD_TIP" || {
  echo "Error: production tip does not contain recorded main SHA" >&2
  exit 67
}

TMP_ROOT=$(mktemp -d /tmp/festapp-tenant-replay.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT
CANONICAL_CHECKER="$TMP_ROOT/canonical-checker.sh"
git show "${BASE_MAIN_SHA}:${CHECKER_PATH}" > "$CANONICAL_CHECKER"
cmp -s "$CANONICAL_CHECKER" "$0" || {
  echo "Error: checker is not the version owned by BASE_MAIN_SHA" >&2
  exit 68
}

SOURCE_POLICY="$TMP_ROOT/source.paths"
GENERATED_POLICY="$TMP_ROOT/generated.paths"
CANONICAL_SCHEMA="$TMP_ROOT/tenant-overlay.schema.json"
CANONICAL_VALIDATOR="$TMP_ROOT/validate-json-schema.mjs"
git show "${BASE_MAIN_SHA}:${POLICY_ROOT}/${TENANT_ID}.paths" > "$SOURCE_POLICY"
git show "${BASE_MAIN_SHA}:${POLICY_ROOT}/generated.paths" > "$GENERATED_POLICY"
git show "${BASE_MAIN_SHA}:${SCHEMA_PATH}" > "$CANONICAL_SCHEMA"
git show "${BASE_MAIN_SHA}:${VALIDATOR_PATH}" > "$CANONICAL_VALIDATOR"

SOURCE_PATTERNS=()
while IFS= read -r entry; do
  SOURCE_PATTERNS[${#SOURCE_PATTERNS[@]}]=$entry
done < <(sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$SOURCE_POLICY")
GENERATED_PATHS=()
while IFS= read -r entry; do
  GENERATED_PATHS[${#GENERATED_PATHS[@]}]=$entry
done < <(sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$GENERATED_POLICY")

is_generated() {
  local candidate=$1 entry
  for entry in "${GENERATED_PATHS[@]}"; do
    [[ "$candidate" == "$entry" ]] && return 0
  done
  return 1
}

is_source_overlay() {
  local candidate=$1 pattern
  for pattern in "${SOURCE_PATTERNS[@]}"; do
    # Patterns are trusted policy loaded from BASE_MAIN_SHA, never from PROD_TIP.
    [[ "$candidate" == $pattern ]] && return 0
  done
  return 1
}

metadata=$(git show "${PROD_TIP}:${METADATA_PATH}" 2>/dev/null) || {
  echo "Error: missing $METADATA_PATH in production tip" >&2
  exit 69
}
METADATA_FILE="$TMP_ROOT/tenant-overlay.json"
printf '%s\n' "$metadata" > "$METADATA_FILE"
node "$CANONICAL_VALIDATOR" "$CANONICAL_SCHEMA" "$METADATA_FILE" || {
  echo "Error: tenant overlay metadata does not satisfy the main-owned schema" >&2
  exit 69
}
node -e '
  const value=JSON.parse(process.argv[1]);
  const [tenant,base]=process.argv.slice(2);
  if(value.tenantId!==tenant||value.baseMainSha!==base) process.exit(1);
' "$metadata" "$TENANT_ID" "$BASE_MAIN_SHA" || {
  echo "Error: invalid or mismatched tenant overlay metadata" >&2
  exit 69
}

EXPECTED_TREE="$TMP_ROOT/expected"
mkdir -p "$EXPECTED_TREE"
# Keep the replay byte-identical to repository blobs even when Git for Windows
# has core.autocrlf=true. Generated-file checks are intentionally byte-exact.
git -c core.autocrlf=false archive "$BASE_MAIN_SHA" | tar -x -C "$EXPECTED_TREE"

while IFS= read -r -d '' path; do
  if [[ "$path" == "$METADATA_PATH" ]]; then
    continue
  fi
  if is_generated "$path"; then
    continue
  fi
  is_source_overlay "$path" || {
    echo "Error: forbidden branch drift: $path" >&2
    exit 70
  }
  target="$EXPECTED_TREE/$path"
  if git cat-file -e "${PROD_TIP}:${path}" 2>/dev/null; then
    git -c core.autocrlf=false archive "$PROD_TIP" -- "$path" |
      tar -x -C "$EXPECTED_TREE"
  else
    rm -f "$target"
  fi
done < <(git diff --name-only -z "$BASE_MAIN_SHA" "$PROD_TIP")

(cd "$EXPECTED_TREE" && bash automation/apply_config.sh automation/project.conf >/dev/null)

for path in "${GENERATED_PATHS[@]}"; do
  expected="$EXPECTED_TREE/$path"
  if [[ -e "$expected" ]] && git cat-file -e "${PROD_TIP}:${path}" 2>/dev/null; then
    # Compare Git object IDs instead of redirecting `git show`. Native Git
    # stdout can be CRLF-translated by the Windows shell, which made an exact
    # LF blob (first observed at pubspec.yaml) look dirty on the build host.
    expected_oid=$(git hash-object --no-filters "$expected")
    actual_oid=$(git rev-parse "${PROD_TIP}:${path}")
    [[ "$expected_oid" == "$actual_oid" ]] || {
      echo "Error: generated content drift: $path" >&2
      exit 71
    }
  elif [[ -e "$expected" ]] || git cat-file -e "${PROD_TIP}:${path}" 2>/dev/null; then
    echo "Error: generated path presence mismatch: $path" >&2
    exit 71
  fi
done

echo "Tenant drift check passed: tenant=$TENANT_ID base=$BASE_MAIN_SHA tip=$(git rev-parse "$PROD_TIP")"
