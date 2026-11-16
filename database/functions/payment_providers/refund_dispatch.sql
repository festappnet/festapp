-- Service-only leased dispatch. A response never manufactures financial facts.
CREATE OR REPLACE FUNCTION public.claim_payment_refund(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.refund_requests; binding jsonb; token uuid; was_dispatched boolean;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[r.order_id]);
 PERFORM 1 FROM eshop.payment_info WHERE id=r.payment_info FOR UPDATE;
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.payment_providers WHERE provider_key=r.method AND hosted_checkout AND (refund_write_supported AND refund_write_enabled OR r.dispatched_at IS NOT NULL)) OR r.status NOT IN ('pending','processing','unknown') THEN RETURN jsonb_build_object('disposition','read'); END IF;
 IF r.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 binding:=public.payment_provider_call_internal(r.method,'refund_binding',jsonb_build_object('orderId',r.order_id));
 IF binding IS NULL OR binding IS DISTINCT FROM r.payload->'binding' THEN RAISE EXCEPTION 'REFUND_BINDING_CHANGED'; END IF;
 IF r.provider_refund_id IS NOT NULL AND public.payment_provider_call_internal(r.method,'refund_observed',
  jsonb_build_object('requestId',r.id,'orderId',r.order_id,'refundId',r.provider_refund_id))='true'::jsonb THEN
  UPDATE eshop.refund_requests SET status='succeeded',updated_at=now() WHERE id=r.id;
  PERFORM public.record_payment_fact_sync_internal(r.order_id);
  RETURN jsonb_build_object('disposition','read');
 END IF;
 token:=extensions.gen_random_uuid();was_dispatched:=r.dispatched_at IS NOT NULL;
 UPDATE eshop.refund_requests SET lease_token=token,lease_until=clock_timestamp()+interval '90 seconds',
  dispatched_at=coalesce(dispatched_at,clock_timestamp()),status='processing',updated_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('requestId',r.id,'providerId',r.method,'lease',token,'priorDispatched',was_dispatched,
  'connectorState',coalesce(r.result->'connectorState','{}')||jsonb_strip_nulls(jsonb_build_object('refundId',r.provider_refund_id)),
  'snapshot',binding||jsonb_build_object('requestId',r.id,'providerId',r.method,'amountMinor',(r.amount*100)::bigint,
    'currency',r.currency,'createdAt',floor(extract(epoch FROM r.created_at))::bigint,'idempotencyKey','festapp-refund-'||r.id));
END $$;
CREATE OR REPLACE FUNCTION public.complete_payment_refund(p_request uuid,p_lease uuid,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.refund_requests; v_status text; observed boolean;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[r.order_id]);
 PERFORM 1 FROM eshop.payment_info WHERE id=r.payment_info FOR UPDATE;
 SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=p_request FOR UPDATE;
 IF p_lease IS NULL OR r.lease_token IS NULL OR r.lease_until IS NULL OR r.lease_token IS DISTINCT FROM p_lease OR r.lease_until<clock_timestamp() OR NOT public.payment_method_is_online_internal(r.method) THEN RAISE EXCEPTION 'REFUND_LEASE_LOST'; END IF;
 IF p_result->>'status' NOT IN ('pending','action_required','succeeded','failed','cancelled','unknown') OR p_result->>'status' IS NULL THEN RAISE EXCEPTION 'REFUND_RESULT_INVALID'; END IF;
 IF r.provider_refund_id IS NOT NULL AND p_result->>'refundId' IS NOT NULL AND r.provider_refund_id<>p_result->>'refundId' THEN RAISE EXCEPTION 'REFUND_IDENTITY_CONFLICT'; END IF;
 observed:=public.payment_provider_call_internal(r.method,'refund_observed',jsonb_build_object('requestId',r.id,'orderId',r.order_id,'refundId',coalesce(r.provider_refund_id,p_result->>'refundId')))='true'::jsonb;
 v_status:=CASE WHEN observed THEN 'succeeded' WHEN p_result->'dispatchUncertain'='true'::jsonb THEN 'unknown'
  WHEN p_result->>'status' IN ('failed','cancelled') THEN p_result->>'status' ELSE 'pending' END;
 UPDATE eshop.refund_requests SET status=v_status,provider_refund_id=coalesce(provider_refund_id,p_result->>'refundId'),result=p_result,
  lease_token=NULL,lease_until=NULL,updated_at=now() WHERE id=r.id;
 INSERT INTO eshop.payment_operation_events(request_id,operation,details) VALUES(r.id,'provider_dispatch',p_result);
 PERFORM public.record_payment_fact_sync_internal(r.order_id);
 RETURN jsonb_build_object('committed',true,'status',v_status);
END $$;
CREATE OR REPLACE FUNCTION public.get_recoverable_payment_refunds()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT coalesce(jsonb_agg(jsonb_build_object('requestId',id,'providerId',method)),'[]') INTO result FROM (
  SELECT r.id,r.method FROM eshop.refund_requests r JOIN eshop.payment_providers p ON p.provider_key=r.method
  WHERE p.hosted_checkout AND r.status IN ('pending','processing','unknown')
   AND (r.lease_until IS NULL OR r.lease_until<clock_timestamp()) ORDER BY r.updated_at LIMIT 10) q;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.claim_payment_refund(uuid),public.complete_payment_refund(uuid,uuid,jsonb),public.get_recoverable_payment_refunds() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_payment_refund(uuid),public.complete_payment_refund(uuid,uuid,jsonb),public.get_recoverable_payment_refunds() TO service_role;
