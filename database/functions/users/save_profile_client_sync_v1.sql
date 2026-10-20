-- Canonical profile command: receipt, version and companion effects have one owner.
CREATE OR REPLACE FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_before jsonb; v_after jsonb; v_result jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object'
    OR octet_length(p_profile::text)>262144
    OR (p_profile->>'occasion')::bigint IS DISTINCT FROM p_occasion
    OR (p_profile->>'user')::uuid IS DISTINCT FROM p_user THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion user profile'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version,
    'profile',p_profile)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.user_info WHERE id=p_user FOR UPDATE;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'rejected',404,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_before:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_before)); END IF;
  v_result:=public.save_occasion_user_for_edit_internal_v1(p_profile);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),jsonb_build_object(
        'version',v_version,'profile',v_before,'message',v_result->>'message'));
  END IF;
  v_after:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF v_after IS NOT DISTINCT FROM v_before THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'profile',v_after)); END IF;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text
    RETURNING version INTO v_version;
  IF v_actor=p_user THEN v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',p_user,
    'payload',public.get_private_profile_payload_v1(p_occasion,p_user))); END IF;
  -- Companion-owner invalidation is part of the mutation, never a replay follow-up.
  PERFORM public.impact_companion_owners_v1(p_occasion,ARRAY[p_user],'profile.companion_identity.changed');
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.save','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','update',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('profile','rights','services'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
      'userId',p_user)),'[]',jsonb_build_object('version',v_version,'profile',v_after),
    '{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_profile_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint, p_profile jsonb) TO authenticated;
