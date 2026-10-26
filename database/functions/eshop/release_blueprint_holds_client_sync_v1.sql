-- Released legacy intent delegates to the one receipt owner.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_client_sync_v1(p_spots bigint[],p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.release_blueprint_holds_command_internal(p_spots,p_command_id)
$$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) TO authenticated;
