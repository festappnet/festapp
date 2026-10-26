-- Released clients retain their original receipt fingerprint and response.
CREATE OR REPLACE FUNCTION public.swap_spot_tickets_client_sync_v1(p_spot_1 bigint,p_spot_2 bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.swap_blueprint_seats_command_internal(p_spot_1,p_spot_2,p_command_id)
$$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) TO authenticated;
