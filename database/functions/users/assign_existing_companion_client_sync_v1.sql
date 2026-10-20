CREATE OR REPLACE FUNCTION public.assign_existing_companion_client_sync_v1(p_occasion bigint, p_owner uuid, p_companion uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_policy jsonb; v_begin jsonb; v_hash text;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  IF NOT public.get_can_assign_companions_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  IF NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
      OR NOT COALESCE((v_policy->>'allow_admin_assign')::boolean,false) THEN
    RAISE insufficient_privilege USING MESSAGE='admin companion assignment disabled';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'owner',p_owner,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.assign',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.check_companion_relation_invariants_v1(p_occasion,p_owner,p_companion);
  IF EXISTS (SELECT 1 FROM public.user_companions uc WHERE uc.occasion=p_occasion
      AND uc."user"=p_owner AND uc.companion=p_companion) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('owner',p_owner,'companion',p_companion));
  END IF;
  INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
  VALUES(p_occasion,p_owner,p_companion,'admin_assigned',v_actor);
  RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,
    'profile.companion.assign',jsonb_build_array(jsonb_build_object(
      'entityType','companion_assignment','entityId',p_companion,'operation','insert',
      'safeLabel','Companion assignment','changedFields',jsonb_build_array('owner'))),
    ARRAY[p_owner],'{}','[]',jsonb_build_object('owner',p_owner,'companion',p_companion));
END $function$
;
REVOKE ALL ON FUNCTION public.assign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.assign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid) TO authenticated;
