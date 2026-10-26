CREATE OR REPLACE FUNCTION public.decide_stripe_partial_refund_client_sync_v1(
 p_order bigint,p_action text,p_tickets bigint[],p_note text,p_expected_refunded_minor bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); o eshop.orders; a eshop.stripe_checkout_attempts; totals record; v_occasion bigint;
 hash text; claim jsonb; ids bigint[]; before_users uuid[]; revision text; decision uuid; card_refunded bigint;
BEGIN
 SELECT ord.occasion INTO v_occasion FROM eshop.orders ord WHERE ord.id=p_order;
 IF actor IS NULL OR v_occasion IS NULL OR NOT coalesce(public.can_write_orders(v_occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions occasion JOIN public.user_info viewer ON viewer.organization=occasion.organization AND viewer.id=actor WHERE occasion.id=v_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('keep','cancel_selected') OR p_command_id IS NULL
  OR nullif(trim(p_note),'') IS NULL OR length(trim(p_note)) NOT BETWEEN 3 AND 500
  OR p_expected_refunded_minor IS NULL THEN RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(coalesce(p_tickets,'{}'::bigint[])) id ORDER BY id);
 IF (p_action='keep' AND cardinality(ids)<>0) OR (p_action='cancel_selected' AND cardinality(ids) NOT BETWEEN 1 AND 1000) THEN
  RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'action',p_action,'tickets',ids,
  'note',trim(p_note),'refundedMinor',p_expected_refunded_minor)::text,'sha256'),'hex');
 claim:=public.begin_client_mutation_v1(p_command_id,'inventory.order.stripe_refund_decision',v_occasion,actor,hash);
 IF claim->>'disposition'='replay' THEN RETURN claim->'response'; END IF;
 PERFORM public.admit_order_mutation_v1(v_occasion,greatest(cardinality(ids),1));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(a.payment_info_id);
 SELECT coalesce(sum(amount_minor),0) INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF card_refunded IS DISTINCT FROM p_expected_refunded_minor THEN RAISE EXCEPTION 'STRIPE_REFUND_REVISION_CHANGED'; END IF;
 IF card_refunded<=0 OR card_refunded>=a.amount_minor OR a.state<>'paid' OR o.state NOT IN ('paid','sent')
  OR totals.invalid_identity OR a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND id=a.payment_info_id AND payment_method='stripe' AND stripe_connection_id=a.connection_id) THEN
  RAISE EXCEPTION 'STRIPE_PARTIAL_REFUND_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(ids) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id
  WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'STRIPE_REFUND_TICKET_UNAVAILABLE'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
 SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(provider_id,amount_minor) ORDER BY provider_id)::text,'[]'),'sha256'),'hex')
 INTO revision FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF p_action='cancel_selected' THEN
  PERFORM public.internal_storno_tickets_221(ids);
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN
   PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 END IF;
 INSERT INTO eshop.stripe_admission_decisions(attempt_id,actor,reason,ticket_ids,provider_revision)
 VALUES(a.id,actor,CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,ids,revision) RETURNING id INTO decision;
 INSERT INTO eshop.orders_history("order",state,price,data) VALUES(o.id,o.state,o.price,jsonb_build_object('action','stripe_partial_refund_decision',
  'decisionId',decision,'actor',actor,'ticketIds',ids,'note',trim(p_note),'providerRevision',revision));
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,v_occasion,'inventory.order.stripe_refund_decision',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','safeLabel','Refund admission decision',
   'changedFields',jsonb_build_array('tickets','admission','allocations'))),before_users,
  jsonb_build_object('decisionId',decision,'payment',public.stripe_order_payment_projection_internal(o.id)));
END $$;
REVOKE ALL ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) TO authenticated;
