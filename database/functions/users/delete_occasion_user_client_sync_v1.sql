CREATE OR REPLACE FUNCTION public.delete_occasion_user_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
 RETURN public.delete_occasion_user_companion_internal_v1(p_occasion,p_user,p_command_id,p_expected_version);
END $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint) TO authenticated;
