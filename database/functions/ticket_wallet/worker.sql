-- Disabled until operations supplies the canonical endpoint; no network activity on migration.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_worker (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 worker_url text CHECK(worker_url ~ '^https://[^ ]+/functions/v1/sync-ticket-wallet$')
);
ALTER TABLE eshop.ticket_wallet_worker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_worker FROM PUBLIC,anon,authenticated;
INSERT INTO eshop.ticket_wallet_worker(singleton) VALUES(true) ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION public.wake_ticket_wallet_worker()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 PERFORM public.require_service_role();
 SELECT worker_url INTO target FROM eshop.ticket_wallet_worker WHERE singleton;
 IF target IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE next_attempt<=now() AND (lease_until IS NULL OR lease_until<=now())) THEN RETURN; END IF;
 PERFORM net.http_post(url:=target,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
END $$;
REVOKE ALL ON FUNCTION public.wake_ticket_wallet_worker() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_ticket_wallet_worker() TO service_role;
-- Deployment schedules this service-only owner using the existing trusted cron owner.
-- No trigger, paid dispatch or tenant activation is performed by the migration.

-- Install dormant, matching the existing notification workers. Activation is
-- a separate authorized release step after the trusted scheduler/worker probe.
DO $$ DECLARE job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  SELECT jobid INTO job FROM cron.job WHERE jobname='festapp_google_ticket_wallet';
  IF job IS NULL THEN
   job:=cron.schedule('festapp_google_ticket_wallet','* * * * *','SELECT public.wake_ticket_wallet_worker()');
   PERFORM cron.alter_job(job,active:=false);
  END IF;
 END IF;
END $$;
