CREATE OR REPLACE FUNCTION public.create_counseling_slots_internal_v1(
    p_speaker       BIGINT,
    p_start         TIMESTAMPTZ,
    p_end           TIMESTAMPTZ,
    p_slot_minutes  INT,
    p_place         BIGINT DEFAULT NULL,
    p_capacity      INT DEFAULT 1,
    p_title         TEXT DEFAULT NULL,
    p_break_minutes INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion      BIGINT;
    v_speaker_title TEXT;
    v_type          TEXT;
    v_title         TEXT;
    v_slot_start    TIMESTAMPTZ;
    v_slot_end      TIMESTAMPTZ;
    v_event_id      BIGINT;
    v_ids           BIGINT[] := ARRAY[]::BIGINT[];
    v_count         INT := 0;
BEGIN
    SELECT occasion, title INTO v_occasion, v_speaker_title
    FROM public.speakers
    WHERE id = p_speaker;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    IF NOT public.get_is_editor_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Parameter validation.
    IF p_slot_minutes IS NULL OR p_slot_minutes < 5
       OR p_start IS NULL OR p_end IS NULL OR p_start >= p_end
       OR p_capacity IS NULL OR p_capacity < 1
       OR p_break_minutes IS NULL OR p_break_minutes < 0 THEN
        RETURN jsonb_build_object('code', 400);
    END IF;

    IF p_place IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.places
            WHERE id = p_place AND occasion = v_occasion
        ) THEN
            RETURN jsonb_build_object('code', 400);
        END IF;
    END IF;

    -- Event type comes from the "counseling" feature config (default 'counseling').
    SELECT COALESCE(elem->>'counseling_event_type', 'counseling')
    INTO v_type
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(o.features, '[]'::jsonb)) elem
    WHERE o.id = v_occasion AND elem->>'code' = 'counseling'
    LIMIT 1;

    IF v_type IS NULL THEN
        v_type := 'counseling';
    END IF;

    v_title := COALESCE(p_title, v_speaker_title);

    -- Generate slots: last slot must fully fit within [p_start, p_end].
    v_slot_start := p_start;
    WHILE v_slot_start + make_interval(mins => p_slot_minutes) <= p_end LOOP
        v_slot_end := v_slot_start + make_interval(mins => p_slot_minutes);

        INSERT INTO public.events (occasion, title, start_time, end_time, max_participants, place, type, is_hidden, data)
        VALUES (
            v_occasion,
            v_title,
            v_slot_start,
            v_slot_end,
            p_capacity,
            p_place,
            v_type,
            FALSE,
            jsonb_build_object('is_counseling_slot', true)
        )
        RETURNING id INTO v_event_id;

        INSERT INTO public.event_speakers (event, speaker) VALUES (v_event_id, p_speaker);

        v_ids := array_append(v_ids, v_event_id);
        v_count := v_count + 1;

        v_slot_start := v_slot_start + make_interval(mins => p_slot_minutes + p_break_minutes);
    END LOOP;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'created',   v_count,
            'event_ids', to_jsonb(v_ids)
        )
    );
END;
$$;



REVOKE ALL ON FUNCTION public.create_counseling_slots_internal_v1(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer) FROM PUBLIC,anon,authenticated;
