#!/usr/bin/env bash
# Initial schema load into the task-owned EMPTY backend, never an existing tenant.
set -euo pipefail
cd "$(dirname "$0")/../../.."
project=${FESTAPP_CMS_TEST_PROJECT:-festapp-vo-wordpress-20261023}
base_port=${FESTAPP_CMS_TEST_BASE_PORT:-59820}
[[ "$project" == festapp-vo-wordpress-20261023 || "$project" =~ ^festapp-cms-consent-[a-z0-9-]+$ ]] || { echo 'Refusing unowned test project'; exit 1; }
[[ "$base_port" =~ ^[0-9]+$ ]] && (( base_port >= 1024 && base_port <= 65520 )) || { echo 'Invalid test base port'; exit 1; }
container=supabase_db_$project
db_port=$((base_port + 2))
url="postgresql://supabase_admin:postgres@127.0.0.1:$db_port/postgres?sslmode=disable"
[ "$(docker inspect -f '{{.Name}}' "$container")" = "/$container" ]
[ "$(docker inspect -f '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$container")" = "$db_port" ]
[ "$(psql "$url" -Atqc "select count(*) from information_schema.tables where table_schema='public' and table_name='organizations'")" = 0 ] || { echo 'Refusing non-empty backend'; exit 1; }
docker exec "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -qc 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog'
docker exec -e PGPASSWORD=postgres "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER SYSTEM SET cron.launch_active_jobs=off'
docker exec -e PGPASSWORD=postgres "$container" psql -X -U supabase_admin -d postgres -Atqc 'SELECT pg_reload_conf()' >/dev/null
bootstrap=$(python3 automation/baseline.py field bootstrap)
schema=$(python3 automation/baseline.py field schema)
seed=$(python3 automation/baseline.py field referenceSeed)
psql "$url" -v ON_ERROR_STOP=1 -f "$bootstrap" -f "$schema" -f "$seed" >/dev/null
python3 automation/baseline.py ledger-sql | psql "$url" -v ON_ERROR_STOP=1 >/dev/null
# The migration CLI changes session role to postgres, which must own its ledger.
psql "$url" -v ON_ERROR_STOP=1 -qc 'GRANT USAGE, CREATE ON SCHEMA supabase_migrations TO postgres; GRANT ALL ON ALL TABLES IN SCHEMA supabase_migrations TO postgres; ALTER TABLE supabase_migrations.schema_migrations OWNER TO postgres'
python3 automation/baseline.py upgrade-local --database-url "$url"
PGOPTIONS='-c request.jwt.claim.role=service_role' psql "$url" -v ON_ERROR_STOP=1 -f supabase/seed.sql -f web_client/tests/fixtures/embedded-checkout/tenant.sql >/dev/null
umask 077
supabase status --workdir integrations/wordpress/.private/backend --output json > integrations/wordpress/.private/backend-status.json
docker exec -i "$container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q < integrations/wordpress/tests/fixture-fixes.sql

node integrations/wordpress/scripts/prepare-organizer.mjs
printf "Disposable canonical backend seeded\n"
