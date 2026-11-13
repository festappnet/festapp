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
 PERFORM public.maintain_ticket_wallet(100);
 SELECT worker_url INTO target FROM eshop.ticket_wallet_worker WHERE singleton;
 IF target IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_work w JOIN eshop.ticket_wallet_integrations i ON i.organization=w.organization WHERE NOT i.paused AND w.kind IN ('class','object') AND w.requested>w.applied AND w.due_at<=now() AND (w.lease_until IS NULL OR w.lease_until<=now())) THEN RETURN; END IF;
 PERFORM net.http_post(url:=target,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
END $$;
REVOKE ALL ON FUNCTION public.wake_ticket_wallet_worker() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_ticket_wallet_worker() TO service_role;
-- Deployment schedules this service-only owner using the existing trusted cron owner.
-- No trigger, paid dispatch or tenant activation is performed by the migration.

-- The existing scheduler is owned by control-plane postgres. Upgrade that single
-- job with automation/ticket-wallet/update-control-plane-scheduler.sql after probes.
-- No runtime-DB schedule is installed by this source.
