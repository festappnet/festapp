CREATE OR REPLACE FUNCTION public.lock_product_order_dependencies_internal_v1(p_product bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 SELECT ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE product=p_product ORDER BY "order") INTO ids;
 PERFORM public.lock_order_capacity_scope_internal(ids);
 PERFORM 1 FROM eshop.products WHERE id=p_product FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE product=p_product AND NOT "order"=ANY(ids)) THEN
  RAISE serialization_failure USING MESSAGE='product order parents changed; retry the same command'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_product_order_dependencies_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
