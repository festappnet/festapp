CREATE OR REPLACE FUNCTION public.save_game_settings_command_internal_v1(p_occasion bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb; v_version bigint;
BEGIN
  IF v_actor IS NULL OR NOT public.can_edit_game_settings(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion',p_occasion,'start',p_start,'end',p_end)||CASE WHEN p_expected_version IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('expectedVersion',p_expected_version) END)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.game.settings',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.data INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('occasion','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions WHERE aggregate_type='occasion' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text FOR UPDATE;
  IF p_expected_version IS NOT NULL AND p_expected_version IS DISTINCT FROM v_version THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',v_version,'game',v_before->'game'));
  END IF;
  v_result:=public.game_update_settings_internal_v1(p_occasion,p_start,p_end);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      400,v_result); END IF;
  SELECT o.data INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  v_result:=v_result||jsonb_build_object('version',v_version,'game',v_after->'game');
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('occasion','occasion',p_occasion,p_occasion::text,1)
  ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
  SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
  v_result:=v_result||jsonb_build_object('version',v_version+1);
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.game.settings','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','game_settings','entityId',p_occasion,'operation','update',
      'safeLabel','Game settings','changedFields',jsonb_build_array('data.game'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.save_game_settings_command_internal_v1(bigint,timestamptz,timestamptz,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
-- Released four-argument facade delegates to the same receipt owner.
CREATE OR REPLACE FUNCTION public.game_update_settings_client_sync_v1(p_occasion bigint,p_start timestamptz,p_end timestamptz,p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_game_settings_command_internal_v1(p_occasion,p_start,p_end,p_command_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.game_update_settings_client_sync_v1(p_occasion bigint,p_start timestamptz,p_end timestamptz,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_expected_version IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='original game settings version required'; END IF;
 RETURN public.save_game_settings_command_internal_v1(p_occasion,p_start,p_end,p_command_id,p_expected_version);
END $$;
REVOKE ALL ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_update_settings_client_sync_v1(bigint,timestamptz,timestamptz,uuid,bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_game_settings_for_authoring_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.occasions WHERE id=p_occasion FOR SHARE;
 IF NOT public.can_edit_game_settings(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='game settings scope denied'; END IF;
 RETURN (SELECT jsonb_build_object('game',COALESCE(NULLIF(o.data->'game','null'::jsonb),'{}'),'version',COALESCE(v.version,0)) FROM public.occasions o LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text WHERE o.id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_game_settings_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_game_settings_for_authoring_v1(bigint) TO authenticated;
