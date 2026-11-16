-- Canonical cancellation-only self-service. Guarded retirement of unused term-moving capability.

-- SOURCE: customer_order_changes/retire_move_preflight.sql
-- Fence writers before checking: a concurrent old-client write must be seen.
LOCK TABLE public.forms, eshop.customer_order_change_policies, eshop.customer_order_change_capabilities, eshop.customer_order_change_requests, eshop.customer_order_change_events IN ACCESS EXCLUSIVE MODE;
-- Never discard a term, credential or business history during this cutover.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.forms WHERE term_start_at IS NOT NULL OR term_end_at IS NOT NULL)
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE operation='move' OR target_form_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_capabilities WHERE operation='move')
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_events WHERE operation='move')
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_policies WHERE policy#>'{move,enabled}'='true'::jsonb) THEN
  RAISE EXCEPTION 'Term-moving state requires explicit preservation before cutover';
 END IF;
END $$;

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
  IF rule->'enabled'='true'::jsonb OR rule ? 'allowed_until' THEN
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
  AND nullif(p.policy#>>ARRAY[p_operation,'allowed_until'],'')::timestamptz>statement_timestamp()
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
   'allowedUntil',rule->'allowed_until','mode',rule->'mode','reasonRequired',rule->'reason_required',
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

-- SOURCE: customer_order_changes/commands.sql
CREATE OR REPLACE FUNCTION public.lock_customer_order_change_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; fid bigint;
BEGIN
 SELECT occasion,form INTO oc.id,fid FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=oc.id;
 PERFORM public.payment_policy_fence_internal(oc.organization);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[oc.id]);
 PERFORM 1 FROM public.forms WHERE id=fid AND occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=p_order FOR UPDATE;
 -- Form saves take this same occasion fence before their product locks.
 PERFORM 1 FROM eshop.products WHERE occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=p_order) FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT id FROM public.get_order_tickets_internal(p_order)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_customer_order_change_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.publish_customer_order_request_internal(p_request uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; oc public.occasions;
BEGIN
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT occ.* INTO STRICT oc FROM public.occasions occ JOIN eshop.orders o ON o.occasion=occ.id WHERE o.id=r.order_id;
 -- Request reasons/answers never enter notification payloads or technical audit.
 PERFORM public.notification_center_order_internal(r.order_id,'customer_order_request','customer-request:'||r.id||':'||r.status,
  NULL,jsonb_build_object('customerRequestId',r.id,'customerRequestOperation',r.operation,'customerRequestStatus',r.status));
END $$;
REVOKE ALL ON FUNCTION public.publish_customer_order_request_internal(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_customer_order_change_internal(p_order bigint,p_operation text,p_payload jsonb,p_preview jsonb,p_command uuid,p_existing_request uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; effect text:=p_preview->>'effect'; request_id uuid:=p_existing_request;
 item record; t eshop.tickets; merged jsonb; fields jsonb; result jsonb; request_status text:='open';
BEGIN
 IF p_operation='edit' THEN RAISE insufficient_privilege USING MESSAGE='CUSTOMER_ANSWERS_READ_ONLY'; END IF;
 IF p_operation IS NULL OR p_operation NOT IN ('cancel','withdraw') THEN RAISE invalid_parameter_value USING MESSAGE='CUSTOMER_CHANGE_INPUT_INVALID'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF effect IN ('request_cancel','cancel_manual_refund') OR (p_operation='cancel' AND nullif(btrim(p_payload->>'reason'),'') IS NOT NULL) THEN
  IF effect IN ('cancel_manual_refund','cancel_refund') THEN request_status:='approved'; ELSIF effect='cancel' THEN request_status:='resolved'; END IF;
  IF p_existing_request IS NULL THEN
  INSERT INTO eshop.customer_order_change_requests(order_id,organization_id,operation,reason,customer_command,status,ticket_ids)
  VALUES(o.id,oc.organization,p_operation,nullif(btrim(p_payload->>'reason'),''),p_command,request_status,CASE WHEN p_payload ? 'ticketIds' THEN ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'ticketIds')) END)
  ON CONFLICT(order_id,operation) WHERE status='open' DO NOTHING RETURNING id INTO request_id;
  IF request_id IS NULL THEN SELECT id INTO request_id FROM eshop.customer_order_change_requests WHERE order_id=o.id AND operation=p_operation AND status='open'; END IF;
  PERFORM public.publish_customer_order_request_internal(request_id);
  END IF;
 END IF;
 IF effect IN ('cancel','cancel_refund','cancel_manual_refund') THEN
  IF effect='cancel_refund' THEN
   PERFORM public.prepare_order_refund_internal(o.id,(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info),
    (p_preview->>'refundAmount')::numeric,p_command,'{}');
   INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(p_command,'prepare_refund',auth.uid(),jsonb_build_object('source','customer_order_change','commandId',p_command));
  END IF;
  IF p_preview->'partial'='true'::jsonb THEN
   PERFORM public.cancel_ticket_selection_domain_internal(ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_preview->'ticketIds')),true);
  ELSIF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
   PERFORM public.cancel_online_order_admission_internal(o.id,'storno');
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
   PERFORM public.notification_center_order_state_internal(o.id);
   PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit);
  ELSE PERFORM public.cancel_order_domain_internal_v1(o.id,true); END IF;
  PERFORM public.enqueue_order_wallet_internal(o.id);
 ELSIF effect='withdraw' THEN
  UPDATE eshop.customer_order_change_requests SET status='withdrawn',updated_at=clock_timestamp()
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open' RETURNING id INTO request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 END IF;
 IF (effect IN ('request_cancel','withdraw') OR p_preview->'partial'='true'::jsonb) AND (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-change:'||p_command);
 END IF;
 INSERT INTO eshop.customer_order_change_events(command_id,order_id,operation,outcome,request_id)
 VALUES(p_command,o.id,p_operation,effect,request_id);
 RETURN jsonb_build_object('code',200,'effect',effect,'requestId',request_id,'orderId',o.id);
END $$;
REVOKE ALL ON FUNCTION public.apply_customer_order_change_internal(bigint,text,jsonb,jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.customer_order_change_gateway(p_action text,p_token text,p_order bigint DEFAULT NULL,
 p_operation text DEFAULT NULL,p_payload jsonb DEFAULT '{}',p_command uuid DEFAULT NULL,p_fingerprint text DEFAULT NULL,
 p_delivery jsonb DEFAULT NULL,p_ip_hash text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE parent eshop.waitlist_capabilities; cap eshop.customer_order_change_capabilities;
 o eshop.orders; oc public.occasions; preview jsonb; limits eshop.customer_order_change_limits; receipt jsonb; result jsonb; users uuid[];
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_action IS NULL OR p_action NOT IN ('challenge_context','challenge','resolve','preview','command') THEN RAISE invalid_parameter_value; END IF;
 IF p_action IN ('challenge_context','challenge') THEN
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  PERFORM public.lock_customer_order_change_internal(parent.order_id);
  parent:=public.customer_change_read_scope_internal(p_token,p_order);
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=parent.order_id;
  SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
  preview:=public.preview_customer_order_change_internal(o.id,p_operation,p_payload);
  IF p_action='challenge' THEN
   IF p_ip_hash IS NULL OR p_ip_hash!~'^[a-f0-9]{64}$' OR p_delivery->>'tokenHash' IS NULL OR p_delivery->>'tokenHash'!~'^[a-f0-9]{64}$'
    OR jsonb_typeof(p_delivery->'source') IS DISTINCT FROM 'object' OR jsonb_typeof(p_delivery->'email') IS DISTINCT FROM 'object'
    OR p_delivery->>'contentHash' IS NULL OR p_delivery->>'contentHash'!~'^[a-f0-9]{64}$' THEN RAISE invalid_parameter_value; END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-order:'||o.id,0));
   PERFORM pg_advisory_xact_lock(hashtextextended('customer-change-ip:'||p_ip_hash,0));
   SELECT * INTO STRICT limits FROM eshop.customer_order_change_limits WHERE singleton;
   IF EXISTS(SELECT 1 FROM eshop.customer_order_change_attempts WHERE (order_id=o.id OR ip_hash=p_ip_hash)
     AND created_at>clock_timestamp()-make_interval(secs=>limits.minimum_seconds))
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE order_id=o.id AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit
    OR (SELECT count(*) FROM eshop.customer_order_change_attempts WHERE ip_hash=p_ip_hash AND created_at>clock_timestamp()-interval '1 hour')>=limits.hourly_limit THEN
     RETURN jsonb_build_object('code',202); END IF;
   INSERT INTO eshop.customer_order_change_attempts(order_id,ip_hash) VALUES(o.id,p_ip_hash);
   INSERT INTO eshop.customer_order_change_capabilities(token_hash,parent_hash,organization_id,form_id,order_id,operation,proposal_hash,
    policy_revision,feature_epoch,expires_at)
   VALUES(p_delivery->>'tokenHash',parent.token_hash,oc.organization,o.form,o.id,p_operation,
    encode(extensions.digest(p_payload::text,'sha256'),'hex'),(preview->>'policyRevision')::bigint,oc.customer_self_service_epoch,clock_timestamp()+interval '10 minutes') RETURNING * INTO cap;
   INSERT INTO eshop.customer_order_change_sources VALUES(cap.id,p_delivery->'source',p_delivery->>'contentHash');
   PERFORM public.enqueue_prepared_email('custom',jsonb_build_object('organization',oc.organization,'occasion',oc.id,'unit',oc.unit,'tracking_policy','none'),
    o.data->>'email',p_delivery->'email','customer-change:'||cap.id,p_delivery->>'contentHash','CUSTOMER_ORDER_CHANGE',cap.expires_at);
   RETURN jsonb_build_object('code',202);
  END IF;
  RETURN jsonb_build_object('code',200,'orderId',o.id,'recipient',o.data->>'email','organization',oc.organization,'occasion',oc.id,'unit',oc.unit,
   'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=oc.organization),
   'locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=oc.organization),'cs'),'preview',preview);
 END IF;
 -- A customer scope is always recovered from the stored credential, never orderId.
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_order IS NOT NULL AND p_order<>cap.order_id THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='resolve' THEN
  RETURN jsonb_build_object('code',200,'orderId',cap.order_id,'operation',cap.operation,
    'source',(SELECT sealed FROM eshop.customer_order_change_sources WHERE capability_id=cap.id));
 END IF;
 PERFORM public.lock_customer_order_change_internal(cap.order_id);
 cap:=public.authorize_customer_change_internal(p_token,p_command);
 IF p_operation IS DISTINCT FROM cap.operation OR encode(extensions.digest(p_payload::text,'sha256'),'hex') IS DISTINCT FROM cap.proposal_hash THEN
  RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 IF p_action='preview' THEN
  preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
  UPDATE eshop.customer_order_change_capabilities SET preview_hash=preview->>'fingerprint',preview_expires_at=(preview->>'expiresAt')::timestamptz WHERE id=cap.id;
  RETURN preview;
 END IF;
 IF p_command IS NULL THEN RAISE invalid_parameter_value; END IF;
 receipt:=public.begin_anonymous_client_mutation_v1(p_command,'orders.customer.'||cap.operation,
  (SELECT occasion FROM eshop.orders WHERE id=cap.order_id),cap.id,encode(extensions.digest(jsonb_build_object('capability',cap.id,'operation',cap.operation,'payload',p_payload,'fingerprint',p_fingerprint)::text,'sha256'),'hex'));
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 preview:=public.preview_customer_order_change_internal(cap.order_id,cap.operation,p_payload);
 IF p_fingerprint IS NULL OR cap.preview_expires_at IS NULL OR cap.preview_expires_at<=clock_timestamp() OR cap.preview_hash IS DISTINCT FROM p_fingerprint OR preview->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 PERFORM public.admit_order_mutation_scope_internal((SELECT occasion FROM eshop.orders WHERE id=cap.order_id),(SELECT count(*) FROM public.get_order_tickets_internal(cap.order_id)),'customer-order:'||cap.order_id);
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=(SELECT occasion FROM eshop.orders WHERE id=cap.order_id);
 result:=public.apply_customer_order_change_internal(cap.order_id,cap.operation,p_payload,preview,p_command);
 UPDATE eshop.customer_order_change_capabilities SET consumed_by=p_command,consumed_form_id=(SELECT form FROM eshop.orders WHERE id=cap.order_id) WHERE id=cap.id;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,(SELECT occasion FROM eshop.orders WHERE id=cap.order_id),
  'orders.customer.'||cap.operation,jsonb_build_array(jsonb_build_object('entityType','order','entityId',cap.order_id,'operation','update',
  'changedFields',jsonb_build_array(cap.operation))),users,result,'unknown');
END $$;
REVOKE ALL ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.customer_order_change_gateway(text,text,bigint,text,jsonb,uuid,text,jsonb,text) TO service_role;

-- SOURCE: customer_order_changes/staff.sql
CREATE OR REPLACE FUNCTION public.command_customer_order_request(p_request uuid,p_action text,p_command uuid,p_expected_at timestamptz,p_response text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r eshop.customer_order_change_requests; o eshop.orders; oc public.occasions; actor uuid:=auth.uid();
 hash text; receipt jsonb; preview jsonb; payload jsonb; result jsonb; users uuid[];
BEGIN
 SELECT * INTO r FROM eshop.customer_order_change_requests WHERE id=p_request;
 SELECT * INTO o FROM eshop.orders WHERE id=r.order_id;
 IF actor IS NULL OR o.id IS NULL OR public.can_write_orders(o.occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='customer request unavailable'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('approve','reject','resolve') OR length(p_response)>2000 THEN RAISE invalid_parameter_value; END IF;
 PERFORM public.lock_customer_order_change_internal(o.id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=o.id;
 SELECT * INTO STRICT r FROM eshop.customer_order_change_requests WHERE id=p_request FOR UPDATE;
 IF public.can_write_orders(o.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 -- Replaying an accepted financial effect also needs today's financial role.
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE id=p_command AND order_id=o.id)
  AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('request',p_request,'action',p_action,'expectedAt',p_expected_at,'response',p_response)::text,'sha256'),'hex');
 receipt:=public.begin_client_mutation_v1(p_command,'orders.customer.request.decide',o.occasion,actor,hash);
 IF receipt->>'disposition'='replay' THEN RETURN receipt->'response'; END IF;
 IF r.updated_at IS DISTINCT FROM p_expected_at OR r.status NOT IN ('open','approved') THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 SELECT coalesce(array_agg("user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 IF p_action='approve' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  payload:=jsonb_build_object('reason',coalesce(r.reason,''));
  IF r.ticket_ids IS NOT NULL THEN payload:=payload||jsonb_build_object('ticketIds',to_jsonb(r.ticket_ids)); END IF;
  preview:=public.preview_customer_order_change_internal(o.id,r.operation,payload,true);
  IF preview->>'effect' ='request_cancel' THEN
   RAISE EXCEPTION 'CUSTOMER_REQUEST_REQUIRES_MANUAL_ACTION' USING ERRCODE='40001'; END IF;
  IF preview->>'effect'='cancel_refund' AND public.can_prepare_order_provider_refund(o.id) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='financial permission required'; END IF;
  result:=public.apply_customer_order_change_internal(o.id,r.operation,payload,preview,p_command,r.id);
  UPDATE eshop.customer_order_change_requests SET status='approved',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSIF p_action='reject' THEN
  IF r.status<>'open' THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='rejected',response=nullif(btrim(p_response),''),
   decided_by=actor,decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 ELSE
  IF nullif(btrim(p_response),'') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='resolution response required'; END IF;
  -- A manual refund obligation cannot be marked paid by a staff click.
  IF r.operation='cancel' AND r.status='approved' AND (coalesce((public.payment_method_context_internal(o.id)->>'net')::numeric,0)>CASE WHEN r.ticket_ids IS NULL OR o.state='storno' THEN 0 ELSE o.price END OR public.payment_method_context_internal(o.id)->'invalidIdentity' IS DISTINCT FROM 'false'::jsonb OR coalesce((public.payment_method_context_internal(o.id)->>'pending')::numeric,0)>0) THEN
   RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRED' USING ERRCODE='40001'; END IF;
  UPDATE eshop.customer_order_change_requests SET status='resolved',response=btrim(p_response),decided_by=actor,
   decision_command=p_command,updated_at=clock_timestamp() WHERE id=r.id;
 END IF;
 PERFORM public.publish_customer_order_request_internal(r.id);
 -- Storno owns its confirmation; support decisions use the same existing queue.
 IF (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
  PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',o.id),oc.organization,oc.id,oc.unit,now(),'customer-request:'||p_command);
 END IF;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command,o.occasion,'orders.customer.request.decide',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('customerRequests'))),
  users,jsonb_build_object('code',200,'requestId',r.id));
END $$;
REVOKE ALL ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.command_customer_order_request(uuid,text,uuid,timestamptz,text) TO authenticated;

-- SOURCE: eshop_forms/admin_form_commands.sql
-- Delegation adapter only: existing UI commands retain the single transaction,
-- receipt, validation, allocation, notification and sync ownership.
CREATE OR REPLACE FUNCTION public.manage_form(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; link text; form_id bigint; source_id bigint; allowed text[]; state jsonb;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('create','save','duplicate','delete','public_link') OR p_payload IS NULL
  OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form command'; END IF;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END);
 SELECT o.link INTO link FROM public.occasions o WHERE o.id=p_occasion;
 IF p_action IN ('save','delete','public_link') THEN
  form_id:=(p_payload->>'id')::bigint;
  IF form_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=p_occasion)
   AND NOT (p_action='delete' AND EXISTS(SELECT 1 FROM public.client_mutation_receipts
    WHERE command_id=p_command_id AND actor_id=auth.uid() AND occasion=p_occasion AND command_name='inventory.form.delete')) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  IF NOT p_payload ? 'expected_aggregate_version' OR jsonb_typeof(p_payload->'expected_aggregate_version')<>'number'
    OR (p_payload->>'expected_aggregate_version')::bigint<0 THEN
   RAISE invalid_parameter_value USING MESSAGE='original form version required'; END IF;
 END IF;
 allowed:=CASE p_action
  WHEN 'public_link' THEN ARRAY['id','expected_aggregate_version','link']
  WHEN 'create' THEN ARRAY['title']
  WHEN 'save' THEN ARRAY['payment_selection_intent','id','expected_aggregate_version','expected_product_versions','expected_product_type_versions',
   'title','header','header_off','is_open','blueprint','bank_account','deadline_duration_seconds',
   'participant_capacity','waitlist_enabled','show_remaining_capacity','waitlist_offer_duration_seconds',
   'form_fields','deleted_field_ids','deleted_product_ids','settings','customer_self_service']
  WHEN 'duplicate' THEN ARRAY['source_form_id','source_occasion_id','source_unit_id','locale']
  WHEN 'delete' THEN ARRAY['id','expected_aggregate_version']
 END;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE NOT k=ANY(allowed)) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported form fields'; END IF;
 CASE p_action
 WHEN 'public_link' THEN
  IF jsonb_typeof(p_payload->'link') IS DISTINCT FROM 'string' THEN RAISE invalid_parameter_value USING MESSAGE='public slug required'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion,'expected_product_versions','{}'::jsonb,'expected_product_type_versions','{}'::jsonb),p_command_id);
 WHEN 'create' THEN
  IF NOT p_payload ? 'title' OR jsonb_typeof(p_payload->'title')<>'string' OR length(p_payload->>'title')>500 THEN
   RAISE invalid_parameter_value USING MESSAGE='form title required'; END IF;
  result:=public.create_form_client_sync_v1(link,'',p_payload->>'title',p_command_id);
 WHEN 'save' THEN
  IF jsonb_typeof(p_payload->'expected_product_versions') IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_payload->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_payload->'deleted_product_ids','[]')) id
    WHERE NOT (p_payload->'expected_product_versions') ? id) THEN
   RAISE invalid_parameter_value USING MESSAGE='deleted product baseline required'; END IF;
  -- The field transport can edit common definitions and reference a catalog
  -- type; inline product mutation remains in the existing aggregate UI owner.
  IF p_payload ? 'form_fields' AND (jsonb_typeof(p_payload->'form_fields')<>'array' OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'form_fields') f WHERE
      jsonb_typeof(f)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f) k WHERE k NOT IN
       ('id','title','description','type','is_required','is_hidden','is_ticket_field','order','data','product_type_id','product_type')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form fields'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'data' AND f->'data'<>'null'::jsonb AND
     (jsonb_typeof(f->'data')<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f->'data') k
       WHERE k NOT IN ('options','max_tickets','selection_type','default_value','label','is_group_feature','min_year','max_year','is_hard','message','show_expiry_date','expiry_date_label','show_surcharge_description')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported field settings'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'product_type' AND f ? 'product_type_id') THEN RAISE invalid_parameter_value USING MESSAGE='choose product reference or aggregate'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion),p_command_id);
 WHEN 'duplicate' THEN
  source_id:=(p_payload->>'source_occasion_id')::bigint;
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source');
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=(p_payload->>'source_form_id')::bigint AND occasion=source_id) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign source form'; END IF;
  IF p_payload->>'locale' IS NULL OR p_payload->>'locale' NOT IN ('cs','en','sk','de','pl','uk') THEN
   RAISE invalid_parameter_value USING MESSAGE='copy locale required'; END IF;
  result:=public.duplicate_form_to_occasion_client_sync_v1((p_payload->>'source_form_id')::bigint,link,p_command_id,p_payload->>'locale');
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source',true);
 WHEN 'delete' THEN
  result:=public.delete_form_client_sync_v1(form_id,p_command_id,(p_payload->>'expected_aggregate_version')::bigint);
 END CASE;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END,true);
 IF (result->>'code')::int=200 THEN
  state:=result->'data'->'authoring';
  IF octet_length(state::text)>1048576 OR jsonb_array_length(state->'fields')>500 THEN
   RAISE program_limit_exceeded USING MESSAGE='form snapshot too large'; END IF;
  form_id:=coalesce((state->'form'->>'id')::bigint,form_id);
  RETURN result||jsonb_build_object('data',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'authoring',state),
   'sync',jsonb_build_object('replacements','[]'::jsonb))
   ||CASE WHEN p_action='public_link' THEN jsonb_build_object('publicLink',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'slug',result#>>'{data,link}')) ELSE '{}'::jsonb END;
 END IF;
 RETURN result||jsonb_build_object('data',jsonb_build_object('reason','FORM_COMMAND_REJECTED'),
   'sync',jsonb_build_object('replacements','[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;

-- SOURCE: eshop_forms/update_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(p_form jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb; v_check record; v_current bigint;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  -- Financial policy entitlement is current even for an existing command receipt.
  IF p_form ? 'customer_self_service' THEN
    IF NOT p_form ? 'expected_aggregate_version' THEN
      RAISE invalid_parameter_value USING MESSAGE='customer policy requires original form revision'; END IF;
    IF public.can_manage_customer_order_policy(v_form,coalesce(
      p_form#>'{customer_self_service,cancel,enabled}'='true'::jsonb AND
      p_form#>>'{customer_self_service,cancel,refund_mode}'='automatic',false)) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='customer policy editor required'; END IF;
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion FOR UPDATE;
  PERFORM 1 FROM eshop.product_types WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  IF v_form IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_form::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  IF (p_form#>'{settings,payments}' ? 'providerConnections' OR p_form#>'{data,payments}' ? 'providerConnections')
    AND NOT p_form ? 'expected_aggregate_version' THEN
    RAISE invalid_parameter_value USING MESSAGE='modern payment snapshot requires original form revision'; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_form ? 'expected_aggregate_version' THEN (p_form->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  -- These maps were frozen when the editor loaded. No read-before-write rebasing.
  -- Missing maps are the bounded released-client facade, not MCP-ready authoring.
  IF p_form ? 'expected_product_versions' OR p_form ? 'expected_product_type_versions' THEN
    IF jsonb_typeof(p_form->'expected_product_versions') IS DISTINCT FROM 'object'
      OR jsonb_typeof(p_form->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
      RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
    FOR v_check IN
      SELECT DISTINCT 'product'::text kind, (p->>'id')::bigint id FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(f#>'{product_type,products}','null'),'[]')) p WHERE p->>'id' IS NOT NULL
      UNION SELECT 'product',value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_product_ids','[]'))
      UNION SELECT DISTINCT 'product',p.id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
        WHERE ff.form=v_form AND ff.id IN (SELECT value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_field_ids','[]')))
      UNION SELECT DISTINCT 'product_type',(f#>>'{product_type,id}')::bigint FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        WHERE f#>>'{product_type,id}' IS NOT NULL
      ORDER BY 1,2
    LOOP
      IF NOT (CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions'
        ELSE p_form->'expected_product_type_versions' END) ? v_check.id::text THEN
        RAISE invalid_parameter_value USING MESSAGE='missing original product baseline'; END IF;
      IF (v_check.kind='product' AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=v_check.id AND occasion=v_occasion))
        OR (v_check.kind='product_type' AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=v_check.id AND occasion=v_occasion)) THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('entity_type',v_check.kind,'entity_id',v_check.id,'deleted',true)); END IF;
      SELECT coalesce(v.version,0) INTO v_current FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
        ON v.aggregate_type=v_check.kind AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_check.id::text;
      IF ((CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions' ELSE p_form->'expected_product_type_versions' END)->>v_check.id::text)::bigint IS DISTINCT FROM v_current THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
          jsonb_build_object('aggregate_version',v_version,'entity_type',v_check.kind,'entity_id',v_check.id,'entity_version',v_current));
      END IF;
    END LOOP;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  BEGIN
    v_result:=public.update_form_internal_v1(p_form-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
  IF p_form ? 'customer_self_service' THEN
    PERFORM public.save_customer_order_policy_internal(v_form,p_form->'customer_self_service');
  END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version,
    'product_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product'),
    'product_type_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product_type'),
    'authoring',public.get_form_authoring_snapshot_internal(v_form));
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.update_form_client_sync_v1(input_data,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;

-- SOURCE: eshop_forms/get_form_for_edit.sql
-- Canonical editor projection shared by the checked UI and MCP boundaries.
CREATE OR REPLACE FUNCTION public.get_form_editor_bundle_internal(p_form_id bigint,p_related_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    v_unit_id BIGINT;
    formData JSONB;
    formFieldsData JSONB;
    productTypesData JSONB;
    productsData JSONB;
    availableBankAccountsData JSONB;
    canDelete BOOLEAN;
BEGIN
    SELECT
        f.id,
        f.occasion,
        o.unit
    INTO
        v_form_id,
        v_occasion_id,
        v_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    -- Private projection; the checked public reader/command owns authorization.

    -- Use the same reference guard as deletion, including retained history.
    canDelete := (public.get_form_usage_internal(v_form_id)->>'blocking_orders')::bigint=0;

    SELECT jsonb_build_object(
        'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=f.occasion AND aggregate_id=f.id::text),0),
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'organizationIdentity',(SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', public.normalize_form_metadata_internal(f.data),
        'measurement_status', public.form_measurement_status_internal(f.id),
        'customer_self_service',public.customer_order_policy_internal(f.id)||jsonb_build_object('canEnableAutomaticRefund',public.can_manage_customer_order_policy(f.id,true)),
        'type', f.type,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'occasion', f.occasion,
        'blueprint', f.blueprint,
        'link', f.link,
        'bank_account', f.bank_account,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'can_delete', canDelete -- Added field
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product_type' AND scope_type='occasion' AND scope_id=pt.occasion AND aggregate_id=pt.id::text),0),
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id
      AND (NOT p_related_only OR pt.id IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

    -- Materialize occasion history once rather than scanning it for every
    -- product and every field. Only current orders and current references determine eligibility.
    WITH occasion_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE occasion = v_occasion_id
    ), snapshots AS MATERIALIZED (
      SELECT data FROM occasion_orders
    ), used_products AS MATERIALIZED (
      SELECT opt.product::text AS product FROM eshop.order_product_ticket opt
      JOIN eshop.products p ON p.id = opt.product WHERE p.occasion = v_occasion_id
      UNION
      SELECT value #>> '{}' FROM snapshots s
      CROSS JOIN LATERAL jsonb_path_query(s.data, '$.tickets[*].products[*].id') ids(value)
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'occasion', p.occasion,
            'title', p.title,
            'description', p.description,
            'price', p.price,
            'currency_code', p.currency_code,
            'is_hidden', p.is_hidden,
            'order', p."order",
            'product_type', p.product_type,
            'ordered_count', (
                SELECT count(*)
                FROM eshop.order_product_ticket opt
                JOIN eshop.orders o ON opt."order" = o.id
                WHERE opt.product = p.id AND o.state <> 'storno'
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    CROSS JOIN LATERAL (SELECT CASE
      WHEN public.primary_product_delete_blocked_internal(p.id) THEN 'primary_product'
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.occasion=v_occasion_id AND p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id)
      AND (NOT p_related_only OR p.product_type IN (SELECT product_type FROM public.form_fields WHERE form=v_form_id));

    WITH form_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE form = v_form_id
    ), form_snapshots AS MATERIALIZED (
      SELECT data FROM form_orders
    ), form_tickets AS MATERIALIZED (
      SELECT t.note FROM eshop.order_product_ticket opt
      JOIN form_orders o ON o.id = opt."order"
      JOIN eshop.tickets t ON t.id = opt.ticket
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'form', ff.form,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'is_hidden', ff.is_hidden,
            'is_ticket_field', ff.is_ticket_field,
            'order', ff."order",
            'product_type', ff.product_type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    CROSS JOIN LATERAL (SELECT CASE
      WHEN EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ff.product_type AND pt.type='spot')
        OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM public.form_fields child
          JOIN eshop.product_types pt ON pt.id=child.product_type
          WHERE child.form=ff.form AND child.is_ticket_field AND pt.type='spot')) THEN 'primary_product'
      WHEN EXISTS (
      SELECT 1 FROM form_snapshots s WHERE
        EXISTS (SELECT 1 FROM jsonb_array_elements(
          CASE WHEN jsonb_typeof(s.data->'fields') = 'array' THEN s.data->'fields' ELSE '[]'::jsonb END) answer
          WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
        OR (ff.type = 'ticket' AND jsonb_path_exists(s.data, '$.tickets[*]'))
        OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(s.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
    ) OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM form_tickets))
      OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (SELECT 1 FROM form_tickets WHERE NULLIF(note, '') IS NOT NULL))
      OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
        WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
      OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form))
    THEN 'responses' ELSE (
      SELECT p->>'delete_blocked_reason' FROM public.form_fields member
      JOIN jsonb_array_elements(productsData) p ON (p->>'product_type')::bigint = member.product_type
      WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
        AND p->>'delete_blocked_reason' IS NOT NULL
      ORDER BY (p->>'id')::bigint LIMIT 1
    ) END AS reason) usage
    WHERE ff.form = v_form_id;

    availableBankAccountsData:=CASE WHEN p_related_only THEN '[]'::jsonb
        ELSE public.get_form_bank_accounts_internal(v_unit_id) END;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'form', formData,
            'form_fields', formFieldsData,
            'product_types', productTypesData,
            'products', productsData,
            'payment_method_policy',public.resolve_payment_method_policy_internal((SELECT organization FROM public.units WHERE id=v_unit_id),v_unit_id),
            'available_bank_accounts', availableBankAccountsData
        )
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_form_editor_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Released link-based entry remains a checked boundary on the same projection.
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE form_id bigint;
BEGIN
 form_id:=public.resolve_form_link_internal(form_link);
 IF form_id IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form not found for the provided link.'); END IF;
 IF public.can_read_form_catalog((SELECT occasion FROM public.forms WHERE id=form_id)) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='form catalog reader required'; END IF;
 RETURN public.get_form_editor_bundle_internal(form_id);
END $$;
REVOKE ALL ON FUNCTION public.get_form_for_edit(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_for_edit(text) TO anon,authenticated,service_role;

-- SOURCE: eshop/get_order_details_for_email.sql
CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    result_data jsonb;
    v_changes jsonb;
    form_fields_data jsonb;
    form_data jsonb;
    form_key uuid;
    latest_history_id bigint;
    v_reply_to_email TEXT;
BEGIN
    -- Retrieve the order, occasion, payment info, and bank account as separate objects
    SELECT jsonb_build_object(
        'order', to_jsonb(o.*) || jsonb_build_object('data', o.data || jsonb_build_object(
          'tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))),
        'occasion', to_jsonb(occ)||jsonb_build_object('locale',coalesce((SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=occ.organization),'cs')),
        -- Same statement snapshot as the ticket feature used by delivery.
        'wallet', jsonb_build_object(
          'feature',(SELECT f FROM jsonb_array_elements(occ.features) f WHERE f->>'code'='ticket'),
          'fingerprint',public.ticket_wallet_fingerprint(occ.id)),
        'payment_info', to_jsonb(pi.*)||jsonb_build_object('collectionAction',public.payment_collection_action_internal(o.id),'providerPayment',CASE WHEN public.payment_method_is_online_internal(pi.payment_method) THEN public.provider_order_payment_projection_internal(o.id) END),
        'bank_account', CASE
            WHEN upper(o.currency_code) = 'EUR'
              AND ba.id IS NOT NULL
              AND nullif(trim(ba.creditor_name), '') IS NULL
            THEN jsonb_set(
              to_jsonb(ba.*),
              '{creditor_name}',
              to_jsonb(left(trim(regexp_replace(org.title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70))
            )
            ELSE to_jsonb(ba.*)
        END
    )
    INTO result_data
    FROM eshop.orders AS o
    LEFT JOIN public.occasions AS occ ON o.occasion = occ.id
    LEFT JOIN public.organizations AS org ON occ.organization = org.id
    LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
    LEFT JOIN eshop.bank_accounts AS ba ON pi.bank_account = ba.id
    WHERE o.id = p_order_id;

    -- Check if the order was found
    IF result_data IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found.');
    END IF;

    -- Call the function you provided to get the email
    SELECT get_reply_to_email_for_order(p_order_id) INTO v_reply_to_email;

    -- Add the email to the result data. jsonb_build_object handles NULLs gracefully.
    result_data := result_data || jsonb_build_object('reply_to', v_reply_to_email);


    v_changes := public.get_order_change_summary_v1(p_order_id);
    latest_history_id := (v_changes->>'latestHistoryId')::bigint;
    result_data := result_data || jsonb_build_object(
      'latest_history_id', latest_history_id,
      'reference_history', v_changes#>'{referenceOrder,data}',
      'order_changes', v_changes);

    -- Extract the form's unique key from the order's data
    form_key := (result_data->'order'->'data'->>'form')::uuid;

    -- If a form key exists, fetch all associated form fields
    IF form_key IS NOT NULL THEN
        -- 2. Modified query to fetch both form_fields and form_data at the same time
        SELECT
            jsonb_object_agg(ff.id, to_jsonb(ff.*)), -- All fields
            public.effective_form_metadata_internal(f.data, u.data) -- Communication metadata without analytics policy
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        JOIN public.occasions form_occasion ON form_occasion.id = f.occasion
        JOIN public.units u ON u.id = form_occasion.unit
        WHERE
            f.key = form_key
        GROUP BY
            f.id, u.data; -- Group by the form used for effective data

        -- If form fields were found, add them to the result data
        IF form_fields_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_fields', form_fields_data);
        END IF;

        -- 3. Added this block to merge the form_data
        IF form_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_data', form_data);
        END IF;
    END IF;

    -- Return a success response with the collected data
    RETURN jsonb_build_object('code', 200, 'data', result_data);

END;
$$;
-- The worker is the external consumer. Already-authorized definer commands
-- (contact repair) share this read owner without granting it to clients.
REVOKE ALL ON FUNCTION public.get_order_details_for_email(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_details_for_email(bigint) TO service_role;

-- SOURCE: ticket_wallet/projection.sql
-- The current paid-delivery boundary, never scanner configuration overrides.
CREATE OR REPLACE FUNCTION public.ticket_wallet_state_internal(p_ticket bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT oc.* INTO o FROM public.occasions oc JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=c.order_id;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 state:='INACTIVE';
 IF t.id IS NOT NULL AND t.occasion=c.occasion AND o.organization=c.organization
 AND coalesce((f->>'is_enabled')::boolean,false) AND c.revoked_at IS NULL
 AND o.start_time IS NOT NULL AND o.end_time IS NOT NULL AND nullif(btrim(o.title),'') IS NOT NULL
 AND t.ticket_symbol IS NOT NULL AND t.state IN ('paid','sent','used')
 AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND ord.id=c.order_id AND ord.occasion=t.occasion AND ord.state IN ('paid','sent'))
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders ord ON ord.id=x."order"
  WHERE x.ticket=t.id AND (ord.occasion IS DISTINCT FROM t.occasion OR ord.state NOT IN ('paid','sent')))
 AND public.provider_ticket_admission_allowed_internal(t.id) THEN
  state:=CASE WHEN o.end_time<=now() OR c.expires_at<=now() THEN 'EXPIRED' WHEN t.state='used' THEN 'COMPLETED' ELSE 'ACTIVE' END;
 END IF;
 RETURN state;
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_state_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_state_internal(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.ticket_wallet_projection_internal(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE t eshop.tickets; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; state text; details jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO t FROM eshop.tickets WHERE id=p_ticket;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT oc.* INTO o FROM public.occasions oc JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=c.order_id;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 state:=public.ticket_wallet_state_internal(p_ticket);
 IF t.id IS NOT NULL THEN
  SELECT x INTO details FROM jsonb_array_elements(public.get_tickets_with_details(c.order_id)) x WHERE (x->>'id')::bigint=t.id;
 END IF;
 RETURN jsonb_build_object('state',state,
 'branding',(SELECT jsonb_build_object('APP_NAME',data->'APP_NAME','DEFAULT_URL',data->'DEFAULT_URL','WALLET_LOGO_URL',data->'WALLET_LOGO_URL') FROM public.organizations WHERE id=o.organization),
 'ticket',jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,
 'order_product_ticket',(SELECT coalesce(jsonb_agg(x||jsonb_build_object('product',jsonb_build_object('title',p.title))),'[]') FROM jsonb_array_elements(details->'order_product_ticket') x LEFT JOIN eshop.products p ON p.id=(x->>'product')::bigint)),
 'occasion',jsonb_build_object('id',o.id,'organization',o.organization,'title',o.title,'start_time',o.start_time,'end_time',o.end_time,
 'ticketFeature',jsonb_build_object('ticket_type',f->'ticket_type','background',f->'background','lightColor',f->'lightColor','layout',f->'layout','wallet_appearance',f->'wallet_appearance'),
 'data',jsonb_build_object('place_name',o.data->'place_name','timezone',o.data->'timezone','logo',o.data->'logo')));
END $$;
REVOKE ALL ON FUNCTION public.ticket_wallet_projection_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_wallet_projection_internal(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.refresh_ticket_wallet_term_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o public.occasions; oid bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT order_id INTO oid FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 SELECT oc.* INTO o FROM public.occasions oc JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=oid;
 IF o.end_time IS NULL THEN RETURN; END IF;
 UPDATE eshop.ticket_wallet_capabilities SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
 WHERE order_id=oid AND occasion=o.id AND organization=o.organization AND revoked_at IS NULL AND reissue_after IS NULL AND event_end_at IS DISTINCT FROM o.end_time;
 UPDATE eshop.ticket_wallet_collections SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
 WHERE order_id=oid AND occasion=o.id AND organization=o.organization AND revoked_at IS NULL AND event_end_at IS DISTINCT FROM o.end_time;
END $$;
REVOKE ALL ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_ticket_wallet_term_internal(bigint) TO service_role;

-- SOURCE: ticket_wallet/capabilities.sql
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet(p_message uuid,p_ticket bigint,p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash IS NOT NULL AND (EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_collections WHERE token_hash=p_hash)) THEN RETURN NULL; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m)
 OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket AND "order"=m.order_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Wallet unavailable'; END IF;
 SELECT oc.* INTO o FROM public.occasions oc JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=m.order_id AND oc.id=m.occasion AND oc.organization=m.organization;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND (publishing_ready OR apple_publishing_ready);
 IF NOT coalesce((f->>'is_enabled')::boolean,false) OR NOT public.ticket_wallet_enabled(f) OR i.organization IS NULL
 OR nullif(btrim(o.title),'') IS NULL OR (o.data->>'timezone' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=o.data->>'timezone'))
 OR o.end_time IS NULL OR o.start_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 -- Serialize issuance/reissue on the existing ticket; revoked rows never disappear.
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket AND occasion=m.occasion AND state IN ('paid','sent','used') AND ticket_symbol IS NOT NULL AND public.provider_ticket_admission_allowed_internal(id) FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(p_ticket);
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  UPDATE eshop.ticket_wallet_capabilities SET token_hash=p_hash,sealed=p_sealed,recipient=m.recipient,message_id=m.message_id,
   revoked_at=NULL,reissue_after=NULL,event_end_at=o.end_time,expires_at=o.end_time+interval '7 days' WHERE ticket_id=p_ticket RETURNING * INTO c;
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 IF c.ticket_id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  INSERT INTO eshop.ticket_wallet_capabilities(ticket_id,organization,occasion,order_id,token_hash,sealed,recipient,message_id,expires_at,event_end_at)
  VALUES(p_ticket,m.organization,m.occasion,m.order_id,p_hash,p_sealed,m.recipient,m.message_id,o.end_time+interval '7 days',o.end_time) RETURNING * INTO c;
 END IF;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NULL THEN c.ticket_id:=NULL; END IF;
 IF c.ticket_id IS NOT NULL AND (c.revoked_at IS NOT NULL OR c.expires_at<=now() OR c.recipient IS DISTINCT FROM m.recipient
 OR c.organization<>m.organization OR c.occasion<>m.occasion OR c.order_id<>m.order_id) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'ticketId',p_ticket,'issuer',i.issuer,
 'environment',i.environment,'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,
 'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
 'collectionEnabled',i.collection_enabled,'source',CASE WHEN c.ticket_id IS NOT NULL THEN jsonb_build_object('sealed',c.sealed,'tokenHash',c.token_hash,'generation',c.generation) END);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_ticket_wallet(p_hash text,p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n integer; k text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_source !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 DELETE FROM eshop.ticket_wallet_limits WHERE window_at<now()-interval '10 minutes';
 FOREACH k IN ARRAY ARRAY['token:'||p_hash,'source:'||p_source] LOOP
  INSERT INTO eshop.ticket_wallet_limits(key,window_at,attempts) VALUES(k,now(),1)
  ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN 1 ELSE ticket_wallet_limits.attempts+1 END,
  window_at=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN now() ELSE ticket_wallet_limits.window_at END RETURNING attempts INTO n;
  IF n>20 THEN RETURN NULL; END IF;
 END LOOP;
 RETURN public.ticket_wallet_scope_internal(p_hash);
END $$;

-- Explicit support operation. A new generation always requires a fresh valid email intent.
CREATE OR REPLACE FUNCTION public.manage_ticket_wallet(p_ticket bigint,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; scope bigint;
BEGIN
 SELECT occasion INTO scope FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF auth.uid() IS NULL OR public.can_write_orders(scope) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_action NOT IN ('revoke','reissue') THEN RAISE invalid_parameter_value; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket FOR UPDATE;
 UPDATE eshop.ticket_wallet_capabilities SET revoked_at=coalesce(revoked_at,now()) WHERE ticket_id=p_ticket;
 -- Reissue retains the tombstone and audit while removing access to the previous source.
 IF p_action='reissue' THEN
  UPDATE eshop.ticket_wallet_capabilities SET generation=generation+1,reissue_after=clock_timestamp(),sealed='{}',token_hash=encode(extensions.gen_random_bytes(32),'hex'),
   recipient='',message_id='00000000-0000-0000-0000-000000000000',expires_at=now() WHERE ticket_id=p_ticket;
 END IF;
 INSERT INTO eshop.ticket_wallet_audit(ticket_id,generation,token_hash,actor,action) VALUES(p_ticket,c.generation,c.token_hash,auth.uid(),p_action);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) TO service_role;
REVOKE ALL ON FUNCTION public.manage_ticket_wallet(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_ticket_wallet(bigint,text) TO authenticated;

-- SOURCE: ticket_wallet/collections.sql
-- A collection grants only the delivered set, never future tickets in its order.
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet_collection(p_message uuid,p_tickets bigint[],p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; i eshop.ticket_wallet_integrations; o public.occasions;
 c eshop.ticket_wallet_capabilities; b eshop.ticket_wallet_collections; ids bigint[]; members jsonb:='[]'; v_fingerprint text;
BEGIN
 PERFORM public.require_service_role();
 IF p_tickets IS NULL OR cardinality(p_tickets) NOT BETWEEN 2 AND 1000 THEN RETURN NULL; END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_tickets) x WHERE x>0;
 IF cardinality(ids) IS DISTINCT FROM cardinality(p_tickets) THEN RAISE invalid_parameter_value; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND collection_enabled AND NOT paused AND (publishing_ready OR apple_publishing_ready);
 SELECT oc.* INTO o FROM public.occasions oc JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=m.order_id AND oc.id=m.occasion AND oc.organization=m.organization;
 IF i.organization IS NULL OR o.end_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 FOR c IN SELECT * FROM eshop.ticket_wallet_capabilities WHERE ticket_id=ANY(ids) ORDER BY ticket_id FOR UPDATE LOOP
  PERFORM public.refresh_ticket_wallet_term_internal(c.ticket_id);
  IF c.organization IS DISTINCT FROM m.organization OR c.occasion IS DISTINCT FROM m.occasion OR c.order_id IS DISTINCT FROM m.order_id
   OR c.recipient IS DISTINCT FROM m.recipient OR c.revoked_at IS NOT NULL OR c.reissue_after IS NOT NULL
   OR public.ticket_wallet_state_internal(c.ticket_id) NOT IN ('ACTIVE','COMPLETED') THEN RAISE insufficient_privilege; END IF;
  members:=members||jsonb_build_array(jsonb_build_object('ticketId',c.ticket_id,'tokenHash',c.token_hash,'generation',c.generation));
 END LOOP;
 IF jsonb_array_length(members)<>cardinality(ids) THEN RAISE insufficient_privilege; END IF;
 v_fingerprint:=encode(extensions.digest(members::text,'sha256'),'hex');
 SELECT * INTO b FROM eshop.ticket_wallet_collections WHERE organization=m.organization AND occasion=m.occasion AND order_id=m.order_id AND recipient=m.recipient AND ticket_wallet_collections.fingerprint=v_fingerprint;
 IF b.id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  IF p_hash !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash)
   OR EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) THEN RAISE invalid_parameter_value; END IF;
  INSERT INTO eshop.ticket_wallet_collections(organization,occasion,order_id,recipient,message_id,members,fingerprint,token_hash,sealed,event_end_at,expires_at)
  VALUES(m.organization,m.occasion,m.order_id,m.recipient,m.message_id,members,v_fingerprint,p_hash,p_sealed,o.end_time,o.end_time+interval '7 days')
  ON CONFLICT(organization,occasion,order_id,recipient,fingerprint) DO UPDATE SET event_end_at=excluded.event_end_at,expires_at=excluded.expires_at RETURNING * INTO b;
 END IF;
 IF b.revoked_at IS NOT NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'orderId',m.order_id,'ticketIds',to_jsonb(ids),'fingerprint',v_fingerprint,
  'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
  'source',CASE WHEN b.id IS NOT NULL THEN jsonb_build_object('sealed',b.sealed,'tokenHash',b.token_hash) END);
END $$;

-- Shared authorization owner. It does not expose QR data for an entire large order.
CREATE OR REPLACE FUNCTION public.ticket_wallet_scope_internal(p_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; b eshop.ticket_wallet_collections; i eshop.ticket_wallet_integrations;
 member jsonb; tickets jsonb:='[]'; common jsonb; item jsonb; result jsonb; v_state text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal((SELECT ticket_id FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash));
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now() AND reissue_after IS NULL;
 IF c.ticket_id IS NOT NULL THEN
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization AND NOT paused;
 ELSE
  UPDATE eshop.ticket_wallet_collections x SET event_end_at=o.end_time,expires_at=o.end_time+interval '7 days'
   FROM public.occasions o WHERE x.token_hash=p_hash AND x.revoked_at IS NULL AND x.occasion=o.id AND x.organization=o.organization
    AND o.end_time IS NOT NULL AND x.event_end_at IS DISTINCT FROM o.end_time;
  SELECT * INTO b FROM eshop.ticket_wallet_collections WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now();
  IF b.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=b.organization AND collection_enabled AND NOT paused;
 END IF;
 IF i.organization IS NULL THEN RETURN NULL; END IF;
 common:=jsonb_build_object('organization',i.organization,'occasion',coalesce(c.occasion,b.occasion),'issuer',i.issuer,'environment',i.environment,
  'webOrigin',i.web_origin,'providers',jsonb_build_object('google',i.publishing_ready,'apple',i.apple_publishing_ready),
  'applePassTypeIdentifier',i.apple_pass_type_identifier,'appleTeamIdentifier',i.apple_team_identifier);
 IF c.ticket_id IS NOT NULL THEN
  item:=common||jsonb_build_object('ticketId',c.ticket_id,'capabilityHash',c.token_hash,'projection',public.ticket_wallet_projection_internal(c.ticket_id));
  result:=item||jsonb_build_object('kind','ticket','tickets',jsonb_build_array(item),'ticketCount',1,'originalCount',1,'state',item#>>'{projection,state}');
 ELSE
  FOR member IN SELECT value FROM jsonb_array_elements(b.members) LOOP
   PERFORM public.refresh_ticket_wallet_term_internal((member->>'ticketId')::bigint);
   SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=(member->>'ticketId')::bigint AND token_hash=member->>'tokenHash'
    AND generation=(member->>'generation')::integer AND organization=b.organization AND occasion=b.occasion AND order_id=b.order_id
    AND recipient=b.recipient AND revoked_at IS NULL AND reissue_after IS NULL AND expires_at>now();
   IF c.ticket_id IS NULL THEN CONTINUE; END IF;
   v_state:=public.ticket_wallet_state_internal(c.ticket_id);
   IF v_state<>'ACTIVE' THEN CONTINUE; END IF;
   tickets:=tickets||jsonb_build_array(common||jsonb_build_object('ticketId',c.ticket_id,'capabilityHash',c.token_hash,'projection',jsonb_build_object('state',v_state)));
  END LOOP;
  IF jsonb_array_length(tickets)=0 THEN RETURN NULL; END IF;
  result:=common||jsonb_build_object('kind','collection','tickets',tickets,'ticketCount',jsonb_array_length(tickets),'originalCount',jsonb_array_length(b.members),'state','ACTIVE');
 END IF;
 RETURN result||jsonb_build_object('revision',encode(extensions.digest(result::text,'sha256'),'hex'));
END $$;

-- The service may load only the already-authorized portion selected by its provider planner.
CREATE OR REPLACE FUNCTION public.get_ticket_wallet_projections(p_hash text,p_tickets bigint[],p_revision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE scope jsonb; item jsonb; result jsonb:='[]'; ids bigint[];
BEGIN
 PERFORM public.require_service_role();
 IF p_tickets IS NULL OR cardinality(p_tickets) NOT BETWEEN 1 AND 10 THEN RETURN NULL; END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_tickets) x;
 IF cardinality(ids) IS DISTINCT FROM cardinality(p_tickets) THEN RETURN NULL; END IF;
 scope:=public.ticket_wallet_scope_internal(p_hash);
 IF scope IS NULL OR scope->>'revision' IS DISTINCT FROM p_revision THEN RETURN NULL; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(scope->'tickets') WHERE (value->>'ticketId')::bigint=ANY(ids) ORDER BY (value->>'ticketId')::bigint LOOP
  result:=result||jsonb_build_array(item||jsonb_build_object('projection',public.ticket_wallet_projection_internal((item->>'ticketId')::bigint)));
 END LOOP;
 IF jsonb_array_length(result)<>cardinality(ids) THEN RETURN NULL; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet_collection(uuid,bigint[],text,jsonb),public.ticket_wallet_scope_internal(text),public.get_ticket_wallet_projections(text,bigint[],text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet_collection(uuid,bigint[],text,jsonb),public.ticket_wallet_scope_internal(text),public.get_ticket_wallet_projections(text,bigint[],text) TO service_role;

-- SOURCE: customer_order_changes/retire_moves.sql
-- An explicit forward retirement; no history or financial record is erased.
UPDATE eshop.customer_order_change_policies SET policy=policy-'move',revision=revision+1,updated_at=clock_timestamp() WHERE policy ? 'move';
DROP FUNCTION public.remap_customer_move_answers_internal(jsonb,bigint,bigint,jsonb,boolean);
DROP FUNCTION public.customer_move_preview_internal(bigint,bigint);
DROP FUNCTION public.customer_move_targets_internal(bigint);
DROP FUNCTION public.move_customer_order_domain_internal(bigint,bigint);
DROP FUNCTION public.order_term_occasion_internal(bigint);
DROP FUNCTION public.refresh_order_wallet_term_domain_internal(bigint);
DROP FUNCTION public.lock_customer_order_change_internal(bigint,bigint);
ALTER TABLE public.forms DROP CONSTRAINT forms_term_interval;
ALTER TABLE public.forms DROP COLUMN term_start_at, DROP COLUMN term_end_at;
ALTER TABLE eshop.customer_order_change_requests DROP COLUMN target_form_id;
ALTER TABLE eshop.customer_order_change_requests DROP CONSTRAINT customer_order_change_requests_operation_check,
 ADD CONSTRAINT customer_order_change_requests_operation_check CHECK(operation='cancel');
ALTER TABLE eshop.customer_order_change_capabilities DROP CONSTRAINT customer_order_change_capabilities_operation_check,
 ADD CONSTRAINT customer_order_change_capabilities_operation_check CHECK(operation IN ('edit','cancel','withdraw'));
