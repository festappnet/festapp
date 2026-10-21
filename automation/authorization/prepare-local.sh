#!/usr/bin/env bash
# Task-owned database only. No .env.local or production target resolution.
set -euo pipefail
AUTHZ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTHZ_WORKDIR="${FESTAPP_AUTHORIZATION_WORKDIR:-/tmp/festapp-authz-local-20261020}"
AUTHZ_PROJECT=festapp-authz-20261020
AUTHZ_PORT=61022
AUTHZ_URL="postgresql://supabase_admin:postgres@127.0.0.1:${AUTHZ_PORT}/postgres"
assert_ready() {
  [[ "$(psql "$AUTHZ_URL" -Atqc 'select project from festapp_test_support.disposable_environment')" == "$AUTHZ_PROJECT" ]] || return 1
  [[ "$(psql "$AUTHZ_URL" -Atqc 'show cron.launch_active_jobs')" == off ]] || return 1
  [[ "$(psql "$AUTHZ_URL" -Atqc 'select bool_and(paused AND worker_url IS NULL) from email_capacity')" == t ]] || return 1
}
if pg_isready -h 127.0.0.1 -p "$AUTHZ_PORT" >/dev/null 2>&1; then
  assert_ready || { echo 'Refusing an unowned or unfenced database on the task port' >&2; exit 1; }
  echo 'Task-owned authorization database is ready on localhost:61022'
  exit 0
fi
mkdir -p "$AUTHZ_WORKDIR/supabase"
if [[ -f "$AUTHZ_WORKDIR/supabase/config.toml" ]]; then
  rg -q '^project_id = "festapp-authz-20261020"$' "$AUTHZ_WORKDIR/supabase/config.toml" || {
    echo 'Refusing a workdir owned by another project' >&2; exit 1;
  }
else
  cat > "$AUTHZ_WORKDIR/supabase/config.toml" <<'TOML'
project_id = "festapp-authz-20261020"
[db]
port = 61022
shadow_port = 61020
major_version = 15
[db.seed]
enabled = false
TOML
fi
cd "$AUTHZ_ROOT"
supabase db start --workdir "$AUTHZ_WORKDIR" >/dev/null
# A stopped task database can resume; no existing schema is ever overwritten.
if [[ "$(psql "$AUTHZ_URL" -Atqc "select to_regclass('festapp_test_support.disposable_environment') is not null")" == t ]]; then
  assert_ready
  echo 'Task-owned authorization database resumed on localhost:61022'
  exit 0
fi
[[ "$(psql "$AUTHZ_URL" -Atqc "select to_regclass('public.organizations') is null")" == t ]] || {
  echo 'Refusing to restore over an existing unmarked schema' >&2; exit 1;
}
psql "$AUTHZ_URL" -v ON_ERROR_STOP=1 -c 'ALTER SYSTEM SET cron.launch_active_jobs=off' -c 'select pg_reload_conf()' >/dev/null
[[ "$(psql "$AUTHZ_URL" -Atqc 'show cron.launch_active_jobs')" == off ]]
AUTHZ_BOOTSTRAP="$(mktemp /tmp/festapp-authz-bootstrap.XXXXXX)"
trap 'rm -f "$AUTHZ_BOOTSTRAP"' EXIT
# Reuse the canonical baseline/migration/seed procedure. Its destructive restart
# is omitted only after verifying this newly created empty task DB and fence.
python3 - "$AUTHZ_ROOT" "$AUTHZ_BOOTSTRAP" <<'PY'
from pathlib import Path
import shlex
import sys
root=Path(sys.argv[1]);text=(root/'automation/bootstrap_local_db.sh').read_text()
replacements={
 'readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"':'readonly SCRIPT_DIR='+shlex.quote(str(root/'automation')),
 'supabase stop --project-id "$LOCAL_PROJECT_ID" --no-backup >/dev/null 2>&1 || true':'true # already verified newly-created empty task DB',
 'supabase db start --workdir "$LOCAL_WORKDIR" >/dev/null':'true # cron was disabled before the first schema restore',
}
for old,new in replacements.items():
    if text.count(old)!=1:raise SystemExit('Canonical bootstrap changed; inspect before restoring')
    text=text.replace(old,new)
Path(sys.argv[2]).write_text(text)
PY
FESTAPP_LOCAL_DB_WORKDIR="$AUTHZ_WORKDIR" FESTAPP_LOCAL_DB_PROJECT_ID="$AUTHZ_PROJECT" \
  FESTAPP_LOCAL_DB_PORT="$AUTHZ_PORT" bash "$AUTHZ_BOOTSTRAP" >/dev/null
psql "$AUTHZ_URL" -v ON_ERROR_STOP=1 -c 'update email_capacity set paused=true,worker_url=null' >/dev/null
assert_ready
echo 'Task-owned authorization database prepared with cron and email delivery disabled'
