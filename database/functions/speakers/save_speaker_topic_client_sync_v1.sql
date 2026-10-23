CREATE OR REPLACE FUNCTION public.save_speaker_topic_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_topic jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_publishable boolean;
  v_old_hidden boolean; v_new_hidden boolean; v_content_impact boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_speakers(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  IF p_topic IS NULL OR jsonb_typeof(p_topic)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_topic) key WHERE key NOT IN
      ('id','title','order','is_hidden')) OR NOT (p_topic ?& ARRAY['title','order','is_hidden'])
    OR length(btrim(COALESCE(p_topic->>'title',''))) NOT BETWEEN 1 AND 200 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid speaker topic'; END IF;
  v_id:=(p_topic->>'id')::bigint; v_new_hidden:=(p_topic->>'is_hidden')::boolean;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'topic',p_topic)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker_topic.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(t),t.is_hidden INTO v_current,v_old_hidden FROM public.speaker_topics t
      WHERE t.id=v_id AND t.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',404,jsonb_build_object('version',0,'topic',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker_topic','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='speaker_topic' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'topic',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    IF jsonb_build_object('id',v_id,'occasion',p_occasion,'title',v_current->>'title',
      'order',(v_current->>'order')::bigint,'is_hidden',(v_current->>'is_hidden')::boolean)
      = jsonb_build_object('id',v_id,'occasion',p_occasion,'title',p_topic->>'title',
      'order',(p_topic->>'order')::bigint,'is_hidden',v_new_hidden) THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
        jsonb_build_object('version',v_version,'topic',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    UPDATE public.speaker_topics SET title=p_topic->>'title',
      "order"=(p_topic->>'order')::bigint,is_hidden=v_new_hidden,
      updated_at=clock_timestamp() WHERE id=v_id
      RETURNING to_jsonb(speaker_topics.*) INTO v_entity;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='speaker_topic'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new topic must not have expected version'; END IF;
    INSERT INTO public.speaker_topics(occasion,title,"order",is_hidden)
    VALUES (p_occasion,p_topic->>'title',(p_topic->>'order')::bigint,v_new_hidden)
    RETURNING id,to_jsonb(speaker_topics.*) INTO v_id,v_entity;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker_topic','occasion',p_occasion,v_id::text,v_version);
  END IF;
  v_entity:=v_entity||jsonb_build_object('aggregate_version',v_version);
  v_content_impact:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker_topic.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker_topic','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_topic->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable AND v_content_impact THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'topic',v_entity));
END; $function$
;
REVOKE ALL ON FUNCTION public.save_speaker_topic_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_topic jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_speaker_topic_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_topic jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated,service_role;
