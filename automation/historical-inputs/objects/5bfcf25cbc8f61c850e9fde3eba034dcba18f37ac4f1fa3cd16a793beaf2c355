-- =============================================================================
-- Migration: Speakers become core, Counseling becomes its own feature.
--
-- Refactor plan docs/plans/2026-07-10_speakers_core_counseling_feature_plan.md.
--
--   * The `speakers` feature code is retired. Speakers (lecturers/counselors)
--     are now a core concept: always manageable, attachable to any event, and
--     always searchable — no feature gate.
--   * A new `counseling` feature gates the counseling flow only: areas catalog,
--     slot generator, availability matcher, the entry rozcestník, and the
--     booking window/limit in sign_user_to_event.
--
-- What this migration does (idempotent — safe to re-run):
--   (1) Transform occasions.features: every `speakers` element becomes a
--       `counseling` element. is_enabled = old is_enabled AND counseling_enabled;
--       counseling_event_type / registration_start_time / max_active_bookings
--       carried over. The `speakers` element is removed. Occasions without a
--       `speakers` element are untouched; a second run is a no-op (no `speakers`
--       element left to match).
--   (2) DROP the old gate function get_is_speakers_enabled_on_occasion and CREATE
--       the new get_is_counseling_enabled_on_occasion (reads code `counseling`).
--   (3) CREATE OR REPLACE the functions whose feature reads changed:
--       get_counseling_availability, create_counseling_slots,
--       sign_user_to_event, search_occasion_content.
--   (4) CREATE delete_event: editor-guarded event deletion that unbinds
--       sign-ups first (counseling slots are ordinary events with attendees).
--
-- The Flutter client that reads the new feature is deployed together with this
-- migration (plan section 5 / decision R8).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- (1) Idempotent transform of occasions.features (decision R2).
--     The CASE expression below is the canonical transform; the DB test
--     database/tests/speakers_test.sql block 9 runs the same statement scoped
--     to a single occasion.
-- ---------------------------------------------------------------------------
UPDATE public.occasions o
SET features = (
    SELECT COALESCE(jsonb_agg(
        CASE
            WHEN elem->>'code' = 'speakers' THEN
                jsonb_strip_nulls(jsonb_build_object(
                    'code', 'counseling',
                    'is_enabled', (
                        COALESCE((elem->>'is_enabled')::boolean, false)
                        AND COALESCE((elem->>'counseling_enabled')::boolean, false)
                    ),
                    'counseling_event_type',    elem->'counseling_event_type',
                    'registration_start_time',  elem->'registration_start_time',
                    'max_active_bookings',      elem->'max_active_bookings'
                ))
            ELSE elem
        END
    ), '[]'::jsonb)
    FROM jsonb_array_elements(o.features) elem
)
WHERE o.features IS NOT NULL
  AND jsonb_typeof(o.features) = 'array'
  AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(o.features) e2
      WHERE e2->>'code' = 'speakers'
  );

-- ---------------------------------------------------------------------------
-- (2) Gate function: new counseling gate, drop the old speakers gate.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_is_counseling_enabled_on_occasion(p_occasion BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(o.features, '[]'::jsonb)) feature
    WHERE o.id = p_occasion
      AND feature->>'code' = 'counseling'
      AND LOWER(COALESCE(feature->>'is_enabled', 'false')) = 'true'
  );
$$;

-- ===== get_counseling_availability (gate → counseling) =====
CREATE OR REPLACE FUNCTION get_counseling_availability(p_occasion BIGINT, p_topic BIGINT)
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
            ), '[]'::jsonb)
        ) ORDER BY s."order", s.title
    ), '[]'::jsonb)
    INTO v_counselors
    FROM public.speakers s
    JOIN public.speaker_topic_links stl ON stl.speaker = s.id AND stl.topic = p_topic
    WHERE s.occasion = p_occasion AND s.is_hidden = FALSE;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('counselors', v_counselors)
    );
END;
$$;

-- ===== create_counseling_slots (event type from counseling feature) =====
CREATE OR REPLACE FUNCTION create_counseling_slots(
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

-- ===== sign_user_to_event (counseling branch reads the counseling feature) =====
create or replace function sign_user_to_event (ev bigint, usr uuid) returns jsonb
 language plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 as $$
declare
  i_max_participants integer;
  current_participants integer;
  event_group_count integer;
  event_group integer;
  exclusive_event_count integer;
  already_in_count integer;
  current_men_participants integer;
  current_women_participants integer;
  b_split_for_men_women boolean;
  is_current_user_male boolean;

  registration_start timestamp;
  event_start_time timestamp;
  event_end_time timestamp;
  workshops_feature jsonb;
  e RECORD;

  v_occasion bigint;
  v_is_counseling boolean;
  counseling_feature jsonb;
  v_limit integer;
  v_active integer;

begin

  -- Check if the user already exists on the occasion
  IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN

      -- Check if the occasion is open
      IF (SELECT is_open FROM occasions WHERE id = (SELECT occasion FROM events WHERE id = ev)) = TRUE THEN

          -- Add the user to the occasion
          PERFORM add_user_to_occasion((SELECT occasion FROM events WHERE id = ev), usr);

          -- Recheck if the user now exists on the occasion
          IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
              -- If user still doesn't exist, return a 403 response
              RETURN json_build_object('code', 403, 'message', 'Failed to add user to occasion');
          END IF;
      ELSE
          -- If the occasion is not open, return a 403 response
          RETURN json_build_object('code', 403, 'message', 'Occasion is not open');
      END IF;
  END IF;

  IF auth.uid() <> usr THEN
      IF NOT EXISTS (
        SELECT 1 FROM user_companions WHERE "user" = auth.uid() AND companion = usr) THEN
          IF (SELECT get_is_editor_on_occasion((SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
            RETURN json_build_object('code', 403);
          END IF;
      END IF;
  END IF;

  -- Resolve the occasion and detect whether this event is a counseling slot.
  SELECT occasion, (data->>'is_counseling_slot')::boolean IS TRUE
    INTO v_occasion, v_is_counseling
  FROM events
  WHERE id = ev;

  IF v_is_counseling THEN
    -- Counseling slots use their own registration window from the "counseling"
    -- feature; the workshops gate (104/108) does not apply (decision R1).
    SELECT elem
      INTO counseling_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = v_occasion
      AND elem->>'code' = 'counseling'
    LIMIT 1;

    -- (a) Feature must be present and enabled, else registration is closed.
    IF counseling_feature IS NULL
       OR (counseling_feature->>'is_enabled')::boolean IS NOT TRUE THEN
      RETURN json_build_object('code', 108);
    END IF;

    registration_start := (counseling_feature->>'registration_start_time')::timestamp;
    IF registration_start IS NOT NULL THEN
      IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
        RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
      END IF;
    END IF;

    -- (b) Limit of the user's future counseling bookings (0 = unlimited).
    v_limit := COALESCE((counseling_feature->>'max_active_bookings')::int, 1);
    IF v_limit > 0 THEN
      SELECT count(*)
        INTO v_active
      FROM event_users eu
      JOIN events e2 ON e2.id = eu.event
      WHERE eu."user" = usr
        AND e2.occasion = v_occasion
        AND (e2.data->>'is_counseling_slot')::boolean IS TRUE
        AND e2.end_time > CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
      IF v_active >= v_limit THEN
        RETURN json_build_object('code', 109);
      END IF;
    END IF;
  ELSE
    -- Check registration start time from occasions.features for the "workshops" feature
    SELECT elem
    INTO workshops_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = (SELECT occasion FROM events WHERE id = ev)
      AND elem->>'code' = 'workshops'
    LIMIT 1;

    IF workshops_feature IS NOT NULL THEN
      -- If the workshops feature is not enabled, do not allow sign in
      IF (workshops_feature->>'is_enabled')::boolean IS NOT TRUE THEN
        RETURN json_build_object('code', 108, 'message', 'Registration for workshops is not enabled');
      END IF;
      -- If start_time is provided, enforce registration start time
      registration_start := (workshops_feature->>'start_time')::timestamp;
      IF registration_start IS NOT NULL THEN
        IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
          RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
        END IF;
      END IF;
    END IF;
    -- If the workshops feature is not present or its start_time is null, sign in is enabled
  END IF;

  SELECT start_time, end_time INTO event_start_time, event_end_time
  FROM events
  WHERE id = ev;

  IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' > event_end_time THEN
    RETURN json_build_object('code', 100);
  END IF;

  SELECT count(*) FROM event_users eu WHERE eu.event = ev AND eu."user" = usr INTO already_in_count;
  IF already_in_count > 0 THEN
    RETURN json_build_object('code', 103);
  END IF;

  SELECT count(*) FROM exclusive_events WHERE event = ev INTO event_group_count;
  IF event_group_count > 0 THEN
    SELECT "group" FROM exclusive_events WHERE event = ev INTO event_group;
    SELECT count(*) FROM exclusive_events ee JOIN event_users eu ON ee.event = eu.event
      WHERE ee."group" = event_group AND eu."user" = usr INTO exclusive_event_count;
    IF exclusive_event_count > 0 THEN
      RETURN json_build_object('code', 102);
    END IF;
  END IF;

  -- Check if the event already has the maximum number of participants
  SELECT max_participants FROM events WHERE id = ev INTO i_max_participants;
  SELECT split_for_men_women FROM events WHERE id = ev INTO b_split_for_men_women;

  IF b_split_for_men_women THEN
    SELECT exists (SELECT sex FROM user_info WHERE id = usr AND sex = 'male') INTO is_current_user_male;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex = 'male' INTO current_men_participants;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex <> 'male' INTO current_women_participants;
    IF is_current_user_male AND current_men_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 105);
    ELSIF NOT is_current_user_male AND current_women_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 106);
    END IF;
  END IF;

  -- Loop through user_events to check for scheduling conflicts
  FOR e IN
      SELECT events.id, events.start_time, events.end_time
      FROM events
      JOIN event_users ON events.id = event_users.event
      WHERE event_users."user" = usr
  LOOP
      IF ((e.start_time < event_end_time AND e.start_time > event_start_time) OR
          (e.end_time < event_end_time AND e.end_time > event_start_time) OR
          (e.start_time = event_start_time) OR
          (e.end_time = event_end_time)) THEN
          RETURN json_build_object('code', 107);
      END IF;
  END LOOP;

  SELECT count(*) FROM event_users WHERE event = ev INTO current_participants;
  IF current_participants >= i_max_participants THEN
    RETURN json_build_object('code', 101);
  ELSE
    INSERT INTO event_users (event, "user") VALUES (ev, usr);
    RETURN json_build_object('code', 200);
  END IF;
END;
$$;

-- ===== search_occasion_content (speakers de-gated: always searchable) =====
CREATE OR REPLACE FUNCTION public.search_occasion_content(p_occasion bigint, p_query text, p_limit integer DEFAULT 50)
 RETURNS TABLE(entity_type text, entity_id bigint, title text, snippet text, rank real, start_time timestamp with time zone, parent_id bigint, extra jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_features        JSONB;
    v_norm_query      TEXT;
    v_effective_limit INT;
BEGIN
    SELECT o.features INTO v_features
    FROM public.occasions o
    WHERE o.id = p_occasion;

    IF v_features IS NULL THEN
        v_features := '[]'::jsonb;
    END IF;

    v_norm_query := public.f_unaccent(coalesce(p_query, ''));

    IF v_norm_query IS NULL OR length(trim(v_norm_query)) = 0 THEN
        RETURN;
    END IF;

    v_effective_limit := LEAST(GREATEST(coalesce(p_limit, 50), 1), 200);

    RETURN QUERY
    SELECT 'event'::TEXT AS entity_type, e.id::BIGINT AS entity_id, e.title,
           LEFT(coalesce(e.description, ''), 120) AS snippet,
           GREATEST(extensions.similarity(e.search_doc, v_norm_query), 0.0)::REAL AS rank,
           e.start_time, e.place AS parent_id,
           jsonb_strip_nulls(jsonb_build_object(
             'end_time', e.end_time,
             'max_participants', e.max_participants,
             'place_title', p.title
           )) AS extra
    FROM public.events e
    LEFT JOIN public.places p ON p.id = e.place
    WHERE e.occasion = p_occasion
      AND e.is_hidden = FALSE
      AND (e.data->>'is_counseling_slot')::boolean IS NOT TRUE
      AND e.search_doc ILIKE '%' || v_norm_query || '%'

    UNION ALL

    SELECT 'place'::TEXT, p.id::BIGINT, p.title,
           LEFT(coalesce(p.description, ''), 120),
           GREATEST(extensions.similarity(p.search_doc, v_norm_query), 0.0)::REAL,
           NULL::TIMESTAMPTZ, NULL::BIGINT, NULL::JSONB
    FROM public.places p
    WHERE p.occasion = p_occasion
      AND p.is_hidden = FALSE
      AND p.search_doc ILIKE '%' || v_norm_query || '%'

    UNION ALL

    SELECT
      CASE
        WHEN i.type = 'song' THEN 'song'
        WHEN i.type = 'game' THEN 'game'
        ELSE 'info'
      END::TEXT,
      i.id::BIGINT, i.title,
      LEFT(coalesce(i.description, ''), 120),
      GREATEST(extensions.similarity(i.search_doc, v_norm_query), 0.0)::REAL,
      NULL::TIMESTAMPTZ, NULL::BIGINT, NULL::JSONB
    FROM public.information i
    WHERE i.occasion = p_occasion
      AND i.is_hidden = FALSE
      AND i.search_doc ILIKE '%' || v_norm_query || '%'
      AND (
        (i.type = 'song' AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_features) f
          WHERE f->>'code' = 'songbook' AND (f->>'is_enabled')::boolean = TRUE
        ))
        OR
        (i.type = 'game' AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_features) f
          WHERE f->>'code' = 'game' AND (f->>'is_enabled')::boolean = TRUE
        ))
        OR
        (i.type IS NULL OR i.type NOT IN ('song', 'game'))
      )

    UNION ALL

    SELECT 'news'::TEXT, n.id::BIGINT, NULL::TEXT,
           LEFT(coalesce(n.message, ''), 120),
           GREATEST(extensions.similarity(n.search_doc, v_norm_query), 0.0)::REAL,
           n.created_at, NULL::BIGINT, NULL::JSONB
    FROM public.news n
    WHERE n.occasion = p_occasion
      AND n.search_doc ILIKE '%' || v_norm_query || '%'

    UNION ALL

    -- Speakers / counselors are core: always searchable, only is_hidden filters.
    -- parent_id carries the speaker's first non-hidden, non-slot event so the
    -- client can open a page where the speaker's medallion is shown.
    SELECT 'speaker'::TEXT, s.id::BIGINT, s.title,
           LEFT(coalesce(NULLIF(s.subtitle, ''), s.description, ''), 120),
           GREATEST(extensions.similarity(s.search_doc, v_norm_query), 0.0)::REAL,
           NULL::TIMESTAMPTZ,
           (SELECT es.event
              FROM public.event_speakers es
              JOIN public.events e2 ON e2.id = es.event
             WHERE es.speaker = s.id
               AND e2.is_hidden = FALSE
               AND (e2.data->>'is_counseling_slot')::boolean IS NOT TRUE
             ORDER BY e2.start_time
             LIMIT 1)::BIGINT AS parent_id,
           NULL::JSONB
    FROM public.speakers s
    WHERE s.occasion = p_occasion
      AND s.is_hidden = FALSE
      AND s.search_doc ILIKE '%' || v_norm_query || '%'

    ORDER BY rank DESC
    LIMIT v_effective_limit;
END;
$function$;

-- ===== delete_event (unbinds sign-ups before deleting) =====
CREATE OR REPLACE FUNCTION delete_event(p_event BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion BIGINT;
BEGIN
    SELECT occasion INTO v_occasion
    FROM public.events
    WHERE id = p_event;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    IF NOT public.get_is_editor_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Unbind child rows without ON DELETE CASCADE, then delete the event.
    DELETE FROM public.event_users       WHERE event = p_event;
    DELETE FROM public.event_users_saved WHERE event = p_event;
    DELETE FROM public.exclusive_events  WHERE event = p_event;
    DELETE FROM public.event_roles       WHERE event = p_event;
    DELETE FROM public.event_groups      WHERE event_parent = p_event OR event_child = p_event;

    DELETE FROM public.events WHERE id = p_event;

    RETURN jsonb_build_object('code', 200);
END;
$$;

-- ---------------------------------------------------------------------------
-- (5) Drop the retired gate function (nothing references it anymore).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_is_speakers_enabled_on_occasion(bigint);
