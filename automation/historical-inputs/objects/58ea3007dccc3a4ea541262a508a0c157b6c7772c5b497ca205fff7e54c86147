-- =============================================================================
-- Make speakers/counselors searchable in GlobalSearch.
--   1. search_terms (editable keywords) + generated search_doc column on
--      public.speakers (mirrors events/places; needs public.f_unaccent) + trgm index.
--   2. search_occasion_content gains a 'speaker' branch gated on the "speakers"
--      feature (parent_id = the speaker's first non-hidden, non-slot event).
-- Idempotent. Apply after 20260709130000_speakers_counseling.sql.
-- =============================================================================

ALTER TABLE public.speakers ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.speakers ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (public.f_unaccent(
    (((COALESCE(title, '') || ' ') || COALESCE(subtitle, '')) || ' '
      || COALESCE(description, '')) || ' ' || COALESCE(search_terms, ''))) STORED;
CREATE INDEX IF NOT EXISTS speakers_search_doc_trgm_idx
  ON public.speakers USING gin (search_doc extensions.gin_trgm_ops);

-- search_occasion_content — GlobalSearch backend across events / places /
-- information / news / speakers for an occasion.
--
-- Speakers/counselors are searchable by name, role (subtitle) and bio, gated on
-- the "speakers" feature (like songs/games); their search_doc column + trigram
-- index are added by migration 20260710120000_speakers_searchable.sql.
--
-- This file is now the repo home of the function; it supersedes the verbatim
-- copy in database/recovery/2026-06_csmostrava_lost_backend.sql (which was
-- recovered from the live catalog). The only functional change versus that copy
-- is in the events branch: counseling slots (data.is_counseling_slot = true)
-- are excluded from search results. Slots are ordinary, non-hidden events
-- (decision R8), so without this filter the hundreds of generated mini-events
-- would flood GlobalSearch (plan 2.1). The check is NULL-safe:
-- `... IS NOT TRUE` keeps normal events where the marker is absent/NULL.
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

    -- Speakers / counselors, gated on the "speakers" feature (like song/game).
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
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_features) f
        WHERE f->>'code' = 'speakers' AND (f->>'is_enabled')::boolean = TRUE
      )

    ORDER BY rank DESC
    LIMIT v_effective_limit;
END;
$function$;
