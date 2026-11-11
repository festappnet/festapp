-- Configuration is resolved once, under the checkout form lock. Only metadata
-- belongs in payment_policy; amount, method, deadline and bank identity stay in columns.
-- Both stored forms and authorized draft previews pass their data to this owner.
CREATE OR REPLACE FUNCTION public.resolve_payment_policy_internal(p_metadata jsonb,p_duration bigint,p_feature jsonb,p_method text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE mode text; seconds bigint;
BEGIN
 mode:=coalesce(p_metadata#>>'{payment_deadline,mode}',CASE WHEN p_duration IS NULL THEN 'inherit' ELSE 'custom' END);
 IF mode NOT IN ('inherit','custom','none') THEN RAISE EXCEPTION 'PAYMENT_DEADLINE_INVALID'; END IF;
 IF p_method='cash' THEN RETURN jsonb_build_object('mode','none','cashInstructions',coalesce(p_metadata#>>'{payments,cashInstructions}','')); END IF;
 IF public.payment_method_is_online_internal(p_method) THEN RETURN '{"mode":"provider"}'::jsonb; END IF;
 IF mode='inherit' THEN mode:=coalesce(p_feature#>>'{payment_deadline,mode}','custom'); END IF;
 IF mode='none' THEN RETURN '{"mode":"none"}'::jsonb; END IF;
 seconds:=coalesce(p_duration,(p_feature->>'deadline_duration_seconds')::bigint,604800);
 IF seconds<0 OR (p_metadata#>>'{payment_deadline,mode}'='custom' AND p_duration IS NULL) THEN
  RAISE EXCEPTION 'PAYMENT_DEADLINE_INVALID'; END IF;
 RETURN jsonb_build_object('mode','custom','durationSeconds',seconds);
END $$;
REVOKE ALL ON FUNCTION public.resolve_payment_policy_internal(jsonb,bigint,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.resolve_form_payment_policy_internal(p_form bigint,p_method text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; feature jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 SELECT elem INTO feature FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) elem
 WHERE o.id=f.occasion AND elem->>'code'='form';
 RETURN public.resolve_payment_policy_internal(f.data,f.deadline_duration_seconds,feature,p_method);
END $$;

-- The sole bounded legacy interpretation. New snapshots retain absolute dates.
CREATE OR REPLACE FUNCTION public.refresh_order_payment_deadline_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; feature jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF public.payment_method_is_online_internal(pi.payment_method) THEN RETURN; END IF;
 IF pi.data ? 'payment_policy' THEN
  IF pi.data#>>'{payment_policy,mode}'='none' THEN
   UPDATE eshop.payment_info SET deadline=NULL,deposit_deadline=NULL WHERE id=pi.id;
  END IF;
  RETURN;
 END IF;
 SELECT elem INTO feature FROM public.occasions oc CROSS JOIN LATERAL jsonb_array_elements(oc.features) elem
 WHERE oc.id=o.occasion AND elem->>'code'='form';
 -- Historical orders alone retain the former product-editor calculation.
 UPDATE eshop.payment_info SET deadline=CASE WHEN o.price>0 THEN now()+make_interval(secs=>coalesce((feature->>'deadline_duration_seconds')::bigint,604800)) END
 WHERE id=pi.id;
 PERFORM public.queue_payment_reminders_internal(o.occasion,pi.id);
END $$;

CREATE OR REPLACE FUNCTION public.check_payment_client_capabilities_internal(p_policy jsonb,p_method text,p_capabilities jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (p_method='cash' AND NOT coalesce(p_capabilities ? 'cash_reservations',false))
  OR (p_policy->>'mode'='none' AND NOT coalesce(p_capabilities ? 'no_payment_deadline',false)) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','PAYMENT_CLIENT_UPDATE_REQUIRED',
   'message','Open the current website to use these payment instructions.')::text;
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guard_form_payment_write_internal(p_saved jsonb,p_candidate jsonb,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb:=p_candidate; incoming jsonb; merged jsonb;
 explicit_selection boolean:=p_input->>'payment_selection_intent'='replace'; conflict boolean:=false;
BEGIN
 IF p_input ? 'payment_selection_intent' AND p_input->>'payment_selection_intent' IS DISTINCT FROM 'replace' THEN
  RAISE EXCEPTION 'PAYMENT_SELECTION_INTENT_INVALID'; END IF;
 incoming:=coalesce(p_input#>'{settings,payments}',p_input#>'{data,payments}');
 IF NOT coalesce(explicit_selection,false) THEN
  IF p_saved#>'{payments,cashEnabled}'='true'::jsonb AND incoming IS NOT NULL THEN
   BEGIN
    merged:=public.merge_form_payments_internal(p_saved->'payments',incoming);
    conflict:=merged IS DISTINCT FROM public.merge_form_payments_internal(p_saved->'payments',NULL);
   EXCEPTION WHEN raise_exception THEN conflict:=true; END;
  END IF;
  IF incoming IS NULL AND p_saved ? 'payments' THEN result:=result||jsonb_build_object('payments',p_saved->'payments'); END IF;
  IF NOT (coalesce(p_input->'settings',p_input->'data','{}'::jsonb) ? 'payment_deadline') AND p_saved ? 'payment_deadline' THEN
   result:=result||jsonb_build_object('payment_deadline',p_saved->'payment_deadline'); END IF;
  IF conflict
   OR (p_saved#>>'{payment_deadline,mode}'='none' AND result#>>'{payment_deadline,mode}' IS DISTINCT FROM 'none')
   OR (result#>'{payments,cashEnabled}'='true'::jsonb AND p_saved#>'{payments,cashEnabled}' IS DISTINCT FROM 'true'::jsonb)
   OR (result#>>'{payment_deadline,mode}'='none' AND p_saved#>>'{payment_deadline,mode}' IS DISTINCT FROM 'none') THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','PAYMENT_CLIENT_UPDATE_REQUIRED',
    'message','Update the editor before changing payment selection.')::text;
  END IF;
 END IF;
 IF result#>'{payments,cashEnabled}'='true'::jsonb THEN
  result:=result||'{"payment_deadline":{"mode":"none"}}'::jsonb;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.resolve_form_payment_policy_internal(bigint,text),public.refresh_order_payment_deadline_internal(bigint),
 public.check_payment_client_capabilities_internal(jsonb,text,jsonb),public.guard_form_payment_write_internal(jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
