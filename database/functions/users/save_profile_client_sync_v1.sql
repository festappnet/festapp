CREATE OR REPLACE FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_result jsonb;
BEGIN
  v_result:=public.save_profile_companion_internal_v1(
    p_occasion,p_user,p_command_id,p_expected_version,p_profile);
  RETURN v_result;
END $function$
;
REVOKE ALL ON FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb) TO authenticated;
