-- A fixed 31-minute reservation leaves one minute to dispatch Stripe's minimum
-- 30-minute Session. Retries never extend it. Product acceptance is a pilot gate.
CREATE OR REPLACE FUNCTION public.create_stripe_order_attempt_internal(p_order bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c eshop.stripe_connections; attempt uuid:=extensions.gen_random_uuid(); stamp timestamptz:=date_trunc('second',clock_timestamp());
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=pi.stripe_connection_id;
 IF pi.payment_method<>'stripe' OR pi.amount<=0 OR pi.amount<>o.price OR pi.currency_code<>o.currency_code
  OR pi.amount*100<>trunc(pi.amount*100) OR o.state<>'ordered' OR o.form IS NULL OR EXISTS(
   SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=o.id) THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 INSERT INTO eshop.stripe_checkout_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
  amount_minor,currency,order_revision,idempotency_key,created_at,reservation_expires_at,return_base_url)
 VALUES(attempt,o.id,pi.id,c.organization_id,c.unit_id,c.id,c.livemode,
  (pi.amount*100)::bigint,pi.currency_code,1,'festapp:checkout:'||attempt,stamp,stamp+interval '31 minutes',
  (SELECT rtrim(data->>'DEFAULT_URL','/')||'/stripe/return' FROM public.organizations WHERE id=c.organization_id));
 UPDATE eshop.payment_info SET deadline=stamp+interval '31 minutes' WHERE id=pi.id;
 RETURN attempt;
END $$;
REVOKE ALL ON FUNCTION public.create_stripe_order_attempt_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Edge prepares random tokens and AES-GCM source using the existing email key.
-- Only hashes and the sealed source commit, in the same transaction as the order.
CREATE OR REPLACE FUNCTION public.attach_stripe_order_pay_source_internal(p_order bigint,p_command uuid,p_source jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; expiry timestamptz:=clock_timestamp()+interval '30 days';
BEGIN
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order FOR UPDATE;
 IF p_command IS NULL OR p_source->>'tokenHash' IS NULL OR p_source->>'tokenHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'returnHash' IS NULL OR p_source->>'returnHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'tokenHash'=p_source->>'returnHash'
  OR p_source->>'contentHash' IS NULL OR p_source->>'contentHash' !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_source->'sealed') IS DISTINCT FROM 'object'
  OR p_source#>>'{sealed,v}' IS DISTINCT FROM '1'
  OR nullif(p_source#>>'{sealed,ciphertext}','') IS NULL OR nullif(p_source#>>'{sealed,iv}','') IS NULL THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_REQUIRED'; END IF;
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(p_source->>'tokenHash','order_pay',p_order,NULL,expiry),
  (p_source->>'returnHash','return_read',p_order,a.id,a.reservation_expires_at+interval '1 day');
 INSERT INTO eshop.stripe_payment_link_sources(token_hash,sealed,content_hash,expires_at,command_id)
 VALUES(p_source->>'tokenHash',p_source->'sealed',p_source->>'contentHash',expiry,p_command);
END $$;
REVOKE ALL ON FUNCTION public.attach_stripe_order_pay_source_internal(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stripe_order_payment_projection_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; a eshop.stripe_checkout_attempts; totals record; status text; admission text; delivery text; card_refunded numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info AND payment_method='stripe';
 IF pi.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1;
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor),0)/100 INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 status:=CASE WHEN totals.disputed>0 THEN 'disputed'
  WHEN card_refunded>=a.amount_minor/100.0 THEN 'refunded'
  WHEN a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL THEN 'pending'
  WHEN a.state='action_required' OR (totals.gross_received>=pi.amount AND o.state NOT IN ('paid','sent')) THEN 'action_required'
  WHEN card_refunded>0 THEN 'partially_refunded'
  WHEN totals.gross_received>=pi.amount AND o.state IN ('paid','sent') THEN 'paid'
  WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
  WHEN a.state IN ('uncertain','preparing') THEN 'preparing' ELSE 'open' END;
 admission:=CASE WHEN totals.disputed>0 OR status IN ('refunded','action_required') THEN 'hold'
  WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
 SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' WHEN 'suppressed' THEN 'suppressed' WHEN 'cancelled' THEN 'suppressed' ELSE 'pending' END INTO delivery
 FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('method','stripe','status',status,'amount',pi.amount::text,'received',totals.gross_received::numeric(30,2)::text,
  'returned',totals.refunded::numeric(30,2)::text,'currency',trim(pi.currency_code),'admissionState',admission,'deliveryState',coalesce(delivery,'not_requested'),
  'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,'reconciliationFailures',a.reconcile_failures,
  'allowedActions',CASE WHEN status IN ('open','preparing') AND NOT coalesce(a.lease_expires_at>clock_timestamp(),false) THEN jsonb_build_array('refresh','pay') ELSE jsonb_build_array('refresh') END);
END $$;
REVOKE ALL ON FUNCTION public.stripe_order_payment_projection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_stripe_order_pay_source_internal(p_order bigint,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
  'payment',public.stripe_order_payment_projection_internal(c.order_id),
  'payBaseUrl',(SELECT regexp_replace(return_base_url,'/stripe/return$','/stripe/pay') FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id ORDER BY created_at DESC LIMIT 1))
 INTO result FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities c USING(token_hash)
 WHERE s.command_id=p_command AND c.order_id=p_order AND c.scope='order_pay'
  AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp() AND s.expires_at=c.expires_at;
 IF result IS NULL THEN
  result:=jsonb_build_object('payment',public.stripe_order_payment_projection_internal(p_order));
  IF result#>>'{payment,method}' IS DISTINCT FROM 'stripe' OR result#>>'{payment,status}' IN ('open','preparing') THEN
   RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) TO service_role;
