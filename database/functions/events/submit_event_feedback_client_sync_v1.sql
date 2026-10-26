CREATE OR REPLACE FUNCTION public.submit_event_feedback_client_sync_v1(p_occasion bigint, p_event bigint, p_rating text, p_note text, p_client_id uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_client uuid; v_begin jsonb; v_hash text;
  v_result jsonb; v_before public.event_feedback%ROWTYPE;
  v_after public.event_feedback%ROWTYPE; v_private_impacts jsonb:='[]'::jsonb;
  v_replacements jsonb:='[]'::jsonb; v_operation text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.events e
    WHERE e.id=p_event AND e.occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='feedback event outside occasion'; END IF;
  v_client:=CASE WHEN v_actor IS NULL THEN p_client_id ELSE NULL END;
  IF v_actor IS NULL AND v_client IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='anonymous client id required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'event',p_event,'rating',p_rating,'note',p_note,
    'clientId',v_client)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'feedback.submit',p_occasion,v_client,v_hash);
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,'feedback.submit',
      p_occasion,v_actor,v_hash);
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=p_event FOR UPDATE;
  IF v_actor IS NULL THEN
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user" IS NULL AND f.client_id=v_client
      FOR UPDATE;
  ELSE
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user"=v_actor FOR UPDATE;
  END IF;
  v_result:=public.submit_event_feedback_internal_v1(
    p_event,p_rating,p_note,v_client);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,400) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,
      jsonb_build_object('message',v_result->>'message'));
  END IF;
  SELECT * INTO STRICT v_after FROM public.event_feedback f
    WHERE f.id=(v_result#>>'{data,id}')::bigint;
  IF v_before.id IS NOT NULL AND v_before.rating IS NOT DISTINCT FROM v_after.rating
      AND v_before.note IS NOT DISTINCT FROM v_after.note
      AND v_before.data IS NOT DISTINCT FROM v_after.data THEN
    UPDATE public.event_feedback SET updated_at=v_before.updated_at
      WHERE id=v_after.id;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('feedback',public.get_event_feedback_command_data_v1(v_after.id)));
  END IF;
  v_operation:=CASE WHEN v_before.id IS NULL THEN 'insert' ELSE 'update' END;
  IF v_actor IS NOT NULL AND EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    v_private_impacts:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor));
    v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor,
      'payload',public.get_private_feedback_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'feedback.submit','feedback',jsonb_build_array(jsonb_build_object(
      'entityType','event_feedback','entityId',v_after.id,'operation',v_operation,
      'safeLabel','Event feedback','changedFields',jsonb_build_array('rating','note'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'feedback',public.get_event_feedback_command_data_v1(v_after.id)),
    '{}','[]',CASE WHEN v_actor IS NULL THEN 'unknown' ELSE 'user' END,NULL,
    v_replacements);
END; $function$
;

REVOKE ALL ON FUNCTION public.submit_event_feedback_client_sync_v1(p_occasion bigint, p_event bigint, p_rating text, p_note text, p_client_id uuid, p_command_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback_client_sync_v1(p_occasion bigint, p_event bigint, p_rating text, p_note text, p_client_id uuid, p_command_id uuid) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid) TO anon,authenticated,service_role;
