CREATE OR REPLACE FUNCTION public.replace_group_assignments_client_sync_v1(p_occasion bigint, p_command_id uuid, p_assignments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
 RETURN public.replace_group_assignments_companion_internal_v1(p_occasion,p_command_id,p_assignments);
END $function$
;
REVOKE ALL ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) TO authenticated;
