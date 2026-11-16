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
