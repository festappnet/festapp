-- =============================================================================
-- Migration: drop the counseling area "code" (key) entirely.
--
-- Counseling areas (public.speaker_topics) must have NO code/key — the only
-- identifier is the hidden primary key id. This removes the optional `code`
-- column and its unique index, and recreates the two functions that referenced
-- the column. Idempotent (IF EXISTS guards; CREATE OR REPLACE).
--
--   * get_speakers          — no longer emits topic `code`.
--   * update_speaker_topic  — no longer reads/writes `code`; no (occasion, code)
--                             uniqueness to guard, so the exception handler is
--                             dropped.
--   * get_speakers_for_edit — unchanged (serializes topics via to_jsonb(t), which
--                             simply stops including code once the column is gone).
-- =============================================================================

DROP INDEX IF EXISTS public.speaker_topics_occasion_code_uidx;
ALTER TABLE public.speaker_topics DROP COLUMN IF EXISTS code;

-- ===== get_speakers (topic catalog without code) =====
CREATE OR REPLACE FUNCTION get_speakers(
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

    -- (b) visible area catalog (no code/key — only the hidden id)
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

-- ===== update_speaker_topic (no code) =====
CREATE OR REPLACE FUNCTION update_speaker_topic(p_occasion BIGINT, p_topic JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_topic_id BIGINT;
    v_row      public.speaker_topics%ROWTYPE;
    v_title    TEXT;
BEGIN
    -- Only editors of the occasion may write the area catalog.
    IF NOT public.get_is_editor_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    IF p_topic ? 'id' AND (p_topic->>'id') IS NOT NULL THEN
        -- UPDATE — guarded by occasion to prevent cross-occasion edits.
        v_topic_id := (p_topic->>'id')::BIGINT;

        UPDATE public.speaker_topics t SET
            title     = COALESCE(p_topic->>'title', t.title),
            "order"   = CASE WHEN p_topic ? 'order'     THEN (p_topic->>'order')::BIGINT        ELSE t."order"   END,
            is_hidden = CASE WHEN p_topic ? 'is_hidden' THEN (p_topic->>'is_hidden')::BOOLEAN   ELSE t.is_hidden END
        WHERE t.id = v_topic_id AND t.occasion = p_occasion
        RETURNING t.* INTO v_row;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('code', 404);
        END IF;
    ELSE
        -- INSERT — a non-empty title is required. Areas have no code/key; the
        -- only identifier is the hidden primary key id.
        v_title := p_topic->>'title';
        IF v_title IS NULL OR btrim(v_title) = '' THEN
            RETURN jsonb_build_object('code', 400);
        END IF;

        INSERT INTO public.speaker_topics (occasion, title, "order", is_hidden)
        VALUES (
            p_occasion,
            v_title,
            COALESCE((p_topic->>'order')::BIGINT, 0),
            COALESCE((p_topic->>'is_hidden')::BOOLEAN, FALSE)
        )
        RETURNING * INTO v_row;
    END IF;

    RETURN jsonb_build_object('code', 200, 'data', to_jsonb(v_row));
END;
$$;
