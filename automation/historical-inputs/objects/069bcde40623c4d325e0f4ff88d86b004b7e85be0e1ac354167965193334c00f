CREATE OR REPLACE FUNCTION public.get_speakers(
    p_occasion            BIGINT,
    p_include_description BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    speakersData      JSONB;
    topicsData        JSONB;
    topicLinksData    JSONB;
    eventSpeakersData JSONB;
BEGIN
    -- (a) visible speakers, description only on request (payload size)
    SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id',          s.id,
        'title',       s.title,
        'subtitle',    s.subtitle,
        'description', CASE WHEN p_include_description THEN s.description ELSE NULL END,
        'image',       s.image,
        'order',       s."order",
        'updated_at',  s.updated_at
    )) ORDER BY s."order", s.title)
    INTO speakersData
    FROM public.speakers s
    WHERE s.occasion = p_occasion
      AND s.is_hidden = FALSE;

    -- (b) visible topic catalog
    SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id',    t.id,
        'title', t.title,
        'order', t."order"
    )) ORDER BY t."order", t.title)
    INTO topicsData
    FROM public.speaker_topics t
    WHERE t.occasion = p_occasion
      AND t.is_hidden = FALSE;

    -- (c) competence links restricted to visible speakers and topics
    SELECT jsonb_agg(jsonb_build_object(
        'speaker', stl.speaker,
        'topic',   stl.topic
    ))
    INTO topicLinksData
    FROM public.speaker_topic_links stl
    JOIN public.speakers s ON s.id = stl.speaker
    JOIN public.speaker_topics t ON t.id = stl.topic
    WHERE s.occasion = p_occasion AND s.is_hidden = FALSE
      AND t.occasion = p_occasion AND t.is_hidden = FALSE;

    -- (d) event links restricted to visible speakers and non-hidden events
    SELECT jsonb_agg(jsonb_build_object(
        'event',   es.event,
        'speaker', es.speaker
    ))
    INTO eventSpeakersData
    FROM public.event_speakers es
    JOIN public.speakers s ON s.id = es.speaker
    JOIN public.events e ON e.id = es.event
    WHERE s.occasion = p_occasion AND s.is_hidden = FALSE
      AND e.occasion = p_occasion AND e.is_hidden = FALSE;

    RETURN jsonb_build_object(
      'code', 200,
      'data', jsonb_build_object(
        'speakers',            COALESCE(speakersData,      '[]'::jsonb),
        'speaker_topics',      COALESCE(topicsData,        '[]'::jsonb),
        'speaker_topic_links', COALESCE(topicLinksData,    '[]'::jsonb),
        'event_speakers',      COALESCE(eventSpeakersData, '[]'::jsonb)
      )
    );
END;
$$;
