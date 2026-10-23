CREATE OR REPLACE FUNCTION public.delete_path_client_sync_v1(p_occasion bigint, p_path_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public.mutate_map_entity_internal_v1('path','delete',p_occasion,
    p_command_id,p_expected_version,p_path_id,NULL); $function$
;

REVOKE ALL ON FUNCTION public.delete_path_client_sync_v1(p_occasion bigint, p_path_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.delete_path_client_sync_v1(p_occasion bigint, p_path_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
