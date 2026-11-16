-- An omitted cancellation deadline follows the current occasion start; explicit deadlines retain precedence.

-- SOURCE: customer_order_changes/policy.sql
-- Private policy owner. The existing receipted form save is the only writer.
-- Lock hierarchy: blueprint scope fence -> capacity/forms in ascending ID ->
-- products in ascending ID -> order -> payment -> provider attempt -> tickets.
-- Payment operations additionally take their organization policy fence first.
-- Feature and form policy writes share the blueprint fence with customer commands.

CREATE OR REPLACE FUNCTION public.normalize_customer_order_policy_internal(p_policy jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE op record; rule jsonb; field jsonb; result jsonb:='{}';
BEGIN
 IF p_policy IS NULL OR jsonb_typeof(p_policy)<>'object' OR octet_length(p_policy::text)>16384
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_policy) k WHERE k NOT IN ('edit','cancel')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid customer change policy'; END IF;
 FOR op IN SELECT * FROM jsonb_each(p_policy) LOOP
  rule:=op.value;
  IF jsonb_typeof(rule)<>'object' OR jsonb_typeof(rule->'enabled') IS DISTINCT FROM 'boolean'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(rule) k WHERE k NOT IN ('enabled','allowed_until',
     'fields','mode','reason_required','refund_mode')) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid customer operation policy'; END IF;
  IF (op.key<>'cancel' AND rule->'enabled'='true'::jsonb) OR rule ? 'allowed_until' THEN
   IF jsonb_typeof(rule->'allowed_until') IS DISTINCT FROM 'string'
    OR rule->>'allowed_until' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
    RAISE invalid_parameter_value USING MESSAGE='customer operation deadline required'; END IF;
   PERFORM (rule->>'allowed_until')::timestamptz;
  END IF;
  IF op.key='cancel' THEN
   IF rule->>'mode' IS NULL OR rule->>'mode' NOT IN ('automatic','approval_required')
    OR jsonb_typeof(rule->'reason_required') IS DISTINCT FROM 'boolean'
    OR rule->>'refund_mode' IS NULL OR rule->>'refund_mode' NOT IN ('none','automatic','manual') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid cancellation mode'; END IF;
   IF rule ?| ARRAY['fields','targets'] THEN RAISE invalid_parameter_value USING MESSAGE='invalid cancellation keys'; END IF;
  ELSIF op.key='edit' THEN
   IF rule ?| ARRAY['mode','reason_required','refund_mode','targets'] OR jsonb_typeof(rule->'fields') IS DISTINCT FROM 'array'
    OR jsonb_array_length(rule->'fields')>100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid customer editable fields'; END IF;
   FOR field IN SELECT value FROM jsonb_array_elements(rule->'fields') LOOP
    IF jsonb_typeof(field)<>'object' OR NOT field ?& ARRAY['id','type'] OR field-ARRAY['id','type']<>'{}'::jsonb
     OR jsonb_typeof(field->'id') IS DISTINCT FROM 'number' OR field->>'id' !~ '^[0-9]+$'
     OR field->>'type' IS NULL OR field->>'type' NOT IN ('name','surname','phone','text','city','address','select_one') THEN
     RAISE invalid_parameter_value USING MESSAGE='customer field not editable'; END IF;
   END LOOP;
   IF (SELECT count(*) FROM jsonb_array_elements(rule->'fields'))<>(SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(rule->'fields')) THEN
    RAISE invalid_parameter_value USING MESSAGE='duplicate customer field'; END IF;
  END IF;
  result:=result||jsonb_build_object(op.key,rule);
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.normalize_customer_order_policy_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_customer_order_policy_internal(p_form bigint,p_policy jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE normalized jsonb; previous jsonb; fid bigint; rule jsonb; field jsonb; automatic_refund boolean;
BEGIN
 normalized:=public.normalize_customer_order_policy_internal(p_policy);
 automatic_refund:=normalized#>'{cancel,enabled}'='true'::jsonb AND normalized#>>'{cancel,refund_mode}'='automatic';
 IF public.can_manage_customer_order_policy(p_form,coalesce(automatic_refund,false)) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='customer policy editor required'; END IF;
 SELECT occasion INTO STRICT fid FROM public.forms WHERE id=p_form;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[fid]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 FOR field IN SELECT value FROM jsonb_array_elements(coalesce(normalized#>'{edit,fields}','[]')) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.form_fields f WHERE f.form=p_form AND f.id=(field->>'id')::bigint
    AND f.type=field->>'type' AND NOT coalesce(f.is_hidden,false) AND f.product_type IS NULL) THEN
   RAISE invalid_parameter_value USING MESSAGE='customer field scope or type invalid'; END IF;
 END LOOP;
 -- Submitted answers are customer read-only in this release, including contact
 -- fields. Retain legacy input validation but never persist an enabled edit rule.
 IF normalized ? 'edit' THEN normalized:=jsonb_set(normalized,'{edit}','{"enabled":false,"fields":[]}'::jsonb); END IF;
 SELECT policy INTO previous FROM eshop.customer_order_change_policies WHERE form_id=p_form FOR UPDATE;
 IF previous IS NOT DISTINCT FROM normalized THEN RETURN; END IF;
 INSERT INTO eshop.customer_order_change_policies(form_id,revision,policy,updated_by)
 VALUES(p_form,1,normalized,auth.uid()) ON CONFLICT(form_id) DO UPDATE
 SET revision=eshop.customer_order_change_policies.revision+1,policy=excluded.policy,
  updated_at=clock_timestamp(),updated_by=auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.save_customer_order_policy_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_policy_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT jsonb_build_object('revision',revision,'policy',policy)
 FROM eshop.customer_order_change_policies WHERE form_id=p_form),'{"revision":0,"policy":{}}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.customer_order_policy_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- This predicate is only a policy gate, never proof of customer ownership.
CREATE OR REPLACE FUNCTION public.customer_order_operation_enabled_internal(p_form bigint,p_operation text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.policy#>ARRAY[p_operation,'enabled']='true'::jsonb
  AND coalesce(nullif(p.policy#>>ARRAY[p_operation,'allowed_until'],'')::timestamptz,o.start_time)>statement_timestamp()
  AND jsonb_path_exists(coalesce(o.features,'[]'),'$[*] ? (@.code == "customer_self_service" && @.is_enabled == true)')
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN eshop.customer_order_change_policies p ON p.form_id=f.id
  WHERE f.id=p_form AND p_operation='cancel'),false);
$$;
REVOKE ALL ON FUNCTION public.customer_order_operation_enabled_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- A reason belongs only in the scoped request, never in technical audit payloads.
CREATE OR REPLACE FUNCTION public.validate_customer_cancellation_reason_internal(p_rule jsonb,p_reason text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE reason text:=nullif(btrim(p_reason),'');
BEGIN
 IF jsonb_typeof(p_rule->'reason_required') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid cancellation reason policy'; END IF;
 IF length(reason)>2000 OR (p_rule->'reason_required'='true'::jsonb AND reason IS NULL) THEN
  RAISE invalid_parameter_value USING MESSAGE='cancellation reason required or too long'; END IF;
 RETURN reason;
END $$;
REVOKE ALL ON FUNCTION public.validate_customer_cancellation_reason_internal(jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_order_feature_enabled_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT jsonb_path_exists(coalesce(o.features,'[]'),'$[*] ? (@.code == "customer_self_service" && @.is_enabled == true)')
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form),false);
$$;
REVOKE ALL ON FUNCTION public.customer_order_feature_enabled_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: customer_order_changes/preview.sql
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
 'reason',reason,'response',response,'ticketIds',to_jsonb(ticket_ids),'createdAt',created_at,'updatedAt',updated_at,
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
 FOREACH op IN ARRAY ARRAY['cancel'] LOOP
  rule:=policy->op;
  enabled:=public.customer_order_operation_enabled_internal(o.form,op);
  reason:=CASE WHEN NOT enabled THEN 'policy_unavailable'
   WHEN o.state NOT IN ('ordered','created','paid','sent') THEN 'order_unavailable'
   WHEN EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=op AND status='open') THEN 'request_pending'
   WHEN o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=o.id)
    OR EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted') THEN 'waitlist_family'
   ELSE NULL END;
  actions:=actions||jsonb_build_array(jsonb_build_object('operation',op,'enabled',reason IS NULL,'reason',reason,
   'allowedUntil',coalesce(nullif(rule->>'allowed_until','')::timestamptz,(SELECT start_time FROM public.occasions WHERE id=o.occasion)),'mode',rule->'mode','reasonRequired',rule->'reason_required',
   'refundMode',rule->'refund_mode','tickets',CASE WHEN op='cancel' AND reason IS NULL THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,o.form)) ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t WHERE t.state NOT IN ('used','storno','expired','stock','waitlisted','preparing_payment')) ELSE '[]'::jsonb END));
 END LOOP;
 RETURN actions;
END $$;
REVOKE ALL ON FUNCTION public.customer_order_actions_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_staff boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; rule jsonb; rev bigint; effect text; blocked text; reason text;
 f public.form_fields; ticket_id bigint; patch record; finance jsonb; amount numeric:=0;
 selected bigint[]; partial boolean:=false; selected_price numeric;
 snapshot jsonb; fields jsonb; current_value jsonb; all_payload jsonb;
BEGIN
 IF p_operation='edit' THEN RAISE insufficient_privilege USING MESSAGE='CUSTOMER_ANSWERS_READ_ONLY'; END IF;
 IF p_operation IS NULL OR p_operation NOT IN ('cancel','withdraw') OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
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
  IF NOT p_staff AND p_operation='cancel' AND EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open') THEN RAISE EXCEPTION 'CUSTOMER_REQUEST_ALREADY_OPEN' USING ERRCODE='40001'; END IF;
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
  IF p_operation='cancel' THEN
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
  END IF;
 END IF;
 snapshot:=jsonb_build_object('form',o.form,'state',o.state,'data',o.data,'price',o.price,'payment',o.payment_info,
  'policyRevision',rev,'epoch',oc.customer_self_service_epoch,'effect',effect,'payload',p_payload,'finance',finance-ARRAY['methods','requests'],
  'refunds',(SELECT jsonb_agg(jsonb_build_object('id',rr.id,'status',rr.status,'amount',rr.amount) ORDER BY rr.id) FROM eshop.refund_requests rr WHERE rr.order_id=o.id),
  'requests',public.customer_order_change_requests_internal(o.id),
  'definitions',(SELECT jsonb_agg(to_jsonb(definition) ORDER BY definition.id) FROM public.form_fields definition WHERE definition.form=o.form),
  'allocations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM eshop.order_product_ticket x WHERE x."order"=o.id),
  'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.get_order_tickets_internal(o.id) t));
 RETURN jsonb_build_object('code',200,'operation',p_operation,'effect',effect,'reason',blocked,'refundAmount',CASE WHEN effect='cancel_refund' THEN amount ELSE 0 END,
  'partial',partial,'ticketIds',to_jsonb(selected),'currency',o.currency_code,'policyRevision',rev,'expiresAt',statement_timestamp()+interval '5 minutes',
  'fingerprint',encode(extensions.digest(snapshot::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.preview_customer_order_change_internal(bigint,text,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
