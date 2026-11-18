CREATE OR REPLACE FUNCTION public.claim_meta_purchase_deliveries(p_limit integer)
RETURNS TABLE(order_id bigint, lease uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 -- Only a small bounded set is scrubbed per run. Keep delivery receipts 90 days.
 WITH expired AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  WHERE d.status='pending' AND d.consent_at<clock_timestamp()-interval '30 days'
  ORDER BY d.consent_at LIMIT 100 FOR UPDATE SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET status='expired',done_at=clock_timestamp(),
  lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
 FROM expired WHERE d.order_id=expired.order_id;
 DELETE FROM analytics.meta_purchase_deliveries d WHERE d.order_id IN(
  SELECT x.order_id FROM analytics.meta_purchase_deliveries x
  WHERE x.done_at<clock_timestamp()-interval '90 days' LIMIT 100 FOR UPDATE SKIP LOCKED);
 RETURN QUERY
 WITH due AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND c.enabled AND c.paused_at IS NULL
    AND public.form_order_purchase_timing_internal(d.order_id)='paid'
    AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
    AND d.next_attempt_at<=clock_timestamp() AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
  ORDER BY d.next_attempt_at,d.order_id LIMIT least(greatest(coalesce(p_limit,1),1),20)
  FOR UPDATE OF d SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET lease=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',prepared=false
 FROM due WHERE d.order_id=due.order_id RETURNING d.order_id,d.lease;
END $$;

-- Revalidate as close to sending as possible. Claiming does not disclose any
-- matching data or confer permission after withdrawal or destination changes.
CREATE OR REPLACE FUNCTION public.prepare_meta_purchase_delivery(p_order_id bigint,p_lease uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
 delivery analytics.meta_purchase_deliveries;
 connector analytics.meta_purchase_connectors;
 fact analytics.conversion_facts;
 o eshop.orders;
 token text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=delivery.unit;
 IF connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 IF public.form_order_purchase_timing_internal(p_order_id) IS DISTINCT FROM 'paid'
    OR public.form_order_purchase_capi_required_internal(p_order_id) IS DISTINCT FROM true
    OR delivery.connector_revision IS DISTINCT FROM connector.revision
    OR delivery.consent_revision IS DISTINCT FROM public.meta_purchase_consent_revision_internal(o.form)
    OR public.meta_purchase_snapshot_valid_internal(delivery.unit,delivery.consent_snapshot) IS DISTINCT FROM true
    OR delivery.consent_at>fact.created_at
    OR delivery.consent_at<clock_timestamp()-interval '30 days'
    OR fact.created_at<clock_timestamp()-interval '7 days'
    OR delivery.attempts>=6
    OR fact.payload IS DISTINCT FROM jsonb_build_object('value',o.price,'currency',trim(o.currency_code))
    OR NOT public.form_paid_conversion_eligible_internal(p_order_id) THEN
  UPDATE analytics.meta_purchase_deliveries SET status='invalid',done_at=clock_timestamp(),
   lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,client_agent=NULL,source_url=NULL
  WHERE order_id=p_order_id;
  RETURN NULL;
 END IF;
 SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE id=connector.vault_secret;
 IF coalesce(length(token),0) NOT BETWEEN 16 AND 4096 THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=connector.unit AND revision=connector.revision;
  RETURN NULL;
 END IF;
 UPDATE analytics.meta_purchase_deliveries SET attempts=attempts+1,prepared=true WHERE order_id=p_order_id;
 RETURN jsonb_build_object('dataset',connector.dataset,'accessToken',token,'testEventCode',connector.test_event_code,
  'eventId',fact.event_id,'eventTime',floor(extract(epoch FROM fact.created_at)),
  'value',fact.payload->'value','currency',fact.payload->>'currency',
  'emailHash',delivery.email_hash,'clientAgent',delivery.client_agent,'sourceUrl',delivery.source_url);
END $$;

CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text;
BEGIN
 PERFORM public.require_service_role();
 IF p_result IS NULL OR p_result NOT IN ('sent','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status='pending' AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision;
 END IF;
 final_status:=CASE WHEN p_result='sent' THEN 'sent'
  WHEN p_result='rejected' OR delivery.attempts>=6 THEN 'failed' ELSE 'pending' END;
 UPDATE analytics.meta_purchase_deliveries SET status=final_status,error_code=nullif(p_result,'sent'),
  next_attempt_at=clock_timestamp()+interval '2 minutes'*power(2,greatest(delivery.attempts-1,0)),
  lease=NULL,lease_until=NULL,done_at=CASE WHEN final_status<>'pending' THEN clock_timestamp() END,
  consent_snapshot=CASE WHEN final_status='pending' THEN consent_snapshot END,
  email_hash=CASE WHEN final_status='pending' THEN email_hash END,
  client_agent=CASE WHEN final_status='pending' THEN client_agent END,
  source_url=CASE WHEN final_status='pending' THEN source_url END
 WHERE order_id=p_order_id;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_meta_purchase_deliveries(integer),
 public.prepare_meta_purchase_delivery(bigint,uuid),public.finish_meta_purchase_delivery(bigint,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.wake_meta_purchase_worker()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE endpoint text;
BEGIN
 IF NOT EXISTS(
  SELECT FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit AND c.enabled AND c.paused_at IS NULL
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND d.next_attempt_at<=clock_timestamp()
   AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
   -- Same cohort filter as claiming, so unclaimable rows do not wake the worker.
   AND public.form_order_purchase_timing_internal(d.order_id)='paid'
   AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
 ) AND NOT EXISTS(
  SELECT FROM analytics.meta_purchase_deliveries WHERE status='pending' AND consent_at<clock_timestamp()-interval '30 days'
     OR done_at<clock_timestamp()-interval '90 days'
 ) THEN RETURN; END IF;
 SELECT regexp_replace(worker_url,'/process-email-queue$','/process-meta-purchases') INTO endpoint
 FROM public.email_capacity
 WHERE worker_url LIKE '%/process-email-queue';
 IF endpoint IS NULL THEN RETURN; END IF;
 PERFORM net.http_post(url:=endpoint,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),
   timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.wake_meta_purchase_worker() FROM PUBLIC,anon,authenticated,service_role;

-- An operator activates the schedule only after configuring a test dataset and
-- releasing the worker with the canonical gateway.
DO $$ DECLARE job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  SELECT jobid INTO job FROM cron.job WHERE jobname='festapp_meta_purchase_delivery';
  IF job IS NULL THEN
   job:=cron.schedule('festapp_meta_purchase_delivery','* * * * *','SELECT public.wake_meta_purchase_worker()');
   PERFORM cron.alter_job(job,active:=false);
  END IF;
 END IF;
END $$;
