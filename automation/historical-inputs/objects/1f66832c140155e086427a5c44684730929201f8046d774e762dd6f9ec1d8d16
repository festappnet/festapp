CREATE OR REPLACE FUNCTION public.delete_occasion_client_sync_v1(p_occasion bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN RETURN public.delete_occasion_domain_command_internal_v1(p_occasion,p_command_id); END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid) TO authenticated;
