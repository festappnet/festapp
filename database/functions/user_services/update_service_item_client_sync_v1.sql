CREATE OR REPLACE FUNCTION public.update_service_item_client_sync_v1(p_occasion bigint, p_type text, p_code text, p_title text, p_reference bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb;
BEGIN
  IF v_actor IS NULL OR p_type NOT IN ('food','accommodation')
    OR nullif(btrim(p_code),'') IS NULL OR length(p_code)>100
    OR length(COALESCE(p_title,''))>500
    OR NOT public.can_write_service_items(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'type',p_type,'code',p_code,'title',p_title,
    'reference',p_reference)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.service.update',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.services INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  v_result:=public.update_service_item_internal_v1(
    p_occasion,p_type,p_code,p_title,p_reference);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      404,v_result); END IF;
  SELECT o.services INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('occasion','occasion',p_occasion,p_occasion::text,1)
  ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
  SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.service.update','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_service','entityId',p_code,'operation','update',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array('services'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.update_service_item_client_sync_v1(bigint,text,text,text,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_service_item_client_sync_v1(bigint,text,text,text,bigint,uuid) TO authenticated;
