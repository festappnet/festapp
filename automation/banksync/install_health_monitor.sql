-- Run in the pg_cron control database after verifying the runtime database and
-- selected tenant. psql variables: runtime_database, monitor_organization_id.
-- The request executes in the runtime database, where its secret is generated.
SELECT cron.schedule_in_database(
  'festapp_bank_sync_health_'||:'monitor_organization_id'::bigint,
  '*/5 * * * *',
  format($job$SELECT net.http_post(url:='https://api.festapp.net/functions/v1/bank-sync-reconcile',
    body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600),'monitor_organization_id',%s),
    timeout_milliseconds:=360000)$job$,:'monitor_organization_id'::bigint),
  :'runtime_database'
);
