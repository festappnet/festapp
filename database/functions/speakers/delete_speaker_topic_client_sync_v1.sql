CREATE OR REPLACE FUNCTION public.delete_speaker_topic_client_sync_v1(p_occasion bigint, p_topic_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_speakers(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'topicId',p_topic_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker_topic.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(t) INTO v_entity FROM public.speaker_topics t
    WHERE t.id=p_topic_id AND t.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'topic',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('speaker_topic','occasion',p_occasion,p_topic_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='speaker_topic' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_topic_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'topic',v_entity)); END IF;
  DELETE FROM public.speaker_topics WHERE id=p_topic_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='speaker_topic'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_topic_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker_topic.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker_topic','entityId',p_topic_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable AND NOT (v_entity->>'is_hidden')::boolean
      THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'topic',NULL));
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_speaker_topic_client_sync_v1(p_occasion bigint, p_topic_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker_topic_client_sync_v1(p_occasion bigint, p_topic_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated,service_role;
