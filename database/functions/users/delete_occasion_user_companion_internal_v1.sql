CREATE OR REPLACE FUNCTION public.delete_occasion_user_companion_internal_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_owners uuid[]; v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_profile jsonb; v_event_ids bigint[]; v_group_ids bigint[];
  v_private_impacts jsonb; v_publishable boolean;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT uc."user"),'{}'::uuid[]) INTO v_owners
  FROM public.user_companions uc WHERE uc.occasion=p_occasion AND uc.companion=p_user;

  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_profile:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_profile)); END IF;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
  FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  WHERE e.occasion=p_occasion AND (eu."user"=p_user OR es."user"=p_user);
  SELECT COALESCE(array_agg(ug."group"),'{}'::bigint[]) INTO v_group_ids
  FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
  WHERE ug."user"=p_user AND g.occasion=p_occasion;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',members."user")),'[]'::jsonb) INTO v_private_impacts
  FROM public.user_groups members WHERE members."group"=ANY(v_group_ids)
    AND members."user"<>p_user;
  v_private_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion
    AND user_id=p_user;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_private_impacts) impact
    WHERE impact->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  PERFORM public.impact_private_profile_users_v1(p_occasion,v_owners,'profile.companion_membership.deleted');
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','delete',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('membership'))),
    CASE WHEN v_publishable AND cardinality(v_event_ids)>0 THEN ARRAY['live_public']
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,
    jsonb_build_object('version',v_version,'profile',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion_user_companion_internal_v1(bigint,uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
