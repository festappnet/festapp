CREATE OR REPLACE FUNCTION public.get_speakers_editor_bundle_v1(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_speakers jsonb; v_topics jsonb;
BEGIN
  IF NOT public.can_read_speakers_editor(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(q.value ORDER BY q.sort_order,q.sort_title),'[]'::jsonb)
    INTO v_speakers FROM (
    SELECT s."order" sort_order,s.title sort_title,
      to_jsonb(s)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0),
        'topics',COALESCE((SELECT jsonb_agg(l.topic ORDER BY l.topic)
          FROM public.speaker_topic_links l WHERE l.speaker=s.id),'[]'::jsonb),
        'events',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',e.id,'title',e.title,'start_time',e.start_time,
          'end_time',e.end_time,'max_participants',e.max_participants,
          'occupied',(SELECT count(*) FROM public.event_users eu WHERE eu.event=e.id),
          'is_counseling_slot',COALESCE((e.data->>'is_counseling_slot')::boolean,false),
          'aggregate_version',COALESCE(ev.version,0)) ORDER BY e.start_time,e.id)
          FROM public.event_speakers es JOIN public.events e ON e.id=es.event
          LEFT JOIN public.client_aggregate_versions ev ON ev.aggregate_type='event'
            AND ev.scope_type='occasion' AND ev.scope_id=p_occasion
            AND ev.aggregate_id=e.id::text WHERE es.speaker=s.id),'[]'::jsonb)
      ) value
    FROM public.speakers s LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='speaker' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=s.id::text
    WHERE s.occasion=p_occasion
  ) q;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)||jsonb_build_object(
      'aggregate_version',COALESCE(v.version,0)) ORDER BY t."order",t.title,t.id),
      '[]'::jsonb) INTO v_topics
  FROM public.speaker_topics t LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=t.id::text
  WHERE t.occasion=p_occasion;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'speakers',v_speakers,'speaker_topics',v_topics));
END; $function$
;
REVOKE ALL ON FUNCTION public.get_speakers_editor_bundle_v1(p_occasion bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_speakers_editor_bundle_v1(p_occasion bigint) TO authenticated;
