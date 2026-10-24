CREATE OR REPLACE FUNCTION public.delete_speaker_client_sync_v1(p_occasion bigint, p_speaker_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_event_ids bigint[];
  v_entity jsonb; v_publishable boolean; v_hidden boolean; v_has_public_events boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'speakerId',p_speaker_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_event_ids:=public.lock_speaker_event_dependencies_internal_v1(p_speaker_id);
  SELECT public.get_speaker_command_data_v1(s.id),s.is_hidden INTO v_entity,v_hidden
    FROM public.speakers s WHERE s.id=p_speaker_id AND s.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'speaker',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('speaker','occasion',p_occasion,p_speaker_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='speaker' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_speaker_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'speaker',v_entity)); END IF;
  SELECT EXISTS (SELECT 1 FROM public.event_speakers es JOIN public.events e
    ON e.id=es.event WHERE es.speaker=p_speaker_id AND NOT e.is_hidden)
    INTO v_has_public_events;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'event','occasion',p_occasion,id::text,1 FROM unnest(v_event_ids) id
  ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
  SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
  DELETE FROM public.speakers WHERE id=p_speaker_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='speaker'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_speaker_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker','entityId',p_speaker_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable THEN CASE WHEN NOT v_hidden THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END||CASE WHEN NOT v_hidden
      AND v_has_public_events THEN ARRAY['program_catalog'] ELSE '{}'::text[] END
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'speaker',NULL));
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_speaker_client_sync_v1(p_occasion bigint, p_speaker_id bigint, p_command_id uuid, p_expected_version bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker_client_sync_v1(p_occasion bigint, p_speaker_id bigint, p_command_id uuid, p_expected_version bigint) TO authenticated;
