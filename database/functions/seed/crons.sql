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

  -- Schedule the synchronize_orders cron job (runs every 10 minutes)
  PERFORM cron.schedule(
      'synchronize_orders',
      '*/10 * * * *',
      format($$
        SELECT net.http_post(
          url := '%s/functions/v1/synchronize-orders'::text,
          body := jsonb_build_object('requestSecret', public.generate_request_secret(3600))
        );
      $$, p_project_url)
  );

  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
END;
$func$;
