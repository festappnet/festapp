CREATE OR REPLACE FUNCTION public.delete_resource(p_resource_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; v bigint; result jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.resources WHERE id=p_resource_id;
 PERFORM public.check_is_editor_order_on_occasion(oc);
 PERFORM public.lock_resource_pools_internal_v1(p_resource_id);
 SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='resource' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=p_resource_id::text),0) INTO v;
 result:=public.delete_resource_client_sync_v1(oc,p_resource_id,extensions.gen_random_uuid(),v);
 IF result->>'code'<>'200' THEN RAISE serialization_failure USING MESSAGE='inventory deletion rejected'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.delete_resource(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_resource(bigint) TO authenticated;
