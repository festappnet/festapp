#!/usr/bin/env bash
set -euo pipefail
kind="$1"
root=/Users/miakh/source/festapp-stripe-readiness-20261022
cd "$root"
if [[ "$kind" == fresh ]]; then
  workdir=/tmp/festapp-stripe-readiness-db
  container=supabase_db_festapp-stripe-readiness-20261022
  port=61232
else
  workdir=/tmp/festapp-stripe-upgrade-db
  container=supabase_db_festapp-stripe-upgrade-20261022
  port=61242
fi
log="/tmp/stripe-${kind}-SEALED-replay.log"
url="postgresql://postgres:postgres@127.0.0.1:$port/postgres?sslmode=disable"
admin_url="postgresql://supabase_admin:postgres@127.0.0.1:$port/postgres?sslmode=disable"
supabase stop --workdir "$workdir" --no-backup > "$log" 2>&1
supabase db start --workdir "$workdir" >> "$log" 2>&1
docker exec -e PGPASSWORD=postgres "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -qc 'ALTER SYSTEM SET cron.launch_active_jobs = off' >> "$log" 2>&1
docker exec -e PGPASSWORD=postgres "$container" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -qc 'SELECT pg_reload_conf()' >> "$log" 2>&1
psql "$url" -X -v ON_ERROR_STOP=1 -qc 'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog' >> "$log" 2>&1
psql "$url" -X -v ON_ERROR_STOP=1 -f supabase/baseline/bootstrap.sql -f supabase/baseline/20260906140000_schema.sql -f supabase/baseline/20260906140000_reference_seed.sql -f automation/local_db/reference_tenants.sql >> "$log" 2>&1
python3 automation/baseline.py ledger-sql | psql "$url" -X -v ON_ERROR_STOP=1 >> "$log" 2>&1
if [[ "$kind" == upgrade ]]; then
  GIT_DIR=/Users/miakh/source/festapp/.git python3 /tmp/festapp-stripe-main-eab22c17/automation/baseline.py upgrade-local --database-url "$admin_url" >> "$log" 2>&1
  psql "$admin_url" -X -v ON_ERROR_STOP=1 -qf /tmp/stripe-upgrade-bank-fixture.sql >> "$log" 2>&1
  psql "$url" -X -Atqc "select jsonb_build_object('order',to_jsonb(o),'payment',to_jsonb(p)) from eshop.orders o join public.occasions c on c.id=o.occasion join eshop.payment_info p on p.id=o.payment_info where c.link='stripe-readiness-bank-fixture'" > /tmp/stripe-bank-SEALED-before.json
fi
python3 automation/baseline.py upgrade-local --database-url "$admin_url" >> "$log" 2>&1
if [[ "$kind" == upgrade ]]; then
  psql "$url" -X -Atqc "select jsonb_build_object('order',to_jsonb(o),'payment',to_jsonb(p)-'payment_method'-'stripe_connection_id') from eshop.orders o join public.occasions c on c.id=o.occasion join eshop.payment_info p on p.id=o.payment_info where c.link='stripe-readiness-bank-fixture'" > /tmp/stripe-bank-SEALED-after.json
  cmp /tmp/stripe-bank-SEALED-before.json /tmp/stripe-bank-SEALED-after.json
fi
psql "$url" -X -v ON_ERROR_STOP=1 -c "SET request.jwt.claim.role='service_role'" -f supabase/seed.sql >> "$log" 2>&1
printf '%s: canonical replay passed\n' "$kind"
