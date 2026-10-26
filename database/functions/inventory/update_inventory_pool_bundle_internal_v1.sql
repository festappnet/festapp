-- Existing complete-editor snapshot boundary; mutation has one shared owner.
CREATE OR REPLACE FUNCTION public.update_inventory_pool_bundle_internal_v1(p_bundle_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE pool_id bigint;
BEGIN
 IF public.can_write_orders((p_bundle_data#>>'{pool,occasion}')::bigint) IS DISTINCT FROM TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
 pool_id:=public.save_inventory_pool_internal(p_bundle_data);
 RETURN public.get_inventory_pool_bundle(pool_id);
END $$;
REVOKE ALL ON FUNCTION public.update_inventory_pool_bundle_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;
