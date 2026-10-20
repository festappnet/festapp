CREATE OR REPLACE FUNCTION public.get_resources_for_inventory_pool_v1(p_inventory_pool_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_occasion bigint; v_result jsonb;
BEGIN
  SELECT ip.occasion INTO v_occasion FROM public.inventory_pools ip
    WHERE ip.id=p_inventory_pool_id;
  IF v_occasion IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='inventory pool not found'; END IF;
  PERFORM public.check_is_editor_order_view_on_occasion(v_occasion);
  SELECT COALESCE(jsonb_agg(to_jsonb(r)||jsonb_build_object(
    'aggregate_version',COALESCE(v.version,0)) ORDER BY r.id),'[]'::jsonb)
    INTO v_result FROM public.resources r
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='resource'
      AND v.scope_type='occasion' AND v.scope_id=v_occasion
      AND v.aggregate_id=r.id::text
    WHERE r.inventory_pool=p_inventory_pool_id;
  RETURN v_result;
END; $function$;
REVOKE ALL ON FUNCTION public.get_resources_for_inventory_pool_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_resources_for_inventory_pool_v1(bigint) TO authenticated;
