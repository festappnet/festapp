-- Single service boundary. Every operation checks service role; browser tokens
-- are independently scoped/hashed and never treated as account credentials.
CREATE OR REPLACE FUNCTION public.gopay_runtime_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.gopay_attempts; c eshop.gopay_connections; cap eshop.gopay_capabilities;
 lease uuid; facts jsonb; tx jsonb; existing eshop.gopay_movements; before_projection jsonb; source jsonb;
 result jsonb; digest text; seconds integer; total bigint; refunded bigint; held boolean:=false; stamp timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.require_service_role();
 IF p_operation='recoverable' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',q.id,'accountId',q.account_id)),'[]') FROM (
   SELECT a.id,c.account_id FROM eshop.gopay_attempts a JOIN eshop.gopay_connections c ON c.id=a.connection_id
   WHERE a.next_reconcile_at<=stamp AND (a.lease_expires_at IS NULL OR a.lease_expires_at<=stamp)
   ORDER BY a.next_reconcile_at,a.id LIMIT 10) q);
 ELSIF p_operation='callback_schedule' THEN
  IF p_args->>'paymentId' IS NULL OR p_args->>'paymentId' !~ '^[1-9][0-9]{0,15}$' THEN RAISE EXCEPTION 'GOPAY_CALLBACK_INVALID'; END IF;
  -- Coalesce bursts; callback cannot cause a remote create or overwrite facts.
  UPDATE eshop.gopay_attempts SET next_reconcile_at=least(next_reconcile_at,greatest(stamp,coalesce(last_synced_at,'-infinity')+interval '6 seconds')) WHERE remote_id=p_args->>'paymentId';
  RETURN NULL;
 ELSIF p_operation='purge' THEN
  WITH selected AS (SELECT s.attempt_id FROM eshop.gopay_sources s JOIN eshop.gopay_capabilities c USING(token_hash) WHERE c.expires_at<=stamp ORDER BY c.expires_at LIMIT 100),
   removed AS (DELETE FROM eshop.gopay_sources WHERE attempt_id IN(SELECT attempt_id FROM selected) RETURNING 1) SELECT count(*) INTO total FROM removed;
  RETURN to_jsonb(total);
 END IF;
 IF p_operation IN ('claim_checkout','read','handoff') THEN
  IF p_args->>'token' IS NULL OR p_args->>'token' !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO cap FROM eshop.gopay_capabilities WHERE token_hash=encode(extensions.digest(p_args->>'token','sha256'),'hex')
   AND scope=CASE p_operation WHEN 'claim_checkout' THEN 'order_pay' WHEN 'handoff' THEN 'handoff' ELSE p_args->>'scope' END AND expires_at>stamp;
  IF cap.token_hash IS NULL OR (p_operation='read' AND p_args->>'scope' NOT IN ('order_pay','return_read')) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO STRICT a FROM eshop.gopay_attempts WHERE id=cap.attempt_id;
 ELSIF p_operation IN ('source','attach_handoff') THEN SELECT * INTO STRICT a FROM eshop.gopay_attempts WHERE order_id=(p_args->>'orderId')::bigint;
 ELSE SELECT * INTO STRICT a FROM eshop.gopay_attempts WHERE id=(p_args->>'attemptId')::uuid; END IF;
 SELECT * INTO STRICT c FROM eshop.gopay_connections WHERE id=a.connection_id;
 IF p_operation='read' THEN
  IF cap.scope='return_read' AND a.remote_id IS NOT NULL THEN
   UPDATE eshop.gopay_capabilities SET consumed_at=stamp WHERE token_hash=cap.token_hash AND consumed_at IS NULL;
   IF FOUND THEN
    UPDATE eshop.gopay_attempts SET next_reconcile_at=least(next_reconcile_at,greatest(stamp,coalesce(last_synced_at,'-infinity')+interval '6 seconds')) WHERE id=a.id;
   END IF;
  END IF;
  RETURN public.provider_order_payment_projection_internal(a.order_id);
 ELSIF p_operation='source' THEN
  SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
   'payBaseUrl',regexp_replace(a.return_base_url,'/payments/gopay/return$','/payments/gopay/pay'),'payment',public.provider_order_payment_projection_internal(a.order_id)) INTO result
  FROM eshop.gopay_sources s JOIN eshop.gopay_capabilities pc USING(token_hash)
   WHERE s.attempt_id=a.id AND s.command_id=(p_args->>'commandId')::uuid AND pc.scope='order_pay' AND pc.expires_at>stamp;
  IF result IS NULL THEN RETURN jsonb_build_object('payment',public.provider_order_payment_projection_internal(a.order_id)); END IF;
  RETURN result;
 ELSIF p_operation='attach_handoff' THEN
  IF p_args->>'tokenHash' IS NULL OR p_args->>'tokenHash' !~ '^[a-f0-9]{64}$' OR NOT EXISTS(SELECT 1 FROM eshop.gopay_sources WHERE attempt_id=a.id AND command_id=(p_args->>'commandId')::uuid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  INSERT INTO eshop.gopay_capabilities(token_hash,attempt_id,scope,expires_at) VALUES(p_args->>'tokenHash',a.id,'handoff',least(a.reservation_expires_at,stamp+interval '30 minutes')) ON CONFLICT DO NOTHING;
  RETURN NULL;
 END IF;
 IF p_operation='claim_checkout' THEN PERFORM public.payment_policy_fence_internal(a.organization_id); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 PERFORM 1 FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.gopay_attempts WHERE id=a.id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=a.order_id AND pi.id=a.payment_info_id AND pi.payment_method='gopay' AND pi.gopay_connection_id=a.connection_id
   AND pi.amount*100=a.amount_minor AND pi.currency_code=a.currency AND oc.organization=a.organization_id AND oc.unit=a.unit_id) THEN RAISE EXCEPTION 'GOPAY_SCOPE_INVALID'; END IF;
 before_projection:=public.provider_order_payment_projection_internal(a.order_id);
 IF p_operation='handoff' THEN
  IF p_args->'consume'='true'::jsonb THEN
   UPDATE eshop.gopay_capabilities SET consumed_at=stamp WHERE token_hash=cap.token_hash AND consumed_at IS NULL AND expires_at>stamp;
   IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.gopay_sources WHERE attempt_id=a.id;
   RETURN jsonb_build_object('source',source);
  END IF;
  RETURN jsonb_build_object('payment',before_projection);
 ELSIF p_operation IN ('claim_checkout','claim_sync') THEN
  IF p_operation='claim_checkout' AND public.payment_collection_action_internal(a.order_id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN jsonb_build_object('providerId','gopay','disposition','read','payment',before_projection); END IF;
  IF p_operation='claim_sync' AND p_args->>'accountId' IS DISTINCT FROM c.account_id THEN RAISE EXCEPTION 'GOPAY_SCOPE_INVALID'; END IF;
  IF a.lease_expires_at>stamp OR coalesce(a.last_synced_at,'-infinity')>stamp-interval '6 seconds' THEN
   RETURN jsonb_build_object('providerId','gopay','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' AND (a.reservation_expires_at<=stamp OR before_projection->>'status' NOT IN ('open','preparing')) THEN
   RETURN jsonb_build_object('providerId','gopay','disposition','read','payment',before_projection); END IF;
  SELECT jsonb_build_object('sealed',sealed,'contentHash',content_hash,'tokenHash',token_hash) INTO source FROM eshop.gopay_sources WHERE attempt_id=a.id;
  IF p_operation='claim_checkout' AND a.remote_id IS NULL AND (a.dispatched_at IS NOT NULL OR source IS NULL OR NOT c.enabled) THEN
   RETURN jsonb_build_object('providerId','gopay','disposition','busy','payment',before_projection); END IF;
  IF p_operation='claim_checkout' THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('gopay.checkout',a.unit_id,a.organization_id),
    jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
  END IF;
  lease:=extensions.gen_random_uuid();
  UPDATE eshop.gopay_attempts SET lease_token=lease,lease_expires_at=stamp+interval '120 seconds',
   dispatched_at=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN coalesce(dispatched_at,stamp) ELSE dispatched_at END,
   next_reconcile_at=stamp+interval '120 seconds',
   state=CASE WHEN p_operation='claim_checkout' AND remote_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
  RETURN jsonb_build_object('providerId','gopay','disposition','dispatch','lease',lease,'checkoutId',a.remote_id,'connectorState',jsonb_build_object('paidObservedAt',(
    SELECT extract(epoch FROM occurred_at)::bigint::text FROM eshop.gopay_movements WHERE attempt_id=a.id AND kind='payment'
   )),'source',source,'returnBaseUrl',a.return_base_url,
   'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',false,'amountMinor',a.amount_minor,'currency',a.currency,
    'orderReference','Order '||(SELECT order_symbol FROM eshop.orders WHERE id=a.order_id),'createdAt',extract(epoch FROM a.created_at)::bigint,
    'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,'idempotencyKey',a.id,'locale',a.locale));
 END IF;
 IF p_args->>'lease' IS NULL OR a.lease_token IS NULL OR a.lease_token IS DISTINCT FROM (p_args->>'lease')::uuid OR a.lease_expires_at<=stamp THEN RAISE EXCEPTION 'GOPAY_LEASE_LOST'; END IF;
 IF p_operation='commit_checkout' THEN
  facts:=p_args->'checkout';
  IF facts->>'id' IS NULL OR facts->>'id' !~ '^[1-9][0-9]{0,15}$' OR (a.remote_id IS NOT NULL AND a.remote_id<>facts->>'id')
   OR (facts->>'url' IS NULL OR facts->>'url' !~ '^https://gw\.sandbox\.gopay\.com/gw/v3/[A-Za-z0-9_-]+$')
   OR (facts->>'expiresAt')::bigint IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint THEN RAISE EXCEPTION 'GOPAY_CHECKOUT_INVALID'; END IF;
  UPDATE eshop.gopay_attempts SET remote_id=facts->>'id',checkout_url=facts->>'url',reconcile_failures=0,state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
   lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=least(a.reservation_expires_at,
    CASE WHEN next_reconcile_at<a.lease_expires_at THEN next_reconcile_at ELSE 'infinity' END) WHERE id=a.id;
 ELSIF p_operation IN ('fail','defer') THEN
  seconds:=CASE WHEN p_operation='fail' THEN 60 ELSE (p_args->>'seconds')::integer END;
  IF seconds IS NULL OR seconds NOT BETWEEN 1 AND 3600 THEN RAISE EXCEPTION 'GOPAY_RECOVERY_INVALID'; END IF;
  IF p_operation='defer' THEN
   PERFORM public.apply_provider_payment_effects_internal('gopay',a.id,'unresolved:'||a.id,before_projection,false,true);
  END IF;
  UPDATE eshop.gopay_attempts SET lease_token=NULL,lease_expires_at=NULL,reconcile_failures=reconcile_failures+1,next_reconcile_at=stamp+make_interval(secs=>seconds) WHERE id=a.id;
 ELSIF p_operation='ingest' THEN
  facts:=p_args->'facts';
  IF facts->>'checkoutId' IS NULL OR facts->>'checkoutId' !~ '^[1-9][0-9]{0,15}$' OR facts->>'paymentId' IS DISTINCT FROM facts->>'checkoutId'
   OR a.remote_id IS DISTINCT FROM facts->>'checkoutId'
   OR facts->>'checkoutStatus' IS NULL OR facts->>'checkoutStatus' NOT IN ('open','complete','expired')
   OR jsonb_typeof(facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'movements')>100
   OR jsonb_typeof(facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(facts->'disputes')>1
   OR coalesce(facts#>>'{connectorState,goPayState}','') NOT IN ('CREATED','PAYMENT_METHOD_CHOSEN','PAID','CANCELED','TIMEOUTED','PARTIALLY_REFUNDED','REFUNDED')
   OR facts ? 'noCheckoutVerified' THEN RAISE EXCEPTION 'GOPAY_FACTS_INVALID'; END IF;
  -- An incomplete or changed history never subtracts a previously proved fact.
  held:=a.financial_hold OR jsonb_array_length(facts->'disputes')>0 OR EXISTS(
   SELECT 1 FROM eshop.gopay_movements m WHERE m.attempt_id=a.id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'movements') x WHERE x->>'providerId'=m.provider_id));
  FOR tx IN SELECT * FROM jsonb_array_elements(facts->'movements') LOOP
   IF tx->>'providerId' IS NULL OR tx->>'providerId' !~ '^[1-9][0-9]{0,15}$' OR tx->>'kind' IS NULL OR tx->>'kind' NOT IN ('payment','refund')
    OR jsonb_typeof(tx->'amountMinor') IS DISTINCT FROM 'number' OR (tx->>'amountMinor')::numeric<>trunc((tx->>'amountMinor')::numeric)
    OR (tx->>'amountMinor')::numeric NOT BETWEEN 1 AND a.amount_minor OR tx->>'currency' IS DISTINCT FROM a.currency
    OR jsonb_typeof(tx->'occurredAt') IS DISTINCT FROM 'number' OR (tx->>'occurredAt')::numeric<>trunc((tx->>'occurredAt')::numeric)
    OR (tx->>'occurredAt')::bigint<extract(epoch FROM a.created_at)::bigint OR (tx->>'occurredAt')::bigint>extract(epoch FROM stamp+interval '1 minute')::bigint
    THEN RAISE EXCEPTION 'GOPAY_MOVEMENT_INVALID'; END IF;
   SELECT * INTO existing FROM eshop.gopay_movements WHERE connection_id=c.id AND provider_id=tx->>'providerId';
   IF FOUND THEN
    IF existing.attempt_id<>a.id OR existing.kind<>tx->>'kind' OR existing.amount_minor<>(tx->>'amountMinor')::bigint OR existing.currency<>tx->>'currency'
      OR existing.occurred_at<>to_timestamp((tx->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'GOPAY_MOVEMENT_CONFLICT'; END IF;
   ELSE INSERT INTO eshop.gopay_movements VALUES(a.id,c.id,tx->>'providerId',tx->>'kind',(tx->>'amountMinor')::bigint,a.currency,to_timestamp((tx->>'occurredAt')::bigint)); END IF;
  END LOOP;
  SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0),coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0) INTO total,refunded FROM eshop.gopay_movements WHERE attempt_id=a.id;
  IF total NOT IN (0,a.amount_minor) OR refunded>total THEN RAISE EXCEPTION 'GOPAY_TOTALS_INVALID'; END IF;
  digest:=encode(extensions.digest(facts::text,'sha256'),'hex');
  INSERT INTO eshop.gopay_observations(attempt_id,digest,facts) VALUES(a.id,digest,facts) ON CONFLICT DO NOTHING;
  UPDATE eshop.gopay_attempts SET remote_id=facts->>'checkoutId',financial_hold=held,last_synced_at=stamp,reconcile_failures=0,
   awaiting_authorization=(facts#>>'{connectorState,goPayState}'='PAYMENT_METHOD_CHOSEN'),
   state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END WHERE id=a.id;
  PERFORM public.apply_provider_payment_effects_internal('gopay',a.id,digest,before_projection,facts->>'checkoutStatus'='expired',false);
  UPDATE eshop.gopay_attempts SET lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=least(
    CASE WHEN next_reconcile_at<a.lease_expires_at THEN next_reconcile_at ELSE 'infinity' END,
    CASE WHEN total=0 AND facts->>'checkoutStatus'<>'expired' AND a.reservation_expires_at>stamp THEN a.reservation_expires_at ELSE 'infinity' END
   ) WHERE id=a.id;
 ELSE RAISE EXCEPTION 'GOPAY_RUNTIME_OPERATION_UNSUPPORTED';
 END IF;
 PERFORM public.notification_center_provider_connection_internal('gopay',a.connection_id);
 RETURN jsonb_build_object('committed',true,'payment',public.provider_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.gopay_runtime_internal(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.gopay_runtime_internal(text,jsonb) TO service_role;
