CREATE OR REPLACE FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(p_occasion bigint, p_muted boolean, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_current boolean; v_impacts jsonb; v_replacements jsonb;
BEGIN
  IF v_actor IS NULL THEN RAISE insufficient_privilege USING MESSAGE='sign in required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'muted',COALESCE(p_muted,false))::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.notifications.set',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE((ou.data->>'cleaning_notifications_off')::boolean,false)
    INTO v_current FROM public.occasion_users ou WHERE ou.occasion=p_occasion
      AND ou."user"=v_actor FOR UPDATE;
  v_result:=public.set_cleaning_notifications_muted_internal_v1(p_occasion,p_muted);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_current IS NOT DISTINCT FROM COALESCE(p_muted,false) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      v_result->'data'); END IF;
  v_impacts:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor));
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'cleaning.notifications.set','profile',jsonb_build_array(jsonb_build_object(
      'entityType','cleaning_preference','entityId',v_actor,'operation','update',
      'safeLabel','Cleaning notifications','changedFields',jsonb_build_array('muted'))),
    '{}',v_impacts,'[]',v_result->'data','{}','[]','user',NULL,v_replacements);
END; $function$;
REVOKE ALL ON FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(bigint,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(bigint,boolean,uuid) TO authenticated;
