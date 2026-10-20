CREATE OR REPLACE FUNCTION public.create_occasion_user_client_sync_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_user uuid; v_begin jsonb; v_hash text;
  v_version bigint;
  v_result jsonb; v_profile jsonb; v_entity jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object'
    OR octet_length(p_profile::text)>262144
    OR (p_profile->>'occasion')::bigint IS DISTINCT FROM p_occasion
    OR p_profile->>'user' IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid new occasion user profile'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'profile',p_profile)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.create',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  BEGIN
  v_result:=public.update_user_internal_v1(jsonb_build_object(
    'occasion',p_occasion,'user',NULL,'data',p_profile->'data'));
  IF COALESCE((v_result->>'code')::integer,500) NOT IN (200,201) THEN
    RAISE SQLSTATE 'P0P01' USING MESSAGE='profile creation rejected'; END IF;
  v_user:=(v_result->>'user')::uuid;
  v_result:=public.add_user_to_occasion_internal_v1(p_occasion,v_user);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE SQLSTATE 'P0P01' USING MESSAGE='profile creation rejected'; END IF;
  v_profile:=p_profile||jsonb_build_object('user',v_user);
  v_result:=public.save_occasion_user_for_edit_internal_v1(v_profile);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE SQLSTATE 'P0P01' USING MESSAGE='profile creation rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0P01' THEN
    -- All domain writes, including an account/membership created earlier, rolled back.
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      coalesce((v_result->>'code')::integer,400),jsonb_build_object('version',0,'profile',NULL,'message',v_result->>'message'));
  END;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,v_user::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp() RETURNING version INTO v_version;
  SELECT public.get_occasion_user_command_data_v1(p_occasion,v_user) INTO v_entity;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.create','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',v_user,'operation','insert',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('profile','rights','services'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
    'userId',v_user)),'[]',jsonb_build_object('version',v_version,'userId',v_user,
      'profile',v_entity));
END; $function$
;
REVOKE ALL ON FUNCTION public.create_occasion_user_client_sync_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_occasion_user_client_sync_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb) TO authenticated;
