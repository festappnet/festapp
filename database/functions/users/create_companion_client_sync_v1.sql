CREATE OR REPLACE FUNCTION public.create_companion_client_sync_v1(p_occasion bigint, p_name text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_organization bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before uuid[]; v_companion uuid; v_replacements jsonb;
BEGIN
  IF v_actor IS NULL OR nullif(btrim(p_name),'') IS NULL
    OR octet_length(p_name)>512 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion'; END IF;
  SELECT o.organization INTO v_organization FROM public.occasions o
    JOIN public.occasion_users ou ON ou.occasion=o.id AND ou."user"=v_actor
    WHERE o.id=p_occasion;
  IF v_organization IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='occasion participant required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'name',p_name)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.create',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  SELECT COALESCE(array_agg(uc.companion),'{}'::uuid[]) INTO v_before
    FROM public.user_companions uc WHERE uc.occasion=p_occasion AND uc."user"=v_actor;
  v_result:=public.create_companion_in_organization_internal_v1(
    v_organization,p_occasion,v_actor,p_name);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer=403 THEN 403 ELSE 400 END,
      jsonb_build_object('companion',NULL,'domainCode',v_result->'code'));
  END IF;
  SELECT uc.companion INTO v_companion FROM public.user_companions uc
    WHERE uc.occasion=p_occasion AND uc."user"=v_actor AND NOT uc.companion=ANY(v_before)
    ORDER BY uc.companion LIMIT 1;
  IF v_companion IS NULL THEN
    RAISE EXCEPTION 'companion handler did not create a companion'; END IF;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.create','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',v_companion,'operation','insert',
      'safeLabel','Companion','changedFields',jsonb_build_array('name'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
      'userId',v_actor)),'[]',jsonb_build_object('companion',jsonb_build_object(
        'id',v_companion,'name',p_name,'event_ids','[]'::jsonb)),
    '{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.create_companion_client_sync_v1(p_occasion bigint, p_name text, p_command_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_companion_client_sync_v1(p_occasion bigint, p_name text, p_command_id uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid) TO authenticated,service_role;
