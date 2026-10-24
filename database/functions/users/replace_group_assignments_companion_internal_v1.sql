CREATE OR REPLACE FUNCTION public.replace_group_assignments_companion_internal_v1(p_occasion bigint, p_command_id uuid, p_assignments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_companions uuid[]; v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_group_ids bigint[]; v_impacted_users uuid[]; v_private_impacts jsonb;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='group import permission required'; END IF;
  IF p_assignments IS NULL OR jsonb_typeof(p_assignments)<>'array'
    OR jsonb_array_length(p_assignments)>10000
    OR octet_length(p_assignments::text)>2097152 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group assignments'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'assignments',p_assignments)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.groups.import',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(uc.companion),'{}'::uuid[]) INTO v_companions
  FROM public.user_companions uc WHERE uc.occasion=p_occasion;

  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    AND g.type IS NULL ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" JOIN jsonb_to_recordset(p_assignments)
      x(user_id uuid,group_title text) ON x.user_id=ug."user"
    WHERE g.occasion=p_occasion AND g.type IS NULL;
  SELECT COALESCE(array_agg(DISTINCT members."user"),'{}'::uuid[])
    INTO v_impacted_users FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids);
  PERFORM public.import_user_group_assignments_internal_v1(
    p_occasion,p_assignments);
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    JOIN jsonb_to_recordset(p_assignments) x(user_id uuid,group_title text)
      ON x.user_id=ug."user" WHERE g.occasion=p_occasion AND g.type IS NULL),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_impacted_users||COALESCE((
    SELECT array_agg(members."user") FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids)),'{}'::uuid[])) id ORDER BY id)
    INTO v_impacted_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_group_ids) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
  FROM unnest(v_impacted_users) id JOIN public.occasion_users ou
    ON ou.occasion=p_occasion AND ou."user"=id;
  IF v_actor=ANY(v_impacted_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  PERFORM public.impact_companion_owners_v1(p_occasion,v_companions,'profile.companion_group.changed');
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.groups.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group_membership','entityId',NULL,'operation','import',
      'safeLabel','Group assignment import','changedFields',jsonb_build_array('memberships'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'assignments',jsonb_array_length(p_assignments)),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.replace_group_assignments_companion_internal_v1(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
