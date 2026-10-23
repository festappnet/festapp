-- Released full-editor receipt API delegates to the same private command owner.
CREATE OR REPLACE FUNCTION public.save_inventory_pool_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_bundle jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_inventory_pool_command_internal(p_occasion,p_command_id,p_expected_version,p_bundle,true)
$$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
