CREATE OR REPLACE FUNCTION public.reserve_draft_payment_reference(p_payment_info_id bigint,p_variable_symbol bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target eshop.orders; pi eshop.payment_info; claim jsonb; result jsonb; policy jsonb; symbol bigint; users uuid[];
BEGIN
 IF auth.uid() IS NULL OR p_command_id IS NULL OR p_variable_symbol IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
  RAISE insufficient_privilege USING MESSAGE='Invalid payment reference command'; END IF;
 SELECT * INTO STRICT target FROM eshop.orders WHERE payment_info=p_payment_info_id;
 PERFORM public.check_is_editor_order_on_occasion(target.occasion);
 PERFORM public.check_occasion_writable(target.occasion);
 claim:=public.begin_client_mutation_v1(p_command_id,'inventory.payment.reference',target.occasion,auth.uid(),
  encode(extensions.digest(jsonb_build_object('payment',p_payment_info_id,'symbol',p_variable_symbol)::text,'sha256'),'hex'));
 IF claim->>'disposition'='replay' THEN RETURN claim->'response'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[target.id]);
 SELECT * INTO STRICT target FROM eshop.orders WHERE id=target.id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
 IF target.state<>'created' OR pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL
 OR EXISTS(SELECT 1 FROM eshop.transactions WHERE payment_info=pi.id)
 OR EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=target.id) THEN
  RAISE EXCEPTION 'PUBLISHED_PAYMENT_REFERENCE_IMMUTABLE'; END IF;
 policy:=jsonb_build_object('mode','exact','value',p_variable_symbol::text);
 symbol:=public.reserve_payment_reference_internal(pi.id,target.form,'manual:'||p_command_id,policy,
  encode(extensions.digest(jsonb_build_object('payment',pi.id,'symbol',p_variable_symbol)::text,'sha256'),'hex'));
 UPDATE eshop.payment_info SET variable_symbol=symbol,
 creditor_reference=CASE WHEN upper(trim(currency_code))='EUR' THEN public.generate_creditor_reference(symbol) ELSE NULL END WHERE id=pi.id;
 SELECT coalesce(array_agg(ou."user"),'{}') INTO users FROM public.occasion_users ou WHERE ou.occasion=target.occasion;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,target.occasion,'inventory.payment.reference',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',target.id,'operation','update','safeLabel','Payment reference',
  'changedFields',jsonb_build_array('payment_info'))),users,jsonb_build_object('code',200,'variable_symbol',symbol));
END $$;
REVOKE ALL ON FUNCTION public.reserve_draft_payment_reference(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reserve_draft_payment_reference(bigint,bigint,uuid) TO authenticated;
