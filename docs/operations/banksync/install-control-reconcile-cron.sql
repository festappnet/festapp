-- Run ONLY in postgres cron database during the separately approved release.
-- This is deliberately separate from the global cron-reset bootstrap.
\set ON_ERROR_STOP on
BEGIN;
SELECT cron.schedule_in_database('festapp_canonical_bank_sync_reconcile','*/5 * * * *',
  $$SELECT net.http_post(url:='https://api.festapp.net/functions/v1/bank-sync-reconcile',
    body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600)),timeout_milliseconds:=360000)$$,
  :'target_database');
COMMIT;
