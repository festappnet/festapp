-- Counselors competent in a topic and their future slots. Optional [p_from,
-- p_to) window scopes the slots to the parent rozcestník event's day (the
-- client passes that event's day bounds in UTC); when both are NULL all future
-- slots are returned. Counselors with no slot in the window are omitted.
CREATE OR REPLACE FUNCTION public.get_counseling_availability(
    p_occasion BIGINT,
    p_topic    BIGINT,
    p_from     TIMESTAMPTZ DEFAULT NULL,
    p_to       TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_uid        UUID := auth.uid();
    v_counselors JSONB;
BEGIN
    -- Feature gate.
    IF NOT public.get_is_counseling_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    -- The chosen topic must belong to the occasion and be visible.
    -- NOTE (decision R3): the topic is only a filter — it is never stored.
    IF NOT EXISTS (
        SELECT 1 FROM public.speaker_topics t
        WHERE t.id = p_topic AND t.occasion = p_occasion AND t.is_hidden = FALSE
    ) THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id',       s.id,
            'title',    s.title,
            'subtitle', s.subtitle,
            'image',    s.image,
            'slots', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id',               e.id,
                    'start_time',       e.start_time,
                    'end_time',         e.end_time,
                    'place',            e.place,
                    'place_title',      (SELECT pl.title FROM public.places pl WHERE pl.id = e.place),
                    'max_participants', e.max_participants,
                    'occupied',         (SELECT count(*) FROM public.event_users eu WHERE eu.event = e.id),
                    'isSignedIn',       (v_uid IS NOT NULL AND EXISTS (
                                            SELECT 1 FROM public.event_users eu2
                                            WHERE eu2.event = e.id AND eu2."user" = v_uid))
                ) ORDER BY e.start_time)
                FROM public.event_speakers es
                JOIN public.events e ON e.id = es.event
                WHERE es.speaker = s.id
                  AND e.occasion = p_occasion
                  AND (e.data->>'is_counseling_slot')::boolean IS TRUE
                  AND e.end_time > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                  AND (p_from IS NULL OR e.start_time >= p_from)
                  AND (p_to   IS NULL OR e.start_time <  p_to)
            ), '[]'::jsonb)
        ) ORDER BY s."order", s.title
    ), '[]'::jsonb)
    INTO v_counselors
    FROM public.speakers s
    JOIN public.speaker_topic_links stl ON stl.speaker = s.id AND stl.topic = p_topic
    WHERE s.occasion = p_occasion AND s.is_hidden = FALSE
      -- Only counselors who actually have a slot in the window.
      AND EXISTS (
          SELECT 1
          FROM public.event_speakers es
          JOIN public.events e ON e.id = es.event
          WHERE es.speaker = s.id
            AND e.occasion = p_occasion
            AND (e.data->>'is_counseling_slot')::boolean IS TRUE
            AND e.end_time > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
            AND (p_from IS NULL OR e.start_time >= p_from)
            AND (p_to   IS NULL OR e.start_time <  p_to)
      );

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('counselors', v_counselors)
    );
END;
$$;
