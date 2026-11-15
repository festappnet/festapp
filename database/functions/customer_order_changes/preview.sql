-- One domain projection serves customer UI, confirmation and email context.
CREATE OR REPLACE FUNCTION public.customer_change_read_scope_internal(p_token text,p_order bigint)
RETURNS eshop.waitlist_capabilities LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.waitlist_capabilities;
BEGIN
 IF p_token IS NULL OR p_token!~'^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY' USING ERRCODE='42501'; END IF;
 SELECT cap.* INTO c FROM eshop.waitlist_capabilities cap JOIN eshop.orders o ON o.id=cap.order_id
 JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion JOIN public.occasions oc ON oc.id=o.occasion
 WHERE cap.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND cap.kind='order_view'
 AND cap.order_id=p_order AND cap.form_id=f.id AND cap.organization_id=oc.organization
 AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp();
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY' USING ERRCODE='42501'; END IF;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION public.customer_change_read_scope_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_change_requests_internal(p_order bigint,p_staff boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'operation',operation,'status',status,
 'reason',reason,'response',response,'ticketIds',to_jsonb(ticket_ids),'targetFormId',target_form_id,'createdAt',created_at,'updatedAt',updated_at,
 'canWithdraw',status='open' AND public.customer_order_feature_enabled_internal((SELECT form FROM eshop.orders WHERE id=p_order)),'canDecide',p_staff AND status='open') ORDER BY created_at DESC),'[]')
 FROM eshop.customer_order_change_requests WHERE order_id=p_order;
$$;
REVOKE ALL ON FUNCTION public.customer_order_change_requests_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_actions_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; policy jsonb; op text; rule jsonb; actions jsonb:='[]'; enabled boolean; reason text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 policy:=public.customer_order_policy_internal(o.form)->'policy';
 FOREACH op IN ARRAY ARRAY['cancel','move'] LOOP
  rule:=policy->op;
  enabled:=public.customer_order_operation_enabled_internal(o.form,op);
  reason:=CASE WHEN NOT enabled THEN 'policy_unavailable'
   WHEN o.state NOT IN ('ordered','created','paid','sent') THEN 'order_unavailable'
   WHEN EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=op AND status='open') THEN 'request_pending'
   WHEN o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=o.id)
    OR EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted') THEN 'waitlist_family'
   ELSE NULL END;
  actions:=actions||jsonb_build_array(jsonb_build_object('operation',op,'enabled',reason IS NULL,'reason',reason,
   'allowedUntil',rule->'allowed_until','mode',rule->'mode','reasonRequired',rule->'reason_required',
   'refundMode',rule->'refund_mode','tickets',CASE WHEN op='cancel' AND reason IS NULL THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,o.form)) ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t WHERE t.state NOT IN ('used','storno','expired','stock','waitlisted','preparing_payment')) ELSE '[]'::jsonb END,'fields',CASE WHEN op='edit' AND reason IS NULL THEN (
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'type',f.type,'title',f.title,'required',f.is_required,
     'ticket',f.is_ticket_field,'options',f.data->'options',
     'value',(SELECT answer->f.id::text FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) answer WHERE answer ? f.id::text LIMIT 1),
     'values',(SELECT jsonb_agg(jsonb_build_object('ticketId',t.id,'value',(SELECT answer->f.id::text FROM jsonb_array_elements(coalesce(t.data->'fields','[]')) answer WHERE answer ? f.id::text LIMIT 1)) ORDER BY t.id) FROM public.get_order_tickets_internal(o.id) t))),'[]') FROM public.form_fields f
    JOIN jsonb_array_elements(rule->'fields') allow ON (allow->>'id')::bigint=f.id AND allow->>'type'=f.type
    WHERE f.form=o.form AND NOT coalesce(f.is_hidden,false) AND f.product_type IS NULL) END,
   'targets',CASE WHEN op='move' AND reason IS NULL THEN public.customer_move_targets_internal(o.id) ELSE '[]'::jsonb END));
 END LOOP;
 RETURN actions;
END $$;
REVOKE ALL ON FUNCTION public.customer_order_actions_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_staff boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; rule jsonb; rev bigint; effect text; blocked text; reason text;
 f public.form_fields; ticket_id bigint; patch record; finance jsonb; amount numeric:=0; target jsonb;
 selected bigint[]; partial boolean:=false; selected_price numeric;
 snapshot jsonb; fields jsonb; current_value jsonb; all_payload jsonb;
BEGIN
 IF p_operation='edit' THEN RAISE insufficient_privilege USING MESSAGE='CUSTOMER_ANSWERS_READ_ONLY'; END IF;
 IF p_operation IS NULL OR p_operation NOT IN ('edit','cancel','move','withdraw') OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
  OR octet_length(p_payload::text)>32768 THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_CHANGE_INPUT_INVALID'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 SELECT revision,policy->p_operation INTO rev,rule FROM eshop.customer_order_change_policies WHERE form_id=o.form;
 IF NOT p_staff AND NOT (CASE WHEN p_operation='withdraw' THEN public.customer_order_feature_enabled_internal(o.form) ELSE public.customer_order_operation_enabled_internal(o.form,p_operation) END) THEN
  RAISE insufficient_privilege USING MESSAGE='CUSTOMER_CHANGE_UNAVAILABLE'; END IF;
 IF p_operation='withdraw' THEN
  IF p_payload-ARRAY['requestId']<>'{}'::jsonb OR NOT EXISTS(SELECT 1 FROM eshop.customer_order_change_requests
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open') THEN
   RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  effect:='withdraw';
 ELSE
  IF NOT p_staff AND p_operation IN ('cancel','move') AND EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open') THEN RAISE EXCEPTION 'CUSTOMER_REQUEST_ALREADY_OPEN' USING ERRCODE='40001'; END IF;
  IF o.state NOT IN ('created','ordered','paid','sent') OR o.source_waitlist_order_id IS NOT NULL
   OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=o.id)
   OR EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state IN ('waitlisted','stock','preparing_payment')) THEN
   RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
  IF p_operation='cancel' AND p_payload ? 'ticketIds' THEN
   IF jsonb_typeof(p_payload->'ticketIds') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'ticketIds') NOT BETWEEN 1 AND 1000
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'ticketIds') id WHERE jsonb_typeof(id)<>'number' OR id::text!~'^[1-9][0-9]*$') THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_TICKET_SELECTION_INVALID'; END IF;
   SELECT array_agg(value::bigint ORDER BY value::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds');
   IF cardinality(selected)<>(SELECT count(DISTINCT id) FROM unnest(selected) id) OR EXISTS(SELECT 1 FROM unnest(selected) chosen(id) WHERE NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=chosen.id AND t.state NOT IN ('storno','expired','stock','waitlisted','preparing_payment'))) THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_TICKET_SELECTION_INVALID'; END IF;
   IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=ANY(selected) AND x."order"<>o.id) THEN RAISE insufficient_privilege USING MESSAGE='CUSTOMER_TICKET_SCOPE_INVALID'; END IF;
   partial:=cardinality(selected)<(SELECT count(*) FROM public.get_order_tickets_internal(o.id) WHERE state NOT IN ('storno','expired'));
  ELSE SELECT array_agg(id ORDER BY id) INTO selected FROM public.get_order_tickets_internal(o.id); END IF;
  -- Mutability/print guards below are translated into a request only for a
  -- supported request operation. No exception can commit a partial mutation.
  IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='used' AND id=ANY(selected)) THEN blocked:='used_ticket'; END IF;
  BEGIN
   PERFORM public.check_batch_ticket_print_immutable_internal(selected);
  EXCEPTION WHEN SQLSTATE '55000' THEN blocked:='immutable_print'; END;
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=o.id AND (data ? 'fakturoid_invoice_id' OR data ? 'invoice_id'))
   OR EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=oc.unit AND type='FAKTUROID')
   OR EXISTS(SELECT 1 FROM eshop.replacement_invoice_preparations WHERE order_id=o.id AND state NOT IN ('failed','cancelled')) THEN blocked:='invoice_review'; END IF;
  -- All provider/bank/cash facts and reservations come from the existing engine.
  finance:=public.payment_method_context_internal(o.id);
  amount:=coalesce((finance->>'net')::numeric,0);
  IF p_operation='edit' THEN
   IF blocked IS NOT NULL THEN RAISE EXCEPTION 'CUSTOMER_ORDER_UNAVAILABLE' USING ERRCODE='40001'; END IF;
   IF (coalesce(p_payload->'order','{}')='{}'::jsonb AND coalesce(p_payload->'tickets','{}')='{}'::jsonb) OR p_payload-ARRAY['order','tickets']<>'{}'::jsonb OR (NOT p_payload ? 'order' AND NOT p_payload ? 'tickets')
    OR (p_payload ? 'order' AND jsonb_typeof(p_payload->'order')<>'object')
    OR (p_payload ? 'tickets' AND jsonb_typeof(p_payload->'tickets')<>'object') THEN
    RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
   FOR ticket_id,fields IN
    SELECT NULL::bigint,coalesce(p_payload->'order','{}') UNION ALL
    SELECT key::bigint,value FROM jsonb_each(coalesce(p_payload->'tickets','{}'))
   LOOP
    IF jsonb_typeof(fields)<>'object' OR (ticket_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE id=ticket_id)) THEN
     RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
    FOR patch IN SELECT * FROM jsonb_each(fields) LOOP
     SELECT * INTO f FROM public.form_fields WHERE form=o.form AND id::text=patch.key
      AND coalesce(is_ticket_field,false)=(ticket_id IS NOT NULL) AND NOT coalesce(is_hidden,false) AND product_type IS NULL;
     IF f.id IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(rule->'fields','[]')) a WHERE a->>'id'=f.id::text AND a->>'type'=f.type)
      OR f.type NOT IN ('name','surname','phone','text','city','address','select_one')
      OR jsonb_typeof(patch.value) IS DISTINCT FROM 'string' OR length(patch.value#>>'{}')>4000
      OR (f.is_required AND nullif(btrim(patch.value#>>'{}'),'') IS NULL)
      OR (f.type='select_one' AND patch.value NOT IN ('""'::jsonb,'null'::jsonb) AND NOT EXISTS(
        SELECT 1 FROM jsonb_array_elements(coalesce(f.data->'options','[]')) option WHERE option->'value'=patch.value)) THEN
      RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_FIELDS_INVALID'; END IF;
    END LOOP;
   END LOOP;
   effect:='edit';
  ELSIF p_operation='cancel' THEN
   IF p_payload-ARRAY['reason','ticketIds']<>'{}'::jsonb OR (p_payload ? 'reason' AND jsonb_typeof(p_payload->'reason')<>'string') THEN
    RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_CHANGE_INPUT_INVALID'; END IF;
   reason:=public.validate_customer_cancellation_reason_internal(rule,p_payload->>'reason');
   effect:=CASE WHEN NOT p_staff AND rule->>'mode'='approval_required' THEN 'request_cancel'
    WHEN blocked IS NOT NULL THEN 'request_cancel' ELSE 'cancel' END;
   IF amount>0 THEN
    IF rule->>'refund_mode'='none' THEN effect:='request_cancel';blocked:='paid_order_requires_review';
    ELSIF rule->>'refund_mode'='manual' THEN effect:=CASE WHEN effect='cancel' THEN 'cancel_manual_refund' ELSE effect END;
    ELSIF effect='cancel' THEN
     IF finance->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb OR (finance->>'pending')::numeric<>0
      OR (finance->>'available')::numeric IS DISTINCT FROM amount
      OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required')
      OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb
      OR NOT EXISTS(SELECT 1 FROM eshop.payment_info pi JOIN eshop.payment_providers pp ON pp.provider_key=pi.payment_method
        WHERE pi.id=o.payment_info AND pp.hosted_checkout AND pp.refund_write_supported AND pp.refund_write_enabled
        AND public.payment_provider_call_internal(pi.payment_method,'refund_binding',jsonb_build_object('orderId',o.id)) IS NOT NULL) THEN
       effect:='request_cancel';blocked:='refund_requires_review';
     ELSE effect:='cancel_refund'; END IF;
    END IF;
   ELSIF amount<0 OR finance->'invalidIdentity'='true'::jsonb OR coalesce((finance->>'pending')::numeric,0)>0
    OR EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND public.payment_method_is_online_internal(pi.payment_method)) THEN
    -- No-money online checkout may still collect. Customer cannot manufacture
    -- provider expiry or free a reservation while collection is uncertain.
    effect:='request_cancel';blocked:='collection_unresolved';
   END IF;
   IF partial THEN
    -- The existing bank/cash partial-cancellation owner reduces only selected
    -- sale lines. Online admission/refund selection stays with its provider owner.
    SELECT coalesce(sum((product->>'price')::numeric),0) INTO selected_price FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) ticket CROSS JOIN LATERAL jsonb_array_elements(coalesce(ticket->'products','[]')) product WHERE (ticket->>'id')::bigint=ANY(selected);
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi WHERE pi.id=o.payment_info AND (public.payment_method_is_online_internal(pi.payment_method) OR pi.deposit_amount IS NOT NULL)) OR (amount>0 AND amount<o.price) OR o.data ? 'discount' OR selected_price<0 OR selected_price>o.price THEN effect:='request_cancel';blocked:='partial_finance_requires_review'; END IF;
    BEGIN PERFORM public.assert_order_discount_unchanged_internal(o.id);
    EXCEPTION WHEN raise_exception THEN IF SQLERRM='DISCOUNTED_ORDER_PRICE_IMMUTABLE' THEN effect:='request_cancel';blocked:='discount_requires_review'; ELSE RAISE;END IF;END;
    IF (SELECT count(*) FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) sale_ticket WHERE (sale_ticket->>'id')::bigint=ANY(selected))<>cardinality(selected)
     OR (SELECT coalesce(sum((product->>'price')::numeric),0) FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) sale_ticket CROSS JOIN LATERAL jsonb_array_elements(coalesce(sale_ticket->'products','[]')) product) IS DISTINCT FROM o.price THEN effect:='request_cancel';blocked:='partial_snapshot_requires_review'; END IF;
    amount:=least(greatest(amount,0),selected_price);
   END IF;
   BEGIN PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x.ticket=ANY(selected)));
   EXCEPTION WHEN invalid_parameter_value OR check_violation THEN effect:='request_cancel';blocked:='seat_selection_requires_review'; END;
   IF finance->'invalidIdentity'='true'::jsonb OR coalesce((finance->>'pending')::numeric,0)>0
    OR public.provider_order_payment_projection_internal(o.id)->>'status' IN ('disputed','unknown','action_required')
    OR public.provider_order_payment_projection_internal(o.id)->'reconciliationPending'='true'::jsonb THEN
    effect:='request_cancel';blocked:='finance_requires_review'; END IF;
  ELSE
   IF p_payload-ARRAY['targetFormId','reason']<>'{}'::jsonb OR jsonb_typeof(p_payload->'targetFormId') IS DISTINCT FROM 'number'
    OR length(coalesce(p_payload->>'reason',''))>2000 THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_MOVE_INVALID'; END IF;
   target:=public.customer_move_preview_internal(o.id,(p_payload->>'targetFormId')::bigint);
   effect:=CASE WHEN blocked IS NULL AND target->'automatic'='true'::jsonb THEN 'move' ELSE 'request_move' END;
   blocked:=coalesce(blocked,target->>'reason');
  END IF;
 END IF;
 snapshot:=jsonb_build_object('form',o.form,'state',o.state,'data',o.data,'price',o.price,'payment',o.payment_info,
  'policyRevision',rev,'epoch',oc.customer_self_service_epoch,'effect',effect,'payload',p_payload,'finance',finance-ARRAY['methods','requests'],
  'refunds',(SELECT jsonb_agg(jsonb_build_object('id',rr.id,'status',rr.status,'amount',rr.amount) ORDER BY rr.id) FROM eshop.refund_requests rr WHERE rr.order_id=o.id),
  'requests',public.customer_order_change_requests_internal(o.id),
  'definitions',(SELECT jsonb_agg(to_jsonb(definition) ORDER BY definition.id) FROM public.form_fields definition WHERE definition.form=o.form),
  'allocations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM eshop.order_product_ticket x WHERE x."order"=o.id),
  'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.get_order_tickets_internal(o.id) t),'target',target);
 RETURN jsonb_build_object('code',200,'operation',p_operation,'effect',effect,'reason',blocked,'refundAmount',CASE WHEN effect='cancel_refund' THEN amount ELSE 0 END,
  'partial',partial,'ticketIds',to_jsonb(selected),'currency',o.currency_code,'target',target,'policyRevision',rev,'expiresAt',statement_timestamp()+interval '5 minutes',
  'fingerprint',encode(extensions.digest(snapshot::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.preview_customer_order_change_internal(bigint,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
