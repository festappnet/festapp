CREATE OR REPLACE FUNCTION public.import_profiles_companion_internal_v1(p_occasion bigint, p_command_id uuid, p_rows jsonb, p_delete_user_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_owners uuid[]; v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_result jsonb; v_before_users uuid[]; v_after_users uuid[]; v_current_users uuid[];
  v_event_ids bigint[]; v_group_ids bigint[]; v_private_impacts jsonb;
  v_publishable boolean; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT o.unit,NOT o.is_hidden INTO v_unit,v_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array'
    OR p_delete_user_ids IS NULL OR jsonb_typeof(p_delete_user_ids)<>'array'
    OR jsonb_array_length(p_rows)>10000 OR jsonb_array_length(p_delete_user_ids)>10000
    OR octet_length(p_rows::text)+octet_length(p_delete_user_ids::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid profile import'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'rows',p_rows,'deleteUserIds',p_delete_user_ids)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.users.import',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT uc."user"),'{}'::uuid[]) INTO v_owners
  FROM public.user_companions uc WHERE uc.occasion=p_occasion;

  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    ORDER BY g.id FOR UPDATE;
  PERFORM 1 FROM public.user_info ui WHERE ui.id IN(
    SELECT ou."user" FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    UNION SELECT (r->>'user_id')::uuid FROM jsonb_array_elements(p_rows) r WHERE nullif(r->>'user_id','') IS NOT NULL)
    OR (ui.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) AND lower(btrim(ui.email_readonly)) IN(
      SELECT lower(btrim(r#>>'{data,email}')) FROM jsonb_array_elements(p_rows) r)) ORDER BY ui.id FOR UPDATE;
  PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion ORDER BY "user" FOR UPDATE;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND (eu."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR
      es."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))));
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[]) INTO v_group_ids
    FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
    JOIN public.user_info ui ON ui.id=ug."user"
    WHERE g.occasion=p_occasion AND (ug."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR ug."user"=ANY(
      COALESCE((SELECT array_agg((row->>'user_id')::uuid)
        FROM jsonb_array_elements(p_rows) row
        WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(ui.email_readonly))=ANY(COALESCE((SELECT array_agg(
        lower(btrim(row#>>'{data,email}'))) FROM jsonb_array_elements(p_rows) row),
        '{}'::text[])));
  v_result:=public.import_occasion_users_from_csv_internal_v1(
    p_occasion,p_rows,p_delete_user_ids);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE data_exception USING MESSAGE=COALESCE(v_result->>'message','profile import failed');
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT ou."user" ORDER BY ou."user"),'{}'::uuid[])
    INTO v_current_users FROM public.occasion_users ou
    JOIN public.user_info ui ON ui.id=ou."user"
    WHERE ou.occasion=p_occasion AND (ou."user"=ANY(COALESCE((SELECT array_agg(
      (row->>'user_id')::uuid) FROM jsonb_array_elements(p_rows) row
      WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(COALESCE(ui.email_readonly,ou.data->>'email')))=ANY(COALESCE((
        SELECT array_agg(lower(btrim(row#>>'{data,email}')))
        FROM jsonb_array_elements(p_rows) row),'{}'::text[])) OR
      NOT ou."user"=ANY(v_before_users));
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(DISTINCT ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE g.occasion=p_occasion AND ug."user"=ANY(v_current_users)),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_current_users||COALESCE((
    SELECT array_agg(DISTINCT ug."user") FROM public.user_groups ug
    WHERE ug."group"=ANY(v_group_ids)),'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id
    ORDER BY id) INTO v_current_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_current_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_group_ids) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT value FROM jsonb_array_elements_text(
      p_delete_user_ids)));
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
  FROM unnest(v_current_users) id;
  IF v_actor=ANY(v_current_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  PERFORM public.impact_private_profile_users_v1(p_occasion,v_owners,'profile.companion_identity.imported');
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.users.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Profile CSV import','changedFields',jsonb_build_array('profiles','services','groups'))),
    CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,v_result,'{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.import_profiles_companion_internal_v1(bigint,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
