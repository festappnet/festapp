CREATE OR REPLACE FUNCTION public.claim_stripe_checkout_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities; a eshop.stripe_checkout_attempts; o eshop.orders; pi eshop.payment_info;
 c eshop.stripe_connections; source jsonb; lease uuid; projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND scope='order_pay' AND revoked_at IS NULL AND expires_at>clock_timestamp();
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 PERFORM public.authorize_stripe_capability_internal(p_token,'order_pay',cap.order_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=cap.order_id;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF a.livemode IS DISTINCT FROM p_livemode OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>a.connection_id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency OR o.currency_code<>a.currency
  OR coalesce(pi.paid_externally,0)<>0 THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 projection:=public.stripe_order_payment_projection_internal(o.id);
 IF projection->>'status' NOT IN ('open','preparing') THEN RETURN jsonb_build_object('disposition','read','payment',projection); END IF;
 IF o.price*100<>a.amount_minor THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 IF a.lease_expires_at>clock_timestamp() OR a.reservation_expires_at<=clock_timestamp() THEN
  RETURN jsonb_build_object('disposition','busy','payment',projection); END IF;
 -- Admission precedes any provider work, keyed by the hashed pay capability.
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.checkout',a.unit_id,a.organization_id),
  jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' AND pc.revoked_at IS NULL AND pc.expires_at>clock_timestamp()
 ORDER BY s.created_at DESC LIMIT 1;
 IF source IS NULL OR a.return_base_url IS NULL THEN RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds',
  state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,'payment',projection,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'returnBaseUrl',a.return_base_url,'sessionId',a.session_id,'refundCursor',a.refund_cursor));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.commit_stripe_checkout_session_internal(p_attempt uuid,p_lease uuid,p_session text,p_url text,p_expires bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 -- Form/order first, then attempt, as in the claim and payment ingest.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt));
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR p_session IS NULL OR p_session !~ '^cs_[A-Za-z0-9_]+$'
  OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/[^[:space:]]+$'
  OR p_expires IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint
  OR (a.session_id IS NOT NULL AND a.session_id<>p_session) THEN RAISE EXCEPTION 'STRIPE_CHECKOUT_RECEIPT_INVALID'; END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_session,checkout_url=p_url,
  state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=least(reservation_expires_at,clock_timestamp()+interval '2 minutes')
 WHERE id=a.id;
 RETURN jsonb_build_object('committed',true,'payment',public.stripe_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_checkout_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_checkout_attempts SET state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=clock_timestamp()+interval '1 minute'
 WHERE id=p_attempt AND lease_token=p_lease;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) TO service_role;

-- Minimal read only. Knowledge of this handle cannot start Checkout or reveal PII.
CREATE OR REPLACE FUNCTION public.read_stripe_return_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='return_read' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE id=c.attempt_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.stripe_order_payment_projection_internal(cap.order_id)-'allowedActions'||jsonb_build_object('allowedActions',jsonb_build_array('refresh'));
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_return_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_return_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.read_stripe_pay_status_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='order_pay' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.stripe_order_payment_projection_internal(cap.order_id);
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) TO service_role;

-- Shared by signed webhook delivery and bounded recovery, including retired
-- connections. Pausing new sales must not stop money/refund reconciliation.
CREATE OR REPLACE FUNCTION public.claim_stripe_sync_internal(p_account text,p_livemode boolean,
 p_attempt uuid DEFAULT NULL,p_session text DEFAULT NULL,p_intent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; lease uuid; source jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account AND livemode=p_livemode;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id AND
  ((p_attempt IS NOT NULL AND id=p_attempt) OR (p_session IS NOT NULL AND session_id=p_session) OR (p_intent IS NOT NULL AND payment_intent_id=p_intent))
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=a.id FOR UPDATE;
 IF a.lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 IF (p_session IS NOT NULL AND a.session_id IS NOT NULL AND p_session<>a.session_id)
  OR (p_intent IS NOT NULL AND a.payment_intent_id IS NOT NULL AND p_intent<>a.payment_intent_id) THEN RAISE EXCEPTION 'STRIPE_SYNC_IDENTITY_MISMATCH'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' ORDER BY s.created_at DESC LIMIT 1;
 -- Historical reads need no bearer secret. Creation still requires its source.
 IF a.return_base_url IS NULL OR (source IS NULL AND coalesce(a.session_id,p_session) IS NULL AND a.reservation_expires_at>clock_timestamp()) THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds' WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'returnBaseUrl',a.return_base_url,'sessionId',coalesce(a.session_id,p_session),'refundCursor',a.refund_cursor,
   'sessionLookupCursor',a.session_lookup_cursor,'sessionLookupFound',a.session_lookup_found));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) TO service_role;
