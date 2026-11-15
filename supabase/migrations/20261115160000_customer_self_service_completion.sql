-- Complete selected-ticket customer cancellation validation; preserve published foundation bytes.

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
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_policy) k WHERE k NOT IN ('edit','cancel','move')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid customer change policy'; END IF;
 FOR op IN SELECT * FROM jsonb_each(p_policy) LOOP
  rule:=op.value;
  IF jsonb_typeof(rule)<>'object' OR jsonb_typeof(rule->'enabled') IS DISTINCT FROM 'boolean'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(rule) k WHERE k NOT IN ('enabled','allowed_until',
     'fields','mode','reason_required','refund_mode','targets')) THEN
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
  ELSE
   IF rule ?| ARRAY['fields','mode','reason_required','refund_mode'] OR jsonb_typeof(rule->'targets') IS DISTINCT FROM 'array'
    OR jsonb_array_length(rule->'targets')>25 THEN RAISE invalid_parameter_value USING MESSAGE='invalid customer move targets'; END IF;
   FOR field IN SELECT value FROM jsonb_array_elements(rule->'targets') LOOP
    IF jsonb_typeof(field)<>'object' OR field-ARRAY['formId','products','fields']<>'{}'::jsonb
     OR jsonb_typeof(field->'formId') IS DISTINCT FROM 'number' OR field->>'formId' !~ '^[1-9][0-9]*$'
     OR jsonb_typeof(field->'products') IS DISTINCT FROM 'object'
     OR (field ? 'fields' AND jsonb_typeof(field->'fields')<>'object') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid customer target mapping'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each(field->'products') x WHERE x.key!~'^[1-9][0-9]*$' OR x.value::text!~'^[1-9][0-9]*$')
     OR EXISTS(SELECT 1 FROM jsonb_each(coalesce(field->'fields','{}')) x WHERE x.key!~'^[1-9][0-9]*$' OR x.value::text!~'^[1-9][0-9]*$') THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid customer target identifiers'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_each_text(coalesce(field->'fields','{}')) m GROUP BY m.value HAVING count(*)>1) THEN
     RAISE invalid_parameter_value USING MESSAGE='customer answer mapping must be one-to-one'; END IF;
   END LOOP;
  END IF;
  result:=result||jsonb_build_object(op.key,rule);
 END LOOP;
 IF (SELECT count(*) FROM jsonb_array_elements(coalesce(result#>'{move,targets}','[]')))<>(SELECT count(DISTINCT v->>'formId') FROM jsonb_array_elements(coalesce(result#>'{move,targets}','[]')) v) THEN
  RAISE invalid_parameter_value USING MESSAGE='duplicate customer target'; END IF;
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
 FOR field IN SELECT value FROM jsonb_array_elements(coalesce(normalized#>'{move,targets}','[]')) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.forms dst JOIN public.occasions target ON target.id=dst.occasion
    JOIN public.occasions source ON source.id=fid WHERE dst.id=(field->>'formId')::bigint AND dst.id<>p_form
    AND target.organization=source.organization AND public.can_read_form_catalog(target.id)) THEN
   RAISE invalid_parameter_value USING MESSAGE='customer target scope invalid'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each_text(field->'products') mapping
    WHERE NOT EXISTS(SELECT 1 FROM eshop.products src JOIN eshop.products dst ON dst.id=mapping.value::bigint
      JOIN public.forms target ON target.id=(field->>'formId')::bigint WHERE src.id=mapping.key::bigint
      AND src.occasion=fid AND dst.occasion=target.occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='customer product mapping scope invalid'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each_text(coalesce(field->'fields','{}')) mapping
    WHERE NOT EXISTS(SELECT 1 FROM public.form_fields src JOIN public.form_fields dst ON dst.id=mapping.value::bigint
      WHERE src.id=mapping.key::bigint AND src.form=p_form AND dst.form=(field->>'formId')::bigint
      AND src.type=dst.type AND src.is_ticket_field IS NOT DISTINCT FROM dst.is_ticket_field
      AND NOT coalesce(src.is_hidden,false) AND NOT coalesce(dst.is_hidden,false))) THEN
    RAISE invalid_parameter_value USING MESSAGE='customer answer mapping scope invalid'; END IF;
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
  WHERE f.id=p_form AND p_operation IN ('cancel','move')),false);
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

-- SOURCE: customer_order_changes/commands.sql
CREATE OR REPLACE FUNCTION public.lock_customer_order_change_internal(p_order bigint,p_target bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; fid bigint;
BEGIN
 SELECT occasion,form INTO oc.id,fid FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=oc.id;
 PERFORM public.payment_policy_fence_internal(oc.organization);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[oc.id]);
 PERFORM 1 FROM public.forms WHERE id IN(fid,p_target) AND occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=p_order FOR UPDATE;
 -- Form saves take this same occasion fence before their product locks.
 PERFORM 1 FROM eshop.products WHERE occasion=oc.id ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=p_order) FOR UPDATE;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT id FROM public.get_order_tickets_internal(p_order)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_customer_order_change_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

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
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF effect='edit' THEN
  IF coalesce(p_payload->'order','{}')<>'{}'::jsonb THEN PERFORM public.update_order_responses_domain_internal(o.id,p_payload->'order'); END IF;
  FOR item IN SELECT * FROM jsonb_each(coalesce(p_payload->'tickets','{}')) LOOP
   SELECT * INTO STRICT t FROM eshop.tickets WHERE id=item.key::bigint FOR UPDATE;
   SELECT coalesce(jsonb_object_agg(a.key,a.value),'{}') INTO merged FROM jsonb_array_elements(coalesce(t.data->'fields','[]')) f CROSS JOIN LATERAL jsonb_each(f) a;
   SELECT coalesce(jsonb_agg(jsonb_build_object(key,value) ORDER BY key),'[]') INTO fields FROM jsonb_each(merged||item.value);
   UPDATE eshop.tickets SET data=jsonb_set(coalesce(t.data,'{}'),'{fields}',fields) WHERE id=t.id;
  END LOOP;
  IF coalesce(p_payload->'tickets','{}')<>'{}'::jsonb THEN
   UPDATE eshop.orders ord SET data=jsonb_set(ord.data,'{tickets}',(SELECT coalesce(jsonb_agg(
    CASE WHEN p_payload->'tickets' ? (snapshot->>'id') THEN jsonb_set(snapshot,'{fields}',(SELECT data->'fields' FROM eshop.tickets WHERE id=(snapshot->>'id')::bigint)) ELSE snapshot END),'[]')
    FROM jsonb_array_elements(coalesce(ord.data->'tickets','[]')) snapshot)),updated_at=clock_timestamp() WHERE ord.id=o.id;
   INSERT INTO eshop.orders_history("order",state,price,data,currency_code) SELECT id,state,price,data,currency_code FROM eshop.orders WHERE id=o.id;
  END IF;
  -- Materialized ticket documents and Wallet share the existing delivery owner.
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);
  PERFORM public.enqueue_order_wallet_internal(o.id);
  IF o.state IN ('paid','sent') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 ELSIF effect IN ('request_cancel','request_move','cancel_manual_refund') OR (p_operation IN ('cancel','move') AND nullif(btrim(p_payload->>'reason'),'') IS NOT NULL) THEN
  IF effect IN ('cancel_manual_refund','cancel_refund') THEN request_status:='approved'; ELSIF effect IN ('cancel','move') THEN request_status:='resolved'; END IF;
  IF p_existing_request IS NULL THEN
  INSERT INTO eshop.customer_order_change_requests(order_id,organization_id,operation,reason,target_form_id,customer_command,status,ticket_ids)
  VALUES(o.id,oc.organization,p_operation,nullif(btrim(p_payload->>'reason'),''),nullif(p_payload->>'targetFormId','')::bigint,p_command,request_status,CASE WHEN p_payload ? 'ticketIds' THEN ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'ticketIds')) END)
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
 ELSIF effect='move' THEN
  PERFORM public.move_customer_order_domain_internal(o.id,(p_payload->>'targetFormId')::bigint);
 ELSIF effect='withdraw' THEN
  UPDATE eshop.customer_order_change_requests SET status='withdrawn',updated_at=clock_timestamp()
   WHERE id=(p_payload->>'requestId')::uuid AND order_id=o.id AND status='open' RETURNING id INTO request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CUSTOMER_CHANGE_CONFLICT' USING ERRCODE='40001'; END IF;
 END IF;
 IF (effect IN ('edit','move','request_cancel','request_move','withdraw') OR p_preview->'partial'='true'::jsonb) AND (SELECT state FROM eshop.orders WHERE id=o.id)<>'storno' THEN
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
  PERFORM public.lock_customer_order_change_internal(parent.order_id,nullif(p_payload->>'targetFormId','')::bigint);
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
 PERFORM public.lock_customer_order_change_internal(cap.order_id,nullif(p_payload->>'targetFormId','')::bigint);
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
 PERFORM public.lock_customer_order_change_internal(o.id,r.target_form_id);
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
  payload:=CASE WHEN r.operation='move' THEN jsonb_build_object('targetFormId',r.target_form_id,'reason',coalesce(r.reason,'')) ELSE jsonb_build_object('reason',coalesce(r.reason,'')) END;
  IF r.ticket_ids IS NOT NULL THEN payload:=payload||jsonb_build_object('ticketIds',to_jsonb(r.ticket_ids)); END IF;
  preview:=public.preview_customer_order_change_internal(o.id,r.operation,payload,true);
  IF preview->>'effect' IN ('request_cancel','request_move') THEN
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
