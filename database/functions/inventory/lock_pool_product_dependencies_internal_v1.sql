-- Match allocation order: forms/orders, products, pool, contexts/resources, spots.
-- A concurrent new link discovered after locking the pool forces a clean retry.
CREATE OR REPLACE FUNCTION public.lock_pool_product_dependencies_internal_v1(p_pool bigint)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_product_ids bigint[];
BEGIN
 SELECT coalesce(array_agg(DISTINCT pic.product ORDER BY pic.product),'{}') INTO v_product_ids
 FROM eshop.product_inventory_contexts pic JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context WHERE ic.inventory_pool=p_pool;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE product=ANY(v_product_ids)));
 PERFORM 1 FROM eshop.products WHERE id=ANY(v_product_ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id=p_pool FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context
   WHERE ic.inventory_pool=p_pool AND NOT pic.product=ANY(v_product_ids)) THEN
  RAISE serialization_failure USING MESSAGE='inventory product dependencies changed; retry the same command'; END IF;
 RETURN v_product_ids;
END $$;
REVOKE ALL ON FUNCTION public.lock_pool_product_dependencies_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
