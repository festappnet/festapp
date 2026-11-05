-- Install through the same pg_cron infrastructure, independently of notification
-- center activation. Activation is a separate release step after the worker probe.
DO $$ DECLARE job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  SELECT jobid INTO job FROM cron.job WHERE jobname='festapp_canonical_sale_opening_notifications';
  IF job IS NULL THEN
   job:=cron.schedule('festapp_canonical_sale_opening_notifications','* * * * *','SELECT public.maintain_sale_opening_notifications(100)');
   PERFORM cron.alter_job(job,active:=false);
  END IF;
 END IF;
END $$;
