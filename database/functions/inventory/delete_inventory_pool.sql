CREATE OR REPLACE FUNCTION public.delete_inventory_pool(p_inventory_pool_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; v bigint; result jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.inventory_pools WHERE id=p_inventory_pool_id;
 PERFORM public.check_is_editor_order_on_occasion(oc);

 PERFORM public.lock_pool_product_dependencies_internal_v1(p_inventory_pool_id);
 PERFORM 1 FROM public.inventory_pools WHERE id=p_inventory_pool_id FOR UPDATE;
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='inventory_pool' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=p_inventory_pool_id::text),0) INTO v;
 result:=public.delete_inventory_pool_client_sync_v1(oc,p_inventory_pool_id,extensions.gen_random_uuid(),v);
 IF result->>'code'<>'200' THEN RAISE serialization_failure USING MESSAGE='inventory deletion rejected'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.delete_inventory_pool(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_inventory_pool(bigint) TO authenticated;
