-- Qualify topic ids expanded from the aggregate payload. An unqualified `id`
-- conflicts with columns visible to PL/pgSQL and rejects every speaker save
-- that carries at least one topic.
CREATE OR REPLACE FUNCTION public.save_speaker_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_speaker jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_requested jsonb; v_entity jsonb;
  v_topic_ids bigint[]; v_old_hidden boolean; v_new_hidden boolean;
  v_publishable boolean; v_content_impact boolean; v_program_impact boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  IF v_publishable IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='occasion not found'; END IF;
  IF p_speaker IS NULL OR jsonb_typeof(p_speaker)<>'object'
    OR octet_length(p_speaker::text)>786432
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_speaker) key WHERE key NOT IN
      ('id','title','subtitle','description','image','order','is_hidden','data','topics'))
    OR NOT (p_speaker ?& ARRAY['title','order','is_hidden','data','topics'])
    OR jsonb_typeof(p_speaker->'topics')<>'array'
    OR jsonb_array_length(p_speaker->'topics')>1000
    OR length(btrim(COALESCE(p_speaker->>'title',''))) NOT BETWEEN 1 AND 200
    OR octet_length(COALESCE(p_speaker->>'description',''))>524288
    OR octet_length(COALESCE((p_speaker->'data')::text,''))>131072 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid speaker aggregate';
  END IF;
  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_topic_ids FROM jsonb_array_elements_text(p_speaker->'topics');
  IF cardinality(v_topic_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_topic_ids)))
    OR EXISTS (
      SELECT 1
      FROM unnest(v_topic_ids) AS requested_topic(topic_id)
      LEFT JOIN public.speaker_topics t
        ON t.id=requested_topic.topic_id AND t.occasion=p_occasion
      WHERE t.id IS NULL
    ) THEN
    RAISE invalid_parameter_value USING MESSAGE='speaker contains invalid topics';
  END IF;
  v_id:=(p_speaker->>'id')::bigint;
  v_new_hidden:=(p_speaker->>'is_hidden')::boolean;
  v_requested:=jsonb_build_object('id',v_id,'title',p_speaker->>'title',
    'subtitle',p_speaker->>'subtitle','description',p_speaker->>'description',
    'image',p_speaker->>'image','order',(p_speaker->>'order')::bigint,
    'is_hidden',v_new_hidden,'data',p_speaker->'data','topics',to_jsonb(v_topic_ids));
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'speaker',p_speaker)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.speakers s WHERE s.id=v_id AND s.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',404,jsonb_build_object('version',0,'speaker',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='speaker' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    SELECT jsonb_build_object('id',s.id,'title',s.title,'subtitle',s.subtitle,
      'description',s.description,'image',s.image,'order',s."order",
      'is_hidden',s.is_hidden,'data',s.data,'topics',COALESCE((SELECT jsonb_agg(
        l.topic ORDER BY l.topic) FROM public.speaker_topic_links l
        WHERE l.speaker=s.id),'[]'::jsonb)),s.is_hidden
      INTO v_current,v_old_hidden FROM public.speakers s WHERE s.id=v_id;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'speaker',
          public.get_speaker_command_data_v1(v_id)||jsonb_build_object(
            'aggregate_version',v_version))); END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new speaker must not have expected version';
  END IF;
  IF v_current IS NOT DISTINCT FROM v_requested THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'speaker',
        public.get_speaker_command_data_v1(v_id)||jsonb_build_object(
          'aggregate_version',v_version)));
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.speakers(occasion,title,subtitle,description,image,"order",is_hidden,data)
    VALUES (p_occasion,p_speaker->>'title',p_speaker->>'subtitle',
      p_speaker->>'description',p_speaker->>'image',(p_speaker->>'order')::bigint,
      v_new_hidden,p_speaker->'data') RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.speakers SET title=p_speaker->>'title',subtitle=p_speaker->>'subtitle',
      description=p_speaker->>'description',image=p_speaker->>'image',
      "order"=(p_speaker->>'order')::bigint,is_hidden=v_new_hidden,data=p_speaker->'data'
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='speaker'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.speaker_topic_links WHERE speaker=v_id;
  INSERT INTO public.speaker_topic_links(speaker,topic)
    SELECT v_id,requested_topic.topic_id
    FROM unnest(v_topic_ids) AS requested_topic(topic_id);
  v_entity:=public.get_speaker_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  v_program_impact:=v_old_hidden IS DISTINCT FROM v_new_hidden AND EXISTS (
    SELECT 1 FROM public.event_speakers es JOIN public.events e ON e.id=es.event
    WHERE es.speaker=v_id AND NOT e.is_hidden);
  v_content_impact:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_speaker->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable THEN CASE WHEN v_content_impact
      THEN ARRAY['content_catalog'] ELSE '{}'::text[] END||CASE WHEN v_program_impact
      THEN ARRAY['program_catalog'] ELSE '{}'::text[] END ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'speaker',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;
