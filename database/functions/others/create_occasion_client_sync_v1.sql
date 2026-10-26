CREATE OR REPLACE FUNCTION public.create_occasion_client_sync_v1(p_command_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_config jsonb; v_data jsonb;
BEGIN
  v_data:=CASE WHEN jsonb_typeof(p_config->'data')='object'
    THEN p_config->'data' ELSE '{}'::jsonb END;
  v_config:=jsonb_set(p_config,'{data}',
    jsonb_set(v_data,'{client_sync_v1}','false'::jsonb,true),true);
  RETURN public.create_occasion_domain_command_internal_v1(p_command_id,v_config);
END; $function$
;
REVOKE ALL ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb) TO authenticated;
