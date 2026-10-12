CREATE OR REPLACE FUNCTION public.delete_user_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_users uuid[]; v_place bigint; v_private_place boolean;
  v_private_impacts jsonb; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'groupId',p_group_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=p_group_id
    AND g.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'group',NULL)); END IF;
  SELECT public.get_user_group_command_data_v1(g.id),g.place,
    COALESCE(p.is_hidden AND p.type='group',false)
    INTO v_entity,v_place,v_private_place
  FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
  WHERE g.id=p_group_id;
  SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[])
    INTO v_users FROM public.user_groups ug WHERE ug."group"=p_group_id;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',p_occasion,p_group_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_group_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'group',v_entity)); END IF;
  IF v_private_place THEN PERFORM public.assert_group_place_owner_internal_v1(p_occasion,p_group_id,v_place,true); END IF;
  DELETE FROM public.user_groups WHERE "group"=p_group_id;
  DELETE FROM public.user_group_info WHERE id=p_group_id;
  IF v_private_place THEN
    DELETE FROM public.places WHERE id=v_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_place::text;
  END IF;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,v_users);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',p_group_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
