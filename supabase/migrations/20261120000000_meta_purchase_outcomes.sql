-- Explain terminal Meta purchase outcomes without retaining matching data.

-- SOURCE: eshop_forms/meta_purchase_settings.sql
CREATE OR REPLACE FUNCTION public.get_unit_meta_purchase(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.can_manage_unit_meta_purchase(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Meta CAPI access denied'; END IF;
 IF NOT public.meta_purchase_platform_allowed_internal(p_unit) THEN
  RETURN jsonb_build_object('allowed',false,'connected',EXISTS(SELECT FROM analytics.meta_purchase_connectors WHERE unit=p_unit));
 END IF;
 SELECT jsonb_build_object('dataset',c.dataset,'website_origin',c.website_origin,'test_event_code',c.test_event_code,
  'enabled',c.enabled,'paused_at',c.paused_at,'token_saved',c.vault_secret IS NOT NULL,'revision',c.revision,
  'website_ready',coalesce(c.website_origin=ANY(public.unit_meta_purchase_origins_internal(p_unit)) AND (
   c.website_origin=(SELECT rtrim(org.data->>'DEFAULT_URL','/') FROM public.units u
    JOIN public.organizations org ON org.id=u.organization WHERE u.id=p_unit)
   OR EXISTS(SELECT FROM analytics.website_consent_bindings b WHERE b.unit=p_unit
    AND b.website_origin=c.website_origin AND b.provider_config->>'provider' IN ('cookiebot','cookieconsent','wix')
    AND public.website_consent_binding_effective_internal(b))
  ),false))
 INTO result FROM analytics.meta_purchase_connectors c WHERE c.unit=p_unit;
 RETURN coalesce(result,'{}'::jsonb)||jsonb_build_object('allowed',true,
  'websites',to_jsonb(public.unit_meta_purchase_origins_internal(p_unit)),
  'queue',(SELECT jsonb_build_object('pending',count(*) FILTER(WHERE status='pending'),
    'sent',count(*) FILTER(WHERE status='sent'),'failed',count(*) FILTER(WHERE status='failed'),
    'revoked',count(*) FILTER(WHERE status='revoked'),
    'invalid',count(*) FILTER(WHERE status='invalid'),'expired',count(*) FILTER(WHERE status='expired')) FROM analytics.meta_purchase_deliveries
    WHERE unit=p_unit AND coalesce(done_at,consent_at)>=statement_timestamp()-interval '30 days'),
  'last_error',coalesce((SELECT jsonb_build_object('code',error_code,'status',status,'at',coalesce(done_at,next_attempt_at-interval '2 minutes'*power(2,greatest(attempts-1,0))))
    FROM analytics.meta_purchase_deliveries WHERE unit=p_unit AND error_code IS NOT NULL
    ORDER BY coalesce(done_at,next_attempt_at-interval '2 minutes'*power(2,greatest(attempts-1,0))) DESC LIMIT 1),
    (SELECT jsonb_build_object('code','credentials','status','pending','at',paused_at) FROM analytics.meta_purchase_connectors WHERE unit=p_unit AND paused_at IS NOT NULL)),
  'forms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'enabled',m.form IS NOT NULL,
     'measurement_ready',public.form_conversion_policy_allows_internal(public.form_measurement_status_internal(f.id))) ORDER BY f.id),'[]'::jsonb)
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    LEFT JOIN analytics.meta_purchase_forms m ON m.form=f.id AND m.unit=p_unit WHERE o.unit=p_unit));
END $$;

-- SOURCE: eshop_forms/meta_purchase_worker.sql
CREATE OR REPLACE FUNCTION public.claim_meta_purchase_deliveries(p_limit integer)
RETURNS TABLE(order_id bigint, lease uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN QUERY
 WITH due AS (
  SELECT d.order_id FROM analytics.meta_purchase_deliveries d
  JOIN analytics.meta_purchase_connectors c ON c.unit=d.unit
  JOIN analytics.conversion_facts f ON f."order"=d.order_id AND f.kind='order_fully_paid'
  WHERE d.status='pending' AND c.enabled AND c.paused_at IS NULL
    AND public.meta_purchase_platform_allowed_internal(c.unit)
    AND public.form_order_purchase_timing_internal(d.order_id)='paid'
    AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
    AND d.next_attempt_at<=clock_timestamp() AND (d.lease_until IS NULL OR d.lease_until<=clock_timestamp())
  ORDER BY d.next_attempt_at,d.order_id LIMIT least(greatest(coalesce(p_limit,1),1),20)
  FOR UPDATE OF d SKIP LOCKED
 )
 UPDATE analytics.meta_purchase_deliveries d SET lease=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',prepared=false,prepared_at=NULL
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
 token text; connector_unit bigint; invalid_reason text;
BEGIN
 PERFORM public.require_service_role();
 -- Follow the same connector -> delivery order as disconnect and finish.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO connector FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 -- Serialize short prepares before a possible credential pause; never upgrade
 -- two concurrent shared connector locks to an update lock.
 IF NOT FOUND OR connector.enabled IS DISTINCT FROM true OR connector.paused_at IS NOT NULL
  OR NOT public.meta_purchase_platform_allowed_internal(connector.unit) THEN RETURN NULL; END IF;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND status='pending' AND lease=p_lease AND lease_until>clock_timestamp() AND NOT prepared
 FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF delivery.unit IS DISTINCT FROM connector.unit THEN RETURN NULL; END IF;
 SELECT * INTO fact FROM analytics.conversion_facts WHERE "order"=p_order_id AND kind='order_fully_paid';
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 -- Closed reason vocabulary; the first matching guard owns the outcome.
 invalid_reason:=CASE
  WHEN delivery.connector_revision IS DISTINCT FROM connector.revision THEN 'connector_changed'
  WHEN public.form_order_purchase_timing_internal(p_order_id) IS DISTINCT FROM 'paid'
    OR public.form_order_purchase_capi_required_internal(p_order_id) IS DISTINCT FROM true
    OR public.form_meta_purchase_unit_internal(o.form) IS DISTINCT FROM connector.unit
    OR fact.payload IS DISTINCT FROM jsonb_build_object('value',o.price,'currency',trim(o.currency_code))
    OR NOT public.form_paid_conversion_eligible_internal(p_order_id) THEN 'order_ineligible'
  WHEN delivery.consent_revision IS DISTINCT FROM public.meta_purchase_consent_revision_internal(o.form)
    OR public.meta_purchase_snapshot_valid_internal(delivery.unit,delivery.consent_snapshot) IS DISTINCT FROM true
    OR delivery.consent_at>fact.created_at
    OR delivery.consent_at<clock_timestamp()-interval '30 days' THEN 'consent_invalid'
  WHEN fact.created_at<clock_timestamp()-interval '7 days' THEN 'payment_too_old'
  WHEN delivery.attempts>=6 THEN 'attempts_exhausted'
 END;
 IF invalid_reason IS NOT NULL THEN
  UPDATE analytics.meta_purchase_deliveries SET status='invalid',error_code=invalid_reason,done_at=clock_timestamp(),
   lease=NULL,lease_until=NULL,consent_snapshot=NULL,email_hash=NULL,phone_hash=NULL,fbp=NULL,fbc=NULL,client_ip=NULL,client_agent=NULL,source_url=NULL
  WHERE order_id=p_order_id;
  RETURN NULL;
 END IF;
 SELECT decrypted_secret INTO token FROM vault.decrypted_secrets WHERE id=connector.vault_secret;
 IF coalesce(length(token),0) NOT BETWEEN 16 AND 4096 THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=connector.unit AND revision=connector.revision;
  RETURN NULL;
 END IF;
 -- Recheck retention even if claim used an older worker or cleanup was bounded.
 IF delivery.consent_at<=clock_timestamp()-interval '7 days' THEN delivery.client_ip:=NULL; END IF;
 UPDATE analytics.meta_purchase_deliveries SET client_ip=delivery.client_ip,attempts=attempts+1,prepared=true,prepared_at=clock_timestamp() WHERE order_id=p_order_id;
 RETURN jsonb_build_object('dataset',connector.dataset,'accessToken',token,'testEventCode',connector.test_event_code,
  'eventId',fact.event_id,'eventTime',floor(extract(epoch FROM fact.created_at)),
  'value',fact.payload->'value','currency',fact.payload->>'currency',
  'phoneHash',CASE WHEN delivery.phone_hash ~ '^[0-9a-f]{64}$' THEN delivery.phone_hash END,'fbp',public.meta_purchase_browser_id_internal(delivery.fbp),
  'fbc',public.meta_purchase_browser_id_internal(delivery.fbc),'clientIp',host(delivery.client_ip),
  'emailHash',delivery.email_hash,'clientAgent',delivery.client_agent,'sourceUrl',delivery.source_url);
END $$;

CREATE OR REPLACE FUNCTION public.finish_meta_purchase_delivery(p_order_id bigint,p_lease uuid,p_result text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE delivery analytics.meta_purchase_deliveries; final_status text; connector_unit bigint;
BEGIN
 PERFORM public.require_service_role();
 IF p_result IS NULL OR p_result NOT IN ('sent','retry','credentials','rejected') THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid delivery result'; END IF;
 -- A disconnected connector may be absent; its terminal receipt still exists.
 -- Lock any surviving connector before the delivery, like prepare and delete.
 SELECT unit INTO connector_unit FROM analytics.meta_purchase_deliveries WHERE order_id=p_order_id;
 IF NOT FOUND THEN RETURN false; END IF;
 PERFORM 1 FROM analytics.meta_purchase_connectors WHERE unit=connector_unit FOR NO KEY UPDATE;
 SELECT * INTO delivery FROM analytics.meta_purchase_deliveries
 WHERE order_id=p_order_id AND lease=p_lease AND status IN ('pending','revoked') AND prepared FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_result='credentials' THEN
  UPDATE analytics.meta_purchase_connectors SET paused_at=clock_timestamp()
  WHERE unit=delivery.unit AND revision=delivery.connector_revision
   AND (token_changed_at IS NULL OR token_changed_at<delivery.prepared_at);
 END IF;
 -- Withdrawal scrubs the payload but must still record the authorized in-flight result.
 IF delivery.status='revoked' THEN
  UPDATE analytics.meta_purchase_deliveries
  SET error_code=CASE WHEN p_result='sent' THEN 'sent_in_flight' ELSE p_result END,
   lease=NULL,lease_until=NULL
  WHERE order_id=p_order_id;
  RETURN true;
 END IF;
 final_status:=CASE WHEN p_result='sent' THEN 'sent'
  WHEN p_result='rejected' OR delivery.attempts>=6 THEN 'failed' ELSE 'pending' END;
 UPDATE analytics.meta_purchase_deliveries SET status=final_status,error_code=nullif(p_result,'sent'),
  next_attempt_at=clock_timestamp()+interval '2 minutes'*power(2,greatest(delivery.attempts-1,0)),
  lease=NULL,lease_until=NULL,done_at=CASE WHEN final_status<>'pending' THEN clock_timestamp() END,
  consent_snapshot=CASE WHEN final_status='pending' THEN consent_snapshot END,
  email_hash=CASE WHEN final_status='pending' THEN email_hash END,
  phone_hash=CASE WHEN final_status='pending' THEN phone_hash END,
  fbp=CASE WHEN final_status='pending' THEN fbp END,
  fbc=CASE WHEN final_status='pending' THEN fbc END,
  client_ip=CASE WHEN final_status='pending' AND consent_at>clock_timestamp()-interval '7 days' THEN client_ip END,
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
   AND public.meta_purchase_platform_allowed_internal(c.unit)
   -- Same cohort filter as claiming, so unclaimable rows do not wake the worker.
   AND public.form_order_purchase_timing_internal(d.order_id)='paid'
   AND public.form_order_purchase_capi_required_internal(d.order_id) IS TRUE
) THEN RETURN; END IF;
 SELECT regexp_replace(worker_url,'/process-email-queue$','/process-meta-purchases') INTO endpoint
 FROM public.email_capacity
 WHERE worker_url LIKE '%/process-email-queue';
 IF endpoint IS NULL THEN RETURN; END IF;
 PERFORM net.http_post(url:=endpoint,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),
   timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.wake_meta_purchase_worker() FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/meta_purchase_retention.sql
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
 UPDATE analytics.meta_purchase_deliveries d SET status='expired',error_code='retention_expired',done_at=clock_timestamp(),
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
