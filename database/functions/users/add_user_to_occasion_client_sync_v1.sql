CREATE OR REPLACE FUNCTION public.add_user_to_occasion_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_before jsonb;
  v_after jsonb; v_result jsonb; v_version bigint; v_replacements jsonb:='[]';
BEGIN
  IF v_actor IS NULL OR p_user IS NULL OR NOT (
    v_actor=p_user OR public.can_manage_occasion_participants(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion membership permission required';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'userId',p_user)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'profile.membership.ensure',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(ou) INTO v_before FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=p_user FOR UPDATE;
  v_result:=public.add_user_to_occasion_internal_v1(p_occasion,p_user);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),v_result); END IF;
  SELECT to_jsonb(ou) INTO v_after FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=p_user;
  SELECT COALESCE(v.version,0) INTO v_version FROM (SELECT 1) seed
    LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=p_user::text;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'userId',p_user)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp() RETURNING version INTO v_version;
  IF v_actor=p_user THEN v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',p_user,
    'payload',public.get_private_profile_payload_v1(p_occasion,p_user))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.membership.ensure','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation',
      CASE WHEN v_before IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','Occasion membership','changedFields',jsonb_build_array(
        'membership','rights'))),'{}',jsonb_build_array(jsonb_build_object(
          'component','private_profile','userId',p_user)),'[]',
    jsonb_build_object('version',v_version,'userId',p_user),
    '{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_client_sync_v1(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_client_sync_v1(bigint,uuid,uuid) TO authenticated,service_role;
