-- get_counseling_topics_overview — per-topic counseling availability for the
-- rozcestník. For each visible area it returns how many future counseling slots
-- exist and how many are still free (occupied < capacity) across the visible
-- counselors competent in that area. The optional [p_from, p_to) window scopes
-- the counts to the parent event's day (same bounds the client passes to
-- get_counseling_availability). The client uses free_future_slots to grey out
-- empty areas and to show the free count. Gated on the counseling feature.
CREATE OR REPLACE FUNCTION public.get_counseling_topics_overview(
    p_occasion BIGINT,
    p_from     TIMESTAMPTZ DEFAULT NULL,
    p_to       TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_topics JSONB;
BEGIN
    IF NOT public.get_is_counseling_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id',                 t.id,
            'title',              t.title,
            'order',              t."order",
            'total_future_slots', COALESCE(fs.total, 0),
            'free_future_slots',  COALESCE(fs.free, 0)
        ) ORDER BY t."order", t.title
    ), '[]'::jsonb)
    INTO v_topics
    FROM public.speaker_topics t
    LEFT JOIN LATERAL (
        SELECT
            count(*) AS total,
            count(*) FILTER (
                WHERE e.max_participants IS NULL
                   OR (SELECT count(*) FROM public.event_users eu WHERE eu.event = e.id) < e.max_participants
            ) AS free
        FROM public.events e
        WHERE e.occasion = p_occasion
          AND (e.data->>'is_counseling_slot')::boolean IS TRUE
          AND e.end_time > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
          AND (p_from IS NULL OR e.start_time >= p_from)
          AND (p_to   IS NULL OR e.start_time <  p_to)
          AND EXISTS (
              SELECT 1
              FROM public.event_speakers es
              JOIN public.speakers s ON s.id = es.speaker
              JOIN public.speaker_topic_links stl ON stl.speaker = s.id
              WHERE es.event = e.id
                AND s.occasion = p_occasion
                AND s.is_hidden = FALSE
                AND stl.topic = t.id
          )
    ) fs ON TRUE
    WHERE t.occasion = p_occasion
      AND t.is_hidden = FALSE;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('topics', v_topics)
    );
END;
$$;
