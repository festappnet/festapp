-- Qualify speaker ids expanded from the command payload. An unqualified `id`
-- conflicts with columns visible to PL/pgSQL and rejects every event-speaker
-- save, including the empty array sent when an event has no speakers.
CREATE OR REPLACE FUNCTION public.save_event_speakers_client_sync_v1(
  p_occasion bigint,p_event bigint,p_command_id uuid,p_expected_version bigint,
  p_speaker_ids bigint[]
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_current bigint[]; v_requested bigint[];
  v_publishable boolean; v_event_hidden boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT COALESCE(array_agg(requested_speaker.speaker_id
      ORDER BY requested_speaker.speaker_id),'{}'::bigint[])
    INTO v_requested
    FROM unnest(COALESCE(p_speaker_ids,'{}'::bigint[]))
      AS requested_speaker(speaker_id);
  IF cardinality(v_requested)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_requested)))
    OR cardinality(v_requested)>1000 OR EXISTS (
      SELECT 1
      FROM unnest(v_requested) AS requested_speaker(speaker_id)
      LEFT JOIN public.speakers s
        ON s.id=requested_speaker.speaker_id AND s.occasion=p_occasion
      WHERE s.id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid event speakers'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventId',p_event,'expectedVersion',p_expected_version,
    'speakerIds',to_jsonb(v_requested))::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.event_speakers.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT e.is_hidden,NOT o.is_hidden INTO v_event_hidden,v_publishable
    FROM public.events e JOIN public.occasions o ON o.id=e.occasion
    WHERE e.id=p_event AND e.occasion=p_occasion FOR UPDATE OF e;
  IF v_event_hidden IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',404,jsonb_build_object('version',0,'eventId',p_event,
      'speakerIds','[]'::jsonb)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('event','occasion',p_occasion,p_event::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='event' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_event::text FOR UPDATE;
  SELECT COALESCE(array_agg(es.speaker ORDER BY es.speaker),'{}') INTO v_current
    FROM public.event_speakers es WHERE es.event=p_event;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'eventId',p_event,
        'speakerIds',to_jsonb(v_current))); END IF;
  IF v_current=v_requested THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
      'eventId',p_event,'speakerIds',to_jsonb(v_current))); END IF;
  DELETE FROM public.event_speakers WHERE event=p_event;
  INSERT INTO public.event_speakers(event,speaker)
    SELECT p_event,requested_speaker.speaker_id
    FROM unnest(v_requested) AS requested_speaker(speaker_id);
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='event'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_event::text
    RETURNING version INTO v_version;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'program.event_speakers.save','program',jsonb_build_array(jsonb_build_object(
      'entityType','event_speakers','entityId',p_event,'operation','update',
      'safeLabel','Event speakers','changedFields',jsonb_build_array('speakerIds'))),
    CASE WHEN v_publishable AND NOT v_event_hidden THEN ARRAY['program_catalog']
      ELSE '{}'::text[] END,'[]','[]',jsonb_build_object('version',v_version,
      'eventId',p_event,'speakerIds',to_jsonb(v_requested)));
END; $$;

REVOKE ALL ON FUNCTION public.save_event_speakers_client_sync_v1(bigint,bigint,uuid,bigint,bigint[])
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_event_speakers_client_sync_v1(bigint,bigint,uuid,bigint,bigint[])
  TO authenticated;
