CREATE OR REPLACE FUNCTION public.delete_service_item_client_sync_v1(p_occasion bigint, p_type text, p_code text, p_force boolean, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_users uuid[];
BEGIN
  IF v_actor IS NULL OR p_force IS NULL OR p_type NOT IN ('food','accommodation')
    OR nullif(btrim(p_code),'') IS NULL OR length(p_code)>100
    OR NOT public.get_is_manager_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'type',p_type,'code',p_code,
    'force',p_force)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.service.delete',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.occasions WHERE id=p_occasion FOR UPDATE;
  PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion ORDER BY "user" FOR UPDATE;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND (
    (p_force AND ou.services->p_type->>p_code IS NOT NULL
      AND ou.services->p_type->>p_code<>'none') OR
    (NOT p_force AND (ou.services->p_type->>p_code IS NULL
      OR ou.services->p_type->>p_code='none')));
  v_result:=public.delete_service_item_internal_v1(
    p_occasion,p_type,p_code,p_force);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),v_result); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',p_occasion,p_occasion::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,
    'occasion.service.delete',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_service','entityId',p_code,'operation','delete',
      'safeLabel',p_code,'changedFields',jsonb_build_array('services'))),
    v_users,ARRAY['occasion_config'],'[]',v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_service_item_client_sync_v1(bigint,text,text,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_service_item_client_sync_v1(bigint,text,text,boolean,uuid) TO authenticated;
