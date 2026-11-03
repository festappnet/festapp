CREATE OR REPLACE FUNCTION public.game_update_settings_client_sync_v1(p_occasion bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'start',p_start,'end',p_end)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.game.settings',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.data INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  v_result:=public.game_update_settings_internal_v1(p_occasion,p_start,p_end);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      400,v_result); END IF;
  SELECT o.data INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('occasion','occasion',p_occasion,p_occasion::text,1)
  ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
  SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.game.settings','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','game_settings','entityId',p_occasion,'operation','update',
      'safeLabel','Game settings','changedFields',jsonb_build_array('data.game'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid) TO authenticated;
