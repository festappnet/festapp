-- Published legacy shape. Version is selected under the same parent lock.
CREATE OR REPLACE FUNCTION public.update_inventory_pool_bundle(p_bundle_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_id bigint:=(p_bundle_data#>>'{pool,id}')::bigint; oc bigint; v bigint; result jsonb; bundle jsonb:=p_bundle_data;
BEGIN
 oc:=(bundle#>>'{pool,occasion}')::bigint;
 IF v_id IS NOT NULL THEN SELECT occasion INTO oc FROM public.inventory_pools WHERE inventory_pools.id=v_id; END IF;
 PERFORM public.check_is_editor_order_on_occasion(oc);
 IF v_id IS NOT NULL THEN
 PERFORM public.lock_pool_product_dependencies_internal_v1(v_id);
  PERFORM 1 FROM public.inventory_pools WHERE inventory_pools.id=v_id FOR UPDATE;
  SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='inventory_pool'
   AND scope_type='occasion' AND scope_id=oc AND aggregate_id=v_id::text),0) INTO v;
  IF NOT bundle ? 'contexts' THEN bundle:=bundle||jsonb_build_object('contexts',public.get_inventory_pool_bundle(v_id)->'contexts'); END IF;
 END IF;
 result:=public.save_inventory_pool_client_sync_v1(oc,extensions.gen_random_uuid(),v,bundle);
 IF result->>'code'<>'200' THEN RAISE serialization_failure USING MESSAGE='inventory pool save rejected'; END IF;
 RETURN result#>'{data,bundle}';
END $$;
REVOKE ALL ON FUNCTION public.update_inventory_pool_bundle(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_inventory_pool_bundle(jsonb) TO authenticated;
