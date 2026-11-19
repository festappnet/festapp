-- This runs in PostgreSQL even if Edge and Meta are offline.
CREATE OR REPLACE FUNCTION public.purge_meta_purchase_data_internal()
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
BEGIN
 -- Unpaid and paused rows also lose raw addresses after seven days.
 WITH stale_ip AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  WHERE d.client_ip IS NOT NULL AND d.consent_at<=clock_timestamp()-interval '7 days'
  ORDER BY d.consent_at LIMIT 100 FOR UPDATE SKIP LOCKED
 ) UPDATE analytics.meta_purchase_deliveries d SET client_ip=NULL FROM stale_ip WHERE d.order_id=stale_ip.order_id;
 -- Only a small bounded set is scrubbed per run. Keep delivery receipts 90 days.
 WITH expired AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  WHERE d.status='pending' AND d.consent_at<clock_timestamp()-interval '30 days'
  ORDER BY d.consent_at LIMIT 100 FOR UPDATE SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET status='expired',done_at=clock_timestamp(),
  lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,client_ip=NULL,client_agent=NULL,source_url=NULL
 FROM expired WHERE d.order_id=expired.order_id;
 DELETE FROM analytics.meta_purchase_deliveries d WHERE d.order_id IN(
  SELECT x.order_id FROM analytics.meta_purchase_deliveries x
  WHERE x.done_at<clock_timestamp()-interval '90 days' LIMIT 100 FOR UPDATE SKIP LOCKED);
 INSERT INTO analytics.meta_purchase_retention_state(singleton,last_sweep)
 VALUES(true,clock_timestamp()) ON CONFLICT(singleton) DO UPDATE SET last_sweep=EXCLUDED.last_sweep;
END $$;
REVOKE ALL ON FUNCTION public.purge_meta_purchase_data_internal() FROM PUBLIC,anon,authenticated,service_role;

-- Stop collecting when the independent retention job has not run recently.
CREATE OR REPLACE FUNCTION public.meta_purchase_retention_ready_internal()
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT FROM analytics.meta_purchase_retention_state
  WHERE singleton AND last_sweep>=statement_timestamp()-interval '10 minutes');
$$;
REVOKE ALL ON FUNCTION public.meta_purchase_retention_ready_internal() FROM PUBLIC,anon,authenticated,service_role;
