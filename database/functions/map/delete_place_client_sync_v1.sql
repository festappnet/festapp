CREATE OR REPLACE FUNCTION public.delete_place_client_sync_v1(p_occasion bigint, p_place_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public.mutate_map_entity_internal_v1('place','delete',p_occasion,
    p_command_id,p_expected_version,p_place_id,NULL); $function$
;
REVOKE ALL ON FUNCTION public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
