-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
