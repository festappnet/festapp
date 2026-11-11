CREATE OR REPLACE FUNCTION public.record_payment_fact_sync_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; impacts jsonb;
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM eshop.orders WHERE id=p_order;
 SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_inventory','userId',"user")),'[]') INTO impacts
 FROM public.occasion_users WHERE occasion=occasion_id;
 PERFORM public.record_client_sync_commit_v1(occasion_id,'orders.payment.fact','inventory',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,'operation','update','changedFields',jsonb_build_array('payment'))),
  '{}'::text[],impacts,'[]'::jsonb,CASE WHEN auth.role()='service_role' THEN 'service' ELSE 'user' END,NULL);
END $$;
REVOKE ALL ON FUNCTION public.record_payment_fact_sync_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
