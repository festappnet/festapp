CREATE OR REPLACE FUNCTION public.save_path_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_path jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT public.mutate_map_entity_internal_v1('path','save',p_occasion,
    p_command_id,p_expected_version,NULL,p_path); $function$
;

REVOKE ALL ON FUNCTION public.save_path_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_path jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_path_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_path jsonb) TO authenticated;
