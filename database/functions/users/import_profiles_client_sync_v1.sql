CREATE OR REPLACE FUNCTION public.import_profiles_client_sync_v1(p_occasion bigint, p_command_id uuid, p_rows jsonb, p_delete_user_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
 RETURN public.import_profiles_companion_internal_v1(p_occasion,p_command_id,p_rows,p_delete_user_ids);
END $function$
;
REVOKE ALL ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb) TO authenticated;
