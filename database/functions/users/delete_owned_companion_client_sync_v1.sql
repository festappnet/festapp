CREATE OR REPLACE FUNCTION public.delete_owned_companion_client_sync_v1(p_occasion bigint, p_companion uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  RETURN public.delete_owned_companion_internal_v1(p_occasion,p_companion,p_command_id);
END $function$
;
REVOKE ALL ON FUNCTION public.delete_owned_companion_client_sync_v1(bigint,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_owned_companion_client_sync_v1(bigint,uuid,uuid) TO authenticated;
