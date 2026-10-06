#!/usr/bin/env bash
set -euo pipefail
[[ "${EMAIL_LOCAL_REHEARSAL:-}" == 1 ]] || { echo 'Set EMAIL_LOCAL_REHEARSAL=1 to recreate only the disposable email test project.' >&2;exit 1; }
cd "$(dirname "$0")/../.."
readonly email_project='festapp-email-tests-pg15'
readonly email_workdir='/tmp/festapp-email-runtime'
readonly email_main_snapshot="${EMAIL_REHEARSAL_MAIN_SHA:-c2c5634f72287a86a1b2f55e58ea63727f53ac0f}"
readonly email_database='postgresql://postgres:postgres@127.0.0.1:55434/postgres'
mkdir -p "$email_workdir/supabase"
sed -e "s/festapp-db-tests-pg15/$email_project/" -e 's/55432/55434/' -e 's/55430/55436/' automation/local_db/supabase/config.toml > "$email_workdir/supabase/config.toml"
supabase stop --project-id "$email_project" --no-backup >/dev/null 2>&1 || true
supabase db start --workdir "$email_workdir" >/dev/null
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
psql "$email_database" -v ON_ERROR_STOP=1 -q -f supabase/baseline/20260805230000_production_schema.sql >/dev/null
# Main snapshot only. Excludes any unrelated, later pending migration.
while IFS= read -r email_migration;do
 email_version="$(basename "$email_migration")";email_version="${email_version%%_*}"
 if [[ "$email_version" > 20260805230000 && "$email_version" != 20261003200000 ]];then
  psql "$email_database" -v ON_ERROR_STOP=1 -q -f "$email_migration" >/dev/null
 fi
done < <(git ls-tree -r --name-only "$email_main_snapshot" supabase/migrations | sort)
psql "$email_database" -v ON_ERROR_STOP=1 -q -c 'SELECT cron.unschedule(jobid) FROM cron.job' -f database/tests/emails/legacy_cutover_fixture.sql >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261003200000_canonical_email_delivery.sql -f database/tests/emails/legacy_cutover_assertions.sql >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f supabase/migrations/20261006090000_email_permissions_and_templates.sql >/dev/null
# Install the standard disposable test identities after legacy cutover assertions.
psql "$email_database" -v ON_ERROR_STOP=1 -q -f supabase/seed.sql >/dev/null
# Keep migrated fixtures for inspection, ineligible for any real send.
psql "$email_database" -v ON_ERROR_STOP=1 -q -c 'SELECT cron.unschedule(jobid) FROM cron.job' >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f database/tests/emails/readiness_fixture.sql >/dev/null
psql "$email_database" -v ON_ERROR_STOP=1 -q -f automation/email-delivery/check-readiness.sql >/dev/null
echo 'PASS: main + legacy fixture + canonical cutover, paused, IDs/audit preserved, ambiguous sends quarantined.'
