-- Token creation belongs to the order transaction, never the public overview.
CREATE OR REPLACE FUNCTION public.issue_stripe_capability_internal(
 p_order bigint,p_scope text,p_expires_at timestamptz,p_attempt uuid DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_attempt eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 IF p_scope IS NULL OR p_scope NOT IN ('order_pay','handoff','return_read') OR
  p_expires_at IS NULL OR p_expires_at<=clock_timestamp() OR
  (p_scope<>'order_pay' AND p_attempt IS NULL) THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 PERFORM 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
 WHERE o.id=p_order AND pi.payment_method='stripe' AND o.state<>'waitlisted' FOR UPDATE OF o;
 IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 IF p_attempt IS NOT NULL THEN
  SELECT * INTO v_attempt FROM eshop.stripe_checkout_attempts WHERE id=p_attempt AND order_id=p_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'STRIPE_CAPABILITY_INVALID'; END IF;
 END IF;
 IF p_scope IN ('handoff','return_read') AND p_expires_at>least(v_attempt.reservation_expires_at,clock_timestamp()+interval '30 minutes') THEN
  RAISE EXCEPTION 'STRIPE_CAPABILITY_EXPIRY_INVALID'; END IF;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(encode(extensions.digest(v_token,'sha256'),'hex'),p_scope,p_order,p_attempt,p_expires_at);
 RETURN v_token;
END $$;
REVOKE ALL ON FUNCTION public.issue_stripe_capability_internal(bigint,text,timestamptz,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.issue_stripe_capability_internal(bigint,text,timestamptz,uuid) TO service_role;

-- A service endpoint must choose the scope; it cannot infer it from any supplied ID.
CREATE OR REPLACE FUNCTION public.authorize_stripe_capability_internal(
 p_token text,p_scope text,p_order bigint,p_attempt uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_scope IS NULL OR p_scope NOT IN ('order_pay','handoff','return_read') THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO v_cap FROM eshop.stripe_capabilities
 WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND scope=p_scope
 AND order_id=p_order AND revoked_at IS NULL AND expires_at>clock_timestamp()
 AND (p_attempt IS NULL OR attempt_id=p_attempt)
 AND (scope<>'handoff' OR consumed_at IS NULL) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_scope='handoff' THEN UPDATE eshop.stripe_capabilities SET consumed_at=clock_timestamp() WHERE token_hash=v_cap.token_hash; END IF;
 RETURN jsonb_build_object('orderId',v_cap.order_id,'attemptId',v_cap.attempt_id,'scope',v_cap.scope,'expiresAt',v_cap.expires_at);
END $$;
REVOKE ALL ON FUNCTION public.authorize_stripe_capability_internal(text,text,bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_stripe_capability_internal(text,text,bigint,uuid) TO service_role;
