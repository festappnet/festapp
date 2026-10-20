-- Migration: clean plain-text snippets for GlobalSearch.
--
-- search_occasion_content previously truncated raw HTML descriptions with
-- LEFT(description, 120), which cut mid-tag (leaving a stray "<"), cut
-- mid-word, and — because markup ate into the 120-char budget — returned
-- wildly variable amounts of real text (sometimes almost none). This adds a
-- reusable f_html_snippet() helper (strip tags -> collapse whitespace ->
-- word-boundary truncate -> ellipsis only when actually cut) and switches
-- every snippet column in the search RPC to use it.
--
-- Additive/idempotent: two CREATE OR REPLACE FUNCTION statements, no data or
-- signature changes.

CREATE OR REPLACE FUNCTION public.f_html_snippet(p_html text, p_limit integer DEFAULT 160)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 PARALLEL SAFE
AS $function$
    WITH cleaned AS (
        SELECT btrim(
                 regexp_replace(
                   regexp_replace(
                     regexp_replace(coalesce(p_html, ''), '<[^>]*>', ' ', 'g'),
                     '<[^>]*$', '', 'g'
                   ),
                   '\s+', ' ', 'g'
                 )
               ) AS t
    )
    SELECT CASE
             WHEN length(t) <= p_limit THEN t
             ELSE btrim(regexp_replace(LEFT(t, p_limit), '\s\S*$', '')) || '…'
           END
    FROM cleaned;
$function$;

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
           public.f_html_snippet(e.description) AS snippet,
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
           public.f_html_snippet(p.description),
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
      public.f_html_snippet(i.description),
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
           public.f_html_snippet(n.message),
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
           public.f_html_snippet(coalesce(NULLIF(s.subtitle, ''), s.description)),
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
