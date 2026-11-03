CREATE OR REPLACE FUNCTION public.replace_group_assignments_client_sync_v1(p_occasion bigint, p_command_id uuid, p_assignments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_before jsonb; v_after jsonb; v_changed bigint[];
  v_group_ids bigint[]; v_impacted_users uuid[]; v_private_impacts jsonb;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
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
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT (public.get_is_editor_on_occasion(p_occasion) OR public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR public.get_is_editor_on_unit(v_unit)) THEN RAISE insufficient_privilege USING MESSAGE='group import permission required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
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
  SELECT COALESCE(jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version'),'{}') INTO v_before FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL;
  PERFORM public.import_user_group_assignments_internal_v1(
    p_occasion,p_assignments);
  SELECT COALESCE(jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version'),'{}') INTO v_after FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL;
  IF v_before=v_after THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,jsonb_build_object('assignments',jsonb_array_length(p_assignments))); END IF;
  SELECT ARRAY(SELECT key::bigint FROM jsonb_each(v_after) WHERE value IS DISTINCT FROM v_before->key ORDER BY key::bigint) INTO v_changed;
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
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_changed) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,v_impacted_users);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.groups.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group_membership','entityId',NULL,'operation','import',
      'safeLabel','Group assignment import','changedFields',jsonb_build_array('memberships'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'assignments',jsonb_array_length(p_assignments)),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) TO authenticated;
