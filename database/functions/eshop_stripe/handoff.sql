-- Issued only from the independently authenticated order-creation result. A
-- deterministic Edge derivation makes replay retain the same one-use bearer.
CREATE OR REPLACE FUNCTION public.attach_stripe_handoff_internal(p_order bigint,p_command uuid,p_token_hash text,p_livemode boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF a.livemode IS DISTINCT FROM p_livemode OR NOT EXISTS(SELECT 1 FROM eshop.stripe_payment_link_sources s
  JOIN eshop.stripe_capabilities pc USING(token_hash) WHERE s.command_id=p_command AND pc.order_id=p_order AND pc.scope='order_pay'
   AND pc.revoked_at IS NULL AND pc.expires_at>clock_timestamp() AND s.expires_at>clock_timestamp()) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(p_token_hash,'handoff',p_order,a.id,least(a.reservation_expires_at,a.created_at+interval '30 minutes'))
 ON CONFLICT(token_hash) DO NOTHING;
 SELECT * INTO STRICT cap FROM eshop.stripe_capabilities WHERE token_hash=p_token_hash;
 IF cap.scope<>'handoff' OR cap.order_id<>p_order OR cap.attempt_id<>a.id THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Replaying creation must never renew, unconsume or un-revoke a handoff.
END $$;
REVOKE ALL ON FUNCTION public.attach_stripe_handoff_internal(bigint,uuid,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.attach_stripe_handoff_internal(bigint,uuid,text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.read_stripe_handoff_internal(p_token text,p_livemode boolean,p_consume boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities; source jsonb; projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_consume IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='handoff' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE id=c.attempt_id AND order_id=c.order_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 SELECT * INTO STRICT cap FROM eshop.stripe_capabilities WHERE token_hash=cap.token_hash FOR UPDATE;
 IF cap.revoked_at IS NOT NULL OR cap.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 projection:=public.stripe_order_payment_projection_internal(cap.order_id);
 IF NOT p_consume THEN
  IF cap.consumed_at IS NOT NULL THEN projection:=projection||jsonb_build_object('allowedActions',jsonb_build_array('refresh')); END IF;
  RETURN jsonb_build_object('payment',projection);
 END IF;
 PERFORM public.authorize_stripe_capability_internal(p_token,'handoff',cap.order_id,cap.attempt_id);
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=cap.order_id AND pc.scope='order_pay' AND pc.revoked_at IS NULL
  AND pc.expires_at>clock_timestamp() AND s.expires_at>clock_timestamp() ORDER BY s.created_at DESC LIMIT 1;
 IF source IS NULL THEN RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 -- This source never crosses the Edge boundary to the handoff browser.
 RETURN jsonb_build_object('source',source,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_handoff_internal(text,boolean,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_handoff_internal(text,boolean,boolean) TO service_role;
