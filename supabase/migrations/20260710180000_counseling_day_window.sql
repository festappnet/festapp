-- Migration: add an optional [p_from, p_to) day window to the counseling
-- availability + overview RPCs, so the rozcestník on a given day shows only that
-- day's counselors/slots/counts. Backward compatible: the old 2-arg / 1-arg
-- calls still work (window defaults to NULL = all future). The signature grows,
-- so the old versions are dropped first to avoid overload ambiguity.

DROP FUNCTION IF EXISTS public.get_counseling_availability(bigint, bigint);
DROP FUNCTION IF EXISTS public.get_counseling_topics_overview(bigint);

CREATE OR REPLACE FUNCTION get_counseling_availability(
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
    IF NOT public.get_is_counseling_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

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

CREATE OR REPLACE FUNCTION get_counseling_topics_overview(
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
