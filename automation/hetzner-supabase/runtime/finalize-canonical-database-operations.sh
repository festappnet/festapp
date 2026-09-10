#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_RUNTIME_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_RUNTIME_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_RUNTIME_DATABASE:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_CANONICAL_DATABASE_FINALIZE_ACK:-}" == "finalize-canonical-database-operations" ]] ||
  fail "set FESTAPP_CANONICAL_DATABASE_FINALIZE_ACK=finalize-canonical-database-operations"
[[ "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid canonical database"
[[ "$(id -u)" == 0 && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] ||
  fail "run as root on the approved Festapp host"

cd "$COMPOSE_DIR"
exec 9>".festapp-runtime-upgrade.lock"
flock -n 9 || fail "another runtime operation is active"
[[ "$(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env)" == "$TARGET_DATABASE" ]] ||
  fail "runtime does not target the requested canonical database"
[[ "$(docker compose exec -T db psql -X -U postgres -d "$TARGET_DATABASE" -Atqc \
  'SHOW default_transaction_read_only')" == "off" ]] || fail "canonical writes are not open"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly FINALIZE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$EVIDENCE_ROOT/canonical-database-finalize-$FINALIZE_ID"
install -d -o root -g root -m 0700 "$RUN_DIR"
docker compose exec -T db pg_dump -U postgres -d "$TARGET_DATABASE" --data-only --format=custom \
  --table=auth.users --table=auth.identities --table=public.user_info \
  --table=public.images --table=public.occasions --table=public.events \
  --table=public.information --table=public.news --table=public.places \
  --table=public.inventory_pools --table=public.email_templates \
  --table=public.external_occasions_cache --table=public.external_sync_sources \
  --table=eshop.blueprints --table=eshop.product_types --table=eshop.products \
  >"$RUN_DIR/pre-change.dump"
chmod 0600 "$RUN_DIR/pre-change.dump"
sha256sum "$RUN_DIR/pre-change.dump" >"$RUN_DIR/pre-change.sha256"
chmod 0600 "$RUN_DIR/pre-change.sha256"

docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;
DO $body$
DECLARE r record; missing_objects bigint; remaining bigint;
BEGIN
  SELECT count(*) INTO missing_objects
  FROM public.images i
  LEFT JOIN storage.objects o
    ON o.bucket_id=split_part(split_part(i.link,'/storage/v1/object/public/',2),'/',1)
   AND o.name=substring(split_part(i.link,'/storage/v1/object/public/',2)
     from position('/' in split_part(i.link,'/storage/v1/object/public/',2))+1)
  WHERE i.link LIKE '%.supabase.co/storage/v1/object/public/%' AND o.id IS NULL;
  IF missing_objects<>0 THEN RAISE EXCEPTION '% legacy image objects were not copied',missing_objects; END IF;

  CREATE TEMP TABLE canonical_auth_email_map ON COMMIT DROP AS
  SELECT ui.id,ui.organization::text||'+'||lower(btrim(ui.email_readonly)) desired_email,
    'finalize-'||replace(ui.id::text,'-','')||'@invalid.local' temporary_email
  FROM public.user_info ui WHERE nullif(btrim(ui.email_readonly),'') IS NOT NULL;
  IF EXISTS(SELECT 1 FROM canonical_auth_email_map GROUP BY desired_email HAVING count(*)>1) OR
     EXISTS(SELECT 1 FROM canonical_auth_email_map m LEFT JOIN auth.users u ON u.id=m.id WHERE u.id IS NULL) THEN
    RAISE EXCEPTION 'canonical Auth email mapping is ambiguous or incomplete';
  END IF;
  UPDATE auth.users u SET email=m.temporary_email,updated_at=now()
  FROM canonical_auth_email_map m WHERE u.id=m.id AND lower(u.email)<>m.desired_email;
  UPDATE auth.identities i SET identity_data=jsonb_set(i.identity_data,'{email}',to_jsonb(m.temporary_email),true),updated_at=now()
  FROM canonical_auth_email_map m WHERE i.user_id=m.id AND i.provider='email' AND lower(coalesce(i.identity_data->>'email',''))<>m.desired_email;
  UPDATE auth.users u SET email=m.desired_email,updated_at=now()
  FROM canonical_auth_email_map m WHERE u.id=m.id AND lower(u.email)<>m.desired_email;
  UPDATE auth.identities i SET identity_data=jsonb_set(i.identity_data,'{email}',to_jsonb(m.desired_email),true),updated_at=now()
  FROM canonical_auth_email_map m WHERE i.user_id=m.id AND i.provider='email' AND lower(coalesce(i.identity_data->>'email',''))<>m.desired_email;

  DELETE FROM public.external_sync_sources WHERE supabase_url LIKE '%.supabase.co';
  FOR r IN SELECT table_schema,table_name,column_name,data_type FROM information_schema.columns
    WHERE table_schema IN ('public','eshop') AND data_type IN ('text','character varying','json','jsonb')
      AND is_generated='NEVER' AND NOT (table_schema='public' AND table_name='external_sync_sources')
  LOOP
    IF r.data_type='jsonb' THEN
      EXECUTE format('update %I.%I set %I=regexp_replace(%I::text,%L,%L,%L)::jsonb where %I::text like %L',r.table_schema,r.table_name,r.column_name,r.column_name,'https://[a-z0-9]+\.supabase\.co','https://api.festapp.net','g',r.column_name,'%.supabase.co%');
    ELSIF r.data_type='json' THEN
      EXECUTE format('update %I.%I set %I=regexp_replace(%I::text,%L,%L,%L)::json where %I::text like %L',r.table_schema,r.table_name,r.column_name,r.column_name,'https://[a-z0-9]+\.supabase\.co','https://api.festapp.net','g',r.column_name,'%.supabase.co%');
    ELSE
      EXECUTE format('update %I.%I set %I=regexp_replace(%I::text,%L,%L,%L) where %I::text like %L',r.table_schema,r.table_name,r.column_name,r.column_name,'https://[a-z0-9]+\.supabase\.co','https://api.festapp.net','g',r.column_name,'%.supabase.co%');
    END IF;
  END LOOP;
  remaining:=0;
  FOR r IN SELECT table_schema,table_name,column_name FROM information_schema.columns
    WHERE table_schema IN ('public','eshop') AND data_type IN ('text','character varying','json','jsonb')
  LOOP
    EXECUTE format('select count(*) from %I.%I where %I::text like %L',r.table_schema,r.table_name,r.column_name,'%.supabase.co%') INTO missing_objects;
    remaining:=remaining+missing_objects;
  END LOOP;
  IF remaining<>0 THEN RAISE EXCEPTION '% legacy Supabase data references remain',remaining; END IF;
END $body$;
COMMIT;
SQL

docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  -c "ALTER SYSTEM SET pg_net.database_name = '$TARGET_DATABASE'" >/dev/null
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -v target_database="$TARGET_DATABASE" <<'SQL'
SELECT cron.unschedule(jobid) FROM cron.job;
SELECT cron.schedule_in_database('festapp_canonical_apply_planned_changes','*/1 * * * *',
  'SELECT public.apply_planned_changes()',:'target_database');
SELECT cron.schedule_in_database('festapp_canonical_synchronize_orders','*/10 * * * *',
  $$SELECT net.http_post(url:='https://api.festapp.net/functions/v1/synchronize-orders',body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600)),timeout_milliseconds:=300000)$$,:'target_database');
SELECT cron.schedule_in_database('festapp_canonical_process_email_queue','*/1 * * * *',
  $$SELECT net.http_post(url:='https://api.festapp.net/functions/v1/send-email',body:=jsonb_build_object('processQueue',true,'requestSecret',public.generate_request_secret(3600)),timeout_milliseconds:=300000) WHERE jsonb_array_length(public.get_due_queue_emails())>0$$,:'target_database');
SQL

docker compose restart db >/dev/null
for attempt in $(seq 1 60); do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' supabase-db 2>/dev/null)" == healthy ]] && break
  sleep 1
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' supabase-db 2>/dev/null)" == healthy ]] || fail "database restart failed"
docker compose restart rest storage auth realtime functions meta studio api-gw >/dev/null
for attempt in $(seq 1 60); do
  unhealthy="$(docker compose ps --format json rest storage auth realtime functions meta studio api-gw | jq -s 'map(select(.State!="running" or (.Health!="" and .Health!="healthy")))|length')"
  [[ "$unhealthy" == 0 ]] && break
  sleep 1
done
[[ "$unhealthy" == 0 ]] || fail "runtime did not recover after database restart"

docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" -Atqc \
  "SELECT jsonb_build_object('target_database',current_database(),'auth_email_mismatches',(SELECT count(*) FROM auth.users u JOIN public.user_info ui ON ui.id=u.id WHERE nullif(btrim(ui.email_readonly),'') IS NOT NULL AND lower(u.email)<>ui.organization::text||'+'||lower(btrim(ui.email_readonly))),'legacy_image_urls',(SELECT count(*) FROM public.images WHERE link LIKE '%.supabase.co%'),'external_sync_sources',(SELECT count(*) FROM public.external_sync_sources),'pg_net_database',current_setting('pg_net.database_name'))" >"$RUN_DIR/result.json"
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -Atqc \
  "SELECT jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,'database',database) ORDER BY jobname) FROM cron.job" >"$RUN_DIR/cron-jobs.json"
chmod 0600 "$RUN_DIR/result.json" "$RUN_DIR/cron-jobs.json"
echo "Canonical database operations finalized."
echo "Evidence: $RUN_DIR"
