#!/usr/bin/env bash
set -euo pipefail
[[ "${EMAIL_LOCAL_REHEARSAL:-}" == 1 ]] || { echo 'Set EMAIL_LOCAL_REHEARSAL=1 to recreate only the disposable email test project.' >&2;exit 1; }
cd "$(dirname "$0")/../.."
if [[ -z "${FESTAPP_DB_RUN_ID:-}" ]]; then
  export FESTAPP_LOCAL_DB_PROJECT_ID=festapp-email-rehearsal-pg15 FESTAPP_LOCAL_DB_PORT=55434 FESTAPP_TEST_PG_MAJOR=15
  keep=(); [[ "${KEEP_EMAIL_REHEARSAL_DB:-1}" == 1 ]] && keep=(--keep-workspace)
  exec python3 automation/local_db/runtime.py exec --provider-only --exclusive "${keep[@]}" -- bash "$0" "$@"
fi
[[ "${FESTAPP_LOCAL_DB_PROJECT_ID:-}" == festapp-email-rehearsal-pg15 ]] || { echo 'Email rehearsal requires its owned provider-only runtime.' >&2; exit 1; }
readonly email_kit="$(mktemp -d /tmp/festapp-email-history.XXXXXX)"
trap 'rm -rf "$email_kit"' EXIT
python3 automation/baseline.py historical-kit --email "$email_kit" >/dev/null
readonly email_original_baseline="$(python3 -c 'import json; print(json.load(open("automation/historical-sql-manifest.json"))["originalBaseline"])')"
readonly email_original_version="$(python3 -c 'import json; print(json.load(open("automation/historical-sql-manifest.json"))["originalBaselineVersion"])')"
readonly email_main_snapshot="$(python3 -c 'import json; print(json.load(open("automation/historical-sql-manifest.json"))["emailRehearsalSnapshot"])')"
readonly email_database="${DATABASE_URL:?owned provider lease required}"
psql "$email_database" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE SCHEMA IF NOT EXISTS eshop;
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;
-- The canonical self-hosted role lacked this grant even though local defaults
-- supplied it. Migration verification must start with the production ACL.
REVOKE USAGE ON SCHEMA extensions FROM service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON TABLES FROM anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA eshop REVOKE ALL ON FUNCTIONS FROM anon,authenticated,service_role;
SQL
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/$email_original_baseline" >/dev/null
# Main snapshot only. Excludes any unrelated, later pending migration.
while IFS= read -r email_migration;do
 email_version="$(basename "$email_migration")";email_version="${email_version%%_*}"
 if [[ "$email_version" > "$email_original_version" && "$email_version" != 20261003200000 ]];then
  psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/$email_migration" >/dev/null
 fi
done < <(python3 automation/historical_inputs.py list "$email_main_snapshot" supabase/migrations/ | sort)
psql "$email_database" -v ON_ERROR_STOP=1 -q -c 'SELECT cron.unschedule(jobid) FROM cron.job' -f "$email_kit/database/tests/emails/legacy_cutover_fixture.sql" >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/supabase/migrations/20261003200000_canonical_email_delivery.sql" -f "$email_kit/database/tests/emails/legacy_cutover_assertions.sql" >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/supabase/migrations/20261006090000_email_permissions_and_templates.sql" >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/supabase/migrations/20261006100000_email_extensions_schema_owner.sql" >/dev/null
# Install the standard disposable test identities after legacy cutover assertions.
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/supabase/seed.sql" >/dev/null
# Keep migrated fixtures for inspection, ineligible for any real send.
psql "$email_database" -v ON_ERROR_STOP=1 -q -c 'SELECT cron.unschedule(jobid) FROM cron.job' >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/database/tests/emails/readiness_fixture.sql" >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_kit/automation/email-delivery/check-readiness.sql" >/dev/null
echo 'PASS: main + legacy fixture + canonical cutover, paused, IDs/audit preserved, ambiguous sends quarantined.'
