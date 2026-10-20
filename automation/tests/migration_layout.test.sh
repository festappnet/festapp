#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly MIGRATIONS_DIR="$PROJECT_ROOT/supabase/migrations"
readonly BOOTSTRAP="$PROJECT_ROOT/automation/bootstrap_local_db.sh"

invalid_names="$({
  find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \;
} | awk '!/^[0-9]{14}_[A-Za-z0-9_][A-Za-z0-9_.-]*\.sql$/')"
if [[ -n "$invalid_names" ]]; then
  echo "Active migrations with invalid Supabase filenames:" >&2
  echo "$invalid_names" >&2
  exit 1
fi

duplicate_versions="$({
  find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -exec basename {} \;
} | awk -F_ '{ count[$1]++ } END { for (version in count) if (count[version] > 1) print version }' | sort)"
if [[ -n "$duplicate_versions" ]]; then
  echo "Duplicate active migration versions:" >&2
  echo "$duplicate_versions" >&2
  exit 1
fi

baseline_version="$(sed -n 's/.*BASELINE_VERSION="\([0-9]\{14\}\)".*/\1/p' "$BOOTSTRAP")"
baseline_file="$PROJECT_ROOT/supabase/baseline/${baseline_version}_production_schema.sql"
if [[ -z "$baseline_version" || ! -f "$baseline_file" ]]; then
  echo "Bootstrap baseline version does not resolve to a schema file." >&2
  exit 1
fi

if grep -Eq '^(COPY|INSERT INTO)[[:space:]]' "$baseline_file"; then
  echo "Schema baseline contains data statements." >&2
  exit 1
fi

echo "Migration layout contract passed."
