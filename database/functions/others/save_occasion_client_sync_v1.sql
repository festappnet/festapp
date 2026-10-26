CREATE OR REPLACE FUNCTION public.save_occasion_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE config jsonb:=p_config; enabled jsonb;
BEGIN
 IF p_config ? 'data' AND jsonb_typeof(p_config->'data')='object' THEN
  SELECT COALESCE(data->'client_sync_v1','false') INTO enabled FROM public.occasions WHERE id=p_occasion;
  config:=jsonb_set(p_config,'{data}',jsonb_set(p_config->'data','{client_sync_v1}',COALESCE(enabled,'false'),true));
 END IF;
 RETURN public.save_occasion_domain_command_internal_v1(p_occasion,p_command_id,p_expected_version,config);
END $$;
REVOKE ALL ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
