CREATE OR REPLACE FUNCTION public.delete_owned_companion_internal_v1(p_occasion bigint, p_companion uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_event_ids bigint[];
  v_group_ids bigint[]; v_private_impacts jsonb; v_replacements jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_companion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion delete'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=v_actor)
    OR NOT coalesce((public.get_companion_feature_policy_v1(p_occasion)->>'is_enabled')::boolean,false)
    OR NOT coalesce((public.get_companion_feature_policy_v1(p_occasion)->>'allow_user_create')::boolean,true) THEN
    RAISE insufficient_privilege USING MESSAGE='self-created companion lifecycle disabled'; END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('attendance-user:'||p_companion::text||':'||p_occasion::text,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('saved-program:'||p_companion::text||':'||p_occasion::text,0));
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.user_info ui WHERE ui.id=p_companion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('companion',NULL)); END IF;
  PERFORM 1 FROM public.occasion_users WHERE "user"=p_companion ORDER BY occasion FOR UPDATE;
  PERFORM 1 FROM public.user_companions WHERE occasion=p_occasion AND companion=p_companion FOR UPDATE;
  PERFORM public.delete_owned_companion_guard_v1(p_occasion,p_companion);
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE "user"=p_companion AND occasion<>p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='cross-occasion companion requires manual cleanup'; END IF;

  SELECT COALESCE(array_agg(DISTINCT event_id ORDER BY event_id),'{}'::bigint[])
    INTO v_event_ids FROM (
      SELECT eu.event event_id FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_companion AND e.occasion=p_occasion
      UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_companion AND e.occasion=p_occasion
    ) affected;
  SELECT COALESCE(array_agg(ug."group" ORDER BY ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" WHERE ug."user"=p_companion AND g.occasion=p_occasion;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=ANY(v_group_ids) ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',impacted.user_id)),'[]'::jsonb) INTO v_private_impacts FROM (
      SELECT v_actor user_id UNION SELECT ug."user" FROM public.user_groups ug
        WHERE ug."group"=ANY(v_group_ids) AND ug."user"<>p_companion
    ) impacted JOIN public.occasion_users ou ON ou.occasion=p_occasion
      AND ou."user"=impacted.user_id;
  SELECT coalesce(jsonb_agg(DISTINCT item),'[]') INTO v_private_impacts FROM jsonb_array_elements(
    public.remove_occasion_user_domain_internal_v1(p_occasion,p_companion)||
    jsonb_build_array(jsonb_build_object('component','private_profile','userId',v_actor))) item;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_companion::text;
  DELETE FROM public.user_reset_token WHERE "user"=p_companion;
  DELETE FROM public.user_companions WHERE "user"=p_companion OR companion=p_companion;
  DELETE FROM public.user_info WHERE id=p_companion;
  DELETE FROM auth.identities WHERE user_id=p_companion;
  DELETE FROM auth.users WHERE id=p_companion;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',p_companion,'operation','delete',
      'safeLabel','Companion','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND cardinality(v_event_ids)>0
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',event_id)) FROM unnest(v_event_ids) event_id),
      '[]'::jsonb) ELSE '[]'::jsonb END,
    jsonb_build_object('companion',NULL),'{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_owned_companion_internal_v1(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
