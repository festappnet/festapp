-- Called only after the originating receipt's actor/hash checks. No new public
-- order-ID lookup or capability is introduced; the receipt itself stays immutable.
CREATE OR REPLACE FUNCTION public.project_local_payment_reference_order_internal(p_response jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=CASE WHEN p_response ? 'data' THEN p_response->'data' ELSE p_response END;
 target eshop.orders; payment eshop.payment_info; details jsonb;
BEGIN
 IF payload#>>'{order,id}' IS NULL THEN RETURN p_response; END IF;
 SELECT * INTO target FROM eshop.orders WHERE id=(payload#>>'{order,id}')::bigint;
 IF target.id IS NULL OR target.state='storno' THEN
  payload:=jsonb_set(payload,'{order,payment_info}','null')||jsonb_build_object('code',409,'errorCode','ORDER_NOT_PAYABLE');
 ELSE
  SELECT * INTO payment FROM eshop.payment_info WHERE id=target.payment_info;
  IF payment.id IS NOT NULL THEN
   details:=coalesce(payload#>'{order,payment_info}','{}')||jsonb_build_object('id',payment.id,'variable_symbol',payment.variable_symbol,
    'creditor_reference',payment.creditor_reference,'amount',payment.amount,'deposit_amount',payment.deposit_amount,
    'deadline',payment.deadline,'deposit_deadline',payment.deposit_deadline,'currency_code',payment.currency_code);
   payload:=jsonb_set(payload,'{order,payment_info}',details);
   IF payment.payment_method='stripe' THEN
    payload:=payload||jsonb_build_object('payment',public.stripe_order_payment_projection_internal(target.id));
   END IF;
  END IF;
 END IF;
 IF p_response ? 'data' THEN RETURN jsonb_set(p_response,'{data}',payload); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.project_local_payment_reference_order_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
