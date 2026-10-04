CREATE OR REPLACE FUNCTION setup_crons(p_project_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $func$
BEGIN
  -- Security Check
  IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
      RAISE EXCEPTION 'Access Denied: Service role required.';
  END IF;

  -- Schedule the apply_planned_changes cron job (runs every minute)
  PERFORM cron.schedule(
    'apply_planned_changes',
    '*/1 * * * *',
    'SELECT apply_planned_changes()'
  );

  -- BankSync owns bank polling. This job only recovers durable control intents.
  PERFORM cron.schedule('festapp_canonical_bank_sync_reconcile','*/5 * * * *',
    format($$SELECT net.http_post(url:='%s/functions/v1/bank-sync-reconcile',
      body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600)),
      timeout_milliseconds:=360000)$$,p_project_url));

  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
END;
$func$;
