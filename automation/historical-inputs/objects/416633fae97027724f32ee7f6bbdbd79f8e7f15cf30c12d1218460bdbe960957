CREATE OR REPLACE FUNCTION public.get_speakers_for_edit(p_occasion BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_speakers JSONB;
    v_topics   JSONB;
BEGIN
    -- Admin read: all speakers and topics, including hidden.
    IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Speakers (all columns) + competence topic ids + linked events with
    -- occupancy. Ordered by "order", title.
    SELECT COALESCE(jsonb_agg(q.sp ORDER BY q.sp_order, q.sp_title), '[]'::jsonb)
    INTO v_speakers
    FROM (
        SELECT
            to_jsonb(s) || jsonb_build_object(
                'topics', COALESCE((
                    SELECT jsonb_agg(stl.topic ORDER BY stl.topic)
                    FROM public.speaker_topic_links stl
                    WHERE stl.speaker = s.id
                ), '[]'::jsonb),
                'events', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'id',                 e.id,
                        'title',              e.title,
                        'start_time',         e.start_time,
                        'end_time',           e.end_time,
                        'max_participants',   e.max_participants,
                        'occupied',           (SELECT count(*) FROM public.event_users eu WHERE eu.event = e.id),
                        'is_counseling_slot', COALESCE((e.data->>'is_counseling_slot')::boolean, FALSE)
                    ) ORDER BY e.start_time)
                    FROM public.event_speakers es
                    JOIN public.events e ON e.id = es.event
                    WHERE es.speaker = s.id
                ), '[]'::jsonb)
            ) AS sp,
            s."order" AS sp_order,
            s.title   AS sp_title
        FROM public.speakers s
        WHERE s.occasion = p_occasion
    ) q;

    -- Full topic catalog, including hidden.
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t."order", t.title), '[]'::jsonb)
    INTO v_topics
    FROM public.speaker_topics t
    WHERE t.occasion = p_occasion;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'speakers',       v_speakers,
            'speaker_topics', v_topics
        )
    );
END;
$$;
