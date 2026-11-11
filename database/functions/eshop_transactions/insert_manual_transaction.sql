CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text,
    p_note text DEFAULT NULL,
    p_payment_info_id int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    PERFORM public.insert_manual_transaction_internal_v1(p_amount::numeric,p_currency,p_unit_id::bigint,
      p_variable_symbol,p_date::timestamptz,p_note,p_payment_info_id::bigint);
END;
$$;

REVOKE ALL ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  TO authenticated;

-- Exact receipted ingress. The released floating-point RPC remains a bounded
-- compatibility facade over the same cash movement owner.
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(input_data jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; u bigint; begin_result jsonb; transaction_id bigint; users uuid[]; result jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE payment_info=(input_data->>'paymentInfoId')::bigint;
 SELECT unit INTO u FROM public.occasions WHERE id=o.occasion;
 PERFORM public.check_is_manager_on_unit(u);
 IF u IS DISTINCT FROM (input_data->>'unitId')::bigint OR trim(o.currency_code) IS DISTINCT FROM input_data->>'currency' THEN
  RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^-?[0-9]{1,8}(\.[0-9]{1,2})?$' THEN
  RAISE EXCEPTION 'CASH_AMOUNT_INVALID'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 begin_result:=public.begin_client_mutation_v1(p_command_id,'orders.cash.record',o.occasion,auth.uid(),
  encode(extensions.digest(input_data::text,'sha256'),'hex'));
 IF begin_result->>'disposition'='replay' THEN RETURN jsonb_set(begin_result->'response','{mutation,replayed}','true'); END IF;
 transaction_id:=public.insert_manual_transaction_internal_v1((input_data->>'amount')::numeric,input_data->>'currency',u,NULL,
  (input_data->>'receivedAt')::timestamptz,input_data->>'note',o.payment_info);
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'orders.cash.record',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('payment'))),users,
  jsonb_build_object('orderId',o.id,'transactionId',transaction_id,'payment',public.customer_order_payment_internal(o.id)));
END $$;
REVOKE ALL ON FUNCTION public.insert_manual_transaction(jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(jsonb,uuid) TO authenticated;
