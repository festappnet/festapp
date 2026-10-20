-- Lock both sides of a resource move before the resource, in deterministic order.
CREATE OR REPLACE FUNCTION public.lock_resource_pools_internal_v1(p_resource bigint,p_target bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE origin bigint; current_pool bigint;
BEGIN
 SELECT inventory_pool INTO origin FROM public.resources WHERE id=p_resource;
 PERFORM 1 FROM public.inventory_pools WHERE id=ANY(ARRAY[origin,p_target]) ORDER BY id FOR UPDATE;
 SELECT inventory_pool INTO current_pool FROM public.resources WHERE id=p_resource FOR UPDATE;
 IF current_pool IS DISTINCT FROM origin THEN
  RAISE serialization_failure USING MESSAGE='resource pool changed; retry the same command'; END IF;
 RETURN origin;
END $$;
REVOKE ALL ON FUNCTION public.lock_resource_pools_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
