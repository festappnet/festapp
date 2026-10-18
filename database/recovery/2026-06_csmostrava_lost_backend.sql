-- =============================================================================
-- RECOVERY MIGRATION — csmostrava lost backend (versions 0.19.34 → 0.19.41)
-- Recovered from the LIVE Supabase project lwfpdjxsdmkfyrzqbrlk (Festapp A) on
-- 2026-06-27, because the source commits (deployed to Cloudflare via direct
-- `wrangler pages deploy`) were never pushed to git and are lost.
--
-- Covers backend for: GlobalSearch (search_occasion_content + search_doc),
-- EventFeedback (event_feedback table + RPCs), occasion Icons (icons table +
-- delete_icon), place_types. All object definitions are verbatim from the live
-- catalog (pg_get_functiondef / information_schema). Idempotent where practical.
-- =============================================================================

-- Extensions used by search (unaccent + pg_trgm live in the extensions schema)
CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- f_unaccent: lowercase + unaccent helper used by generated search_doc columns
-- ---------------------------------------------------------------------------
-- ===== f_unaccent =====
CREATE OR REPLACE FUNCTION public.f_unaccent(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT lower(extensions.unaccent('extensions.unaccent'::regdictionary, t));
$function$;
-- ---------------------------------------------------------------------------
-- Full-text-ish search columns: search_terms (editable keywords) + search_doc
-- (generated, trigram-indexed) on events / places / information / news.
-- ---------------------------------------------------------------------------
ALTER TABLE public.events      ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.places      ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.information ADD COLUMN IF NOT EXISTS search_terms text;
ALTER TABLE public.news        ADD COLUMN IF NOT EXISTS search_terms text;

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (f_unaccent((((COALESCE(title,''::text)||' '::text)||COALESCE(description,''::text))||' '::text)||COALESCE(search_terms,''::text))) STORED;
ALTER TABLE public.places ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (f_unaccent((((COALESCE(title,''::text)||' '::text)||COALESCE(description,''::text))||' '::text)||COALESCE(search_terms,''::text))) STORED;
ALTER TABLE public.information ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (f_unaccent((((COALESCE(title,''::text)||' '::text)||COALESCE(description,''::text))||' '::text)||COALESCE(search_terms,''::text))) STORED;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS search_doc text
  GENERATED ALWAYS AS (f_unaccent((COALESCE(message,''::text)||' '::text)||COALESCE(search_terms,''::text))) STORED;

CREATE INDEX IF NOT EXISTS events_search_doc_trgm_idx      ON public.events      USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS places_search_doc_trgm_idx      ON public.places      USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS information_search_doc_trgm_idx ON public.information USING gin (search_doc extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS news_search_doc_trgm_idx        ON public.news        USING gin (search_doc extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- icons table — ALREADY EXISTED (link/data/id/created_at/updated_at/organization).
-- This work turned it into a managed unit-owned library; legacy rows keep
-- unit IS NULL (read-only). Hence ALTER, not CREATE.
-- ---------------------------------------------------------------------------
ALTER TABLE public.icons ADD COLUMN IF NOT EXISTS unit       bigint REFERENCES public.units(id);
ALTER TABLE public.icons ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.icons ALTER COLUMN link DROP NOT NULL;
DO $$ BEGIN
  ALTER TABLE public.icons ADD CONSTRAINT icons_data_size_chk CHECK ((data IS NULL) OR (octet_length(data) <= 51200));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS icons_unit_idx       ON public.icons USING btree (unit);
CREATE INDEX IF NOT EXISTS icons_created_by_idx ON public.icons USING btree (created_by);

ALTER TABLE public.icons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable select for all" ON public.icons;
CREATE POLICY "Enable select for all" ON public.icons FOR SELECT USING (true);
DROP POLICY IF EXISTS "Enable insert for unit members" ON public.icons;
-- NOTE: must go through the SECURITY DEFINER helper — unit_users has RLS
-- enabled with no policies, so a plain EXISTS subquery here is always false
-- and every insert fails with 42501 (fixed on live 2026-07-07).
CREATE POLICY "Enable insert for unit members" ON public.icons FOR INSERT
  WITH CHECK ((created_by = auth.uid()) AND (unit IS NOT NULL) AND get_is_editor_on_unit(unit));
DROP POLICY IF EXISTS "Disable update" ON public.icons;
CREATE POLICY "Disable update" ON public.icons FOR UPDATE USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "Disable direct delete" ON public.icons;
CREATE POLICY "Disable direct delete" ON public.icons FOR DELETE USING (false);

-- ---------------------------------------------------------------------------
-- place_types table (occasion place categories, optional icon, one default)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.place_types (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  occasion    bigint NOT NULL REFERENCES public.occasions(id),
  code        text NOT NULL,
  title       text NOT NULL,
  icon        bigint REFERENCES public.icons(id),
  "order"     bigint,
  is_hidden   boolean NOT NULL DEFAULT false,
  is_default  boolean NOT NULL DEFAULT false,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT place_types_occasion_code_unique UNIQUE (occasion, code)
);
CREATE UNIQUE INDEX IF NOT EXISTS place_types_one_default_per_occasion ON public.place_types USING btree (occasion) WHERE (is_default = true);

ALTER TABLE public.place_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable read for all" ON public.place_types;
CREATE POLICY "Enable read for all" ON public.place_types FOR SELECT USING (true);
DROP POLICY IF EXISTS "Enable insert for editors" ON public.place_types;
CREATE POLICY "Enable insert for editors" ON public.place_types FOR INSERT WITH CHECK (get_is_editor_on_occasion(occasion));
DROP POLICY IF EXISTS "Enable update for editors" ON public.place_types;
CREATE POLICY "Enable update for editors" ON public.place_types FOR UPDATE USING (get_is_editor_on_occasion(occasion)) WITH CHECK (get_is_editor_on_occasion(occasion));
DROP POLICY IF EXISTS "Enable delete for editors" ON public.place_types;
CREATE POLICY "Enable delete for editors" ON public.place_types FOR DELETE USING (get_is_editor_on_occasion(occasion));

-- Optional: places.icon / path_groups.icon FKs to icons (referenced by delete_icon)
ALTER TABLE public.places      ADD COLUMN IF NOT EXISTS icon bigint REFERENCES public.icons(id);
ALTER TABLE public.path_groups ADD COLUMN IF NOT EXISTS icon bigint REFERENCES public.icons(id);

-- ---------------------------------------------------------------------------
-- event_feedback table (smiley ratings + optional note; user OR client_id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_feedback (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  event       bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  occasion    bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  "user"      uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
  client_id   uuid,
  rating      text NOT NULL,
  note        text,
  data        jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT event_feedback_identity_check   CHECK (("user" IS NOT NULL) OR (client_id IS NOT NULL)),
  CONSTRAINT event_feedback_rating_check     CHECK (rating = ANY (ARRAY['happy'::text,'neutral'::text,'sad'::text])),
  CONSTRAINT event_feedback_note_length_check CHECK (char_length(COALESCE(note,''::text)) <= 2000)
);
CREATE UNIQUE INDEX IF NOT EXISTS event_feedback_event_user_uidx   ON public.event_feedback USING btree (event, "user")     WHERE ("user" IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS event_feedback_event_client_uidx ON public.event_feedback USING btree (event, client_id) WHERE (("user" IS NULL) AND (client_id IS NOT NULL));
CREATE INDEX        IF NOT EXISTS event_feedback_event_idx         ON public.event_feedback USING btree (event);
ALTER TABLE public.event_feedback ENABLE ROW LEVEL SECURITY; -- access via SECURITY DEFINER RPCs only

DROP TRIGGER IF EXISTS handle_updated_at ON public.icons;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.icons          FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime('updated_at');
DROP TRIGGER IF EXISTS handle_updated_at ON public.place_types;
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.place_types    FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime('updated_at');

-- ---------------------------------------------------------------------------
-- RPC functions (verbatim from live catalog)
-- ---------------------------------------------------------------------------


-- ===== submit_event_feedback =====
CREATE OR REPLACE FUNCTION public.submit_event_feedback(p_event bigint, p_rating text, p_note text DEFAULT NULL::text, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_event public.events%ROWTYPE;
    v_user UUID := auth.uid();
    v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_is_limited BOOLEAN;
    v_is_editor BOOLEAN;
    v_feedback public.event_feedback%ROWTYPE;
BEGIN
    IF p_rating NOT IN ('happy', 'neutral', 'sad') THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Invalid rating');
    END IF;

    IF char_length(COALESCE(v_note, '')) > 2000 THEN
        RETURN jsonb_build_object('code', 413, 'message', 'Feedback text is too long');
    END IF;

    SELECT *
    INTO v_event
    FROM public.events
    WHERE id = p_event
      AND is_hidden = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_event_allowed(p_event) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Event is not available');
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_event.occasion) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback feature is not enabled for this occasion');
    END IF;

    IF COALESCE(v_event.data->>'feedback_enabled', 'false') <> 'true' THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback is not enabled for this event');
    END IF;

    v_is_editor := public.get_is_editor_view_on_occasion(v_event.occasion);

    IF now() < v_event.start_time AND NOT v_is_editor THEN
        RETURN jsonb_build_object('code', 409, 'message', 'Feedback is not open yet');
    END IF;

    v_is_limited := COALESCE(v_event.max_participants, 0) > 0;
    IF v_is_limited AND NOT v_is_editor THEN
        IF v_user IS NULL THEN
            RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required for feedback on this event');
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.event_users eu
            WHERE eu.event = p_event
              AND eu."user" = v_user
        ) THEN
            RETURN jsonb_build_object('code', 403, 'message', 'Only signed-in participants can rate this event');
        END IF;
    END IF;

    IF v_user IS NULL AND p_client_id IS NULL THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Client id is required for anonymous feedback');
    END IF;

    IF v_user IS NOT NULL THEN
        INSERT INTO public.event_feedback (event, occasion, "user", rating, note)
        VALUES (p_event, v_event.occasion, v_user, p_rating, v_note)
        ON CONFLICT (event, "user") WHERE "user" IS NOT NULL
        DO UPDATE SET
            rating = EXCLUDED.rating,
            note = EXCLUDED.note,
            updated_at = now()
        RETURNING * INTO v_feedback;
    ELSE
        INSERT INTO public.event_feedback (event, occasion, client_id, rating, note)
        VALUES (p_event, v_event.occasion, p_client_id, p_rating, v_note)
        ON CONFLICT (event, client_id) WHERE "user" IS NULL AND client_id IS NOT NULL
        DO UPDATE SET
            rating = EXCLUDED.rating,
            note = EXCLUDED.note,
            updated_at = now()
        RETURNING * INTO v_feedback;
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'id', v_feedback.id,
            'event', v_feedback.event,
            'rating', v_feedback.rating,
            'note', v_feedback.note,
            'created_at', v_feedback.created_at,
            'updated_at', v_feedback.updated_at
        )
    );
END;
$function$;


-- ===== get_event_feedback =====
CREATE OR REPLACE FUNCTION public.get_event_feedback(p_event bigint, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_event public.events%ROWTYPE;
    v_user UUID := auth.uid();
    v_feedback public.event_feedback%ROWTYPE;
BEGIN
    SELECT *
    INTO v_event
    FROM public.events
    WHERE id = p_event
      AND is_hidden = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_event_allowed(p_event) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Event is not available');
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_event.occasion) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback feature is not enabled for this occasion');
    END IF;

    IF v_user IS NOT NULL THEN
        SELECT *
        INTO v_feedback
        FROM public.event_feedback
        WHERE event = p_event
          AND "user" = v_user
        LIMIT 1;
    ELSIF p_client_id IS NOT NULL THEN
        SELECT *
        INTO v_feedback
        FROM public.event_feedback
        WHERE event = p_event
          AND "user" IS NULL
          AND client_id = p_client_id
        LIMIT 1;
    ELSE
        RETURN jsonb_build_object('code', 200, 'data', NULL);
    END IF;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 200, 'data', NULL);
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'id', v_feedback.id,
            'event', v_feedback.event,
            'rating', v_feedback.rating,
            'note', v_feedback.note,
            'created_at', v_feedback.created_at,
            'updated_at', v_feedback.updated_at
        )
    );
END;
$function$;



-- ===== get_event_feedback_for_edit =====
CREATE OR REPLACE FUNCTION public.get_event_feedback_for_edit(p_event bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_occasion BIGINT;
    v_summary JSONB;
    v_items JSONB;
BEGIN
    SELECT occasion
    INTO v_occasion
    FROM public.events
    WHERE id = p_event;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Event not found');
    END IF;

    IF NOT public.get_is_editor_view_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Insufficient permissions');
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback feature is not enabled for this occasion');
    END IF;

    SELECT jsonb_build_object(
        'total', COUNT(*),
        'happy', COUNT(*) FILTER (WHERE rating = 'happy'),
        'neutral', COUNT(*) FILTER (WHERE rating = 'neutral'),
        'sad', COUNT(*) FILTER (WHERE rating = 'sad')
    )
    INTO v_summary
    FROM public.event_feedback
    WHERE event = p_event;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''),
                'is_anonymous', f."user" IS NULL
            )
            ORDER BY f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.event_feedback f
    LEFT JOIN public.user_info ui ON ui.id = f."user"
    WHERE f.event = p_event;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'summary', v_summary,
            'items', v_items
        )
    );
END;
$function$;



-- ===== get_event_feedback_export_for_edit =====
CREATE OR REPLACE FUNCTION public.get_event_feedback_export_for_edit(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_items JSONB;
BEGIN
    IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Insufficient permissions');
    END IF;

    IF NOT public.get_is_event_feedback_enabled_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Feedback feature is not enabled for this occasion');
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'event_id', e.id,
                'event_title', e.title,
                'event_start_time', e.start_time,
                'event_end_time', e.end_time,
                'feedback_id', f.id,
                'created_at', f.created_at,
                'updated_at', f.updated_at,
                'rating', f.rating,
                'note', f.note,
                'user_name', NULLIF(btrim(CONCAT_WS(' ', ui.name, ui.surname)), ''),
                'is_anonymous', f."user" IS NULL
            )
            ORDER BY e.start_time ASC, e.title ASC, f.updated_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_items
    FROM public.event_feedback f
    JOIN public.events e ON e.id = f.event
    LEFT JOIN public.user_info ui ON ui.id = f."user"
    WHERE f.occasion = p_occasion;

    RETURN jsonb_build_object('code', 200, 'data', v_items);
END;
$function$;



-- ===== delete_event_feedback =====
CREATE OR REPLACE FUNCTION public.delete_event_feedback(p_event bigint, p_client_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_deleted INTEGER := 0;
BEGIN
    IF v_user IS NULL AND p_client_id IS NULL THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Client id is required for anonymous feedback');
    END IF;

    IF v_user IS NOT NULL THEN
        DELETE FROM public.event_feedback
        WHERE event = p_event
          AND "user" = v_user;
    ELSE
        DELETE FROM public.event_feedback
        WHERE event = p_event
          AND "user" IS NULL
          AND client_id = p_client_id;
    END IF;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('deleted', v_deleted)
    );
END;
$function$;



-- ===== get_is_event_feedback_enabled_on_occasion =====
CREATE OR REPLACE FUNCTION public.get_is_event_feedback_enabled_on_occasion(p_occasion bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(o.features, '[]'::jsonb)) feature
    WHERE o.id = p_occasion
      AND feature->>'code' = 'event_feedback'
      AND LOWER(COALESCE(feature->>'is_enabled', 'false')) = 'true'
  );
$function$;



-- ===== search_occasion_content =====
-- SUPERSEDED: the live/current definition lives in
-- database/functions/others/search_occasion_content.sql (it additionally
-- excludes counseling slots and searches speakers). It is NOT duplicated here
-- so that re-running this recovery file can never regress the newer function.
-- Apply that file after this one when bootstrapping a fresh database.



-- ===== delete_icon =====
CREATE OR REPLACE FUNCTION public.delete_icon(p_icon_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_icon record;
    v_has_access BOOLEAN;
    v_places_n INT;
    v_paths_n INT;
    v_types_n INT;
BEGIN
    SELECT id, unit
      INTO v_icon
      FROM public.icons
      WHERE id = p_icon_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    IF v_user IS NULL THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Legacy icons (no unit) are read-only.
    IF v_icon.unit IS NULL THEN
        RETURN jsonb_build_object('code', 403, 'reason', 'legacy_no_unit');
    END IF;

    -- Permission: any member of the unit may delete (no role check).
    SELECT EXISTS (
        SELECT 1
          FROM public.unit_users
         WHERE unit = v_icon.unit
           AND "user" = v_user
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Reference check across the three FK consumers.
    SELECT COUNT(*) INTO v_places_n
      FROM public.places
     WHERE icon = p_icon_id;

    SELECT COUNT(*) INTO v_paths_n
      FROM public.path_groups
     WHERE icon = p_icon_id;

    SELECT COUNT(*) INTO v_types_n
      FROM public.place_types
     WHERE icon = p_icon_id;

    IF v_places_n + v_paths_n + v_types_n > 0 THEN
        RETURN jsonb_build_object(
            'code', 409,
            'refs', jsonb_build_object(
                'places', v_places_n,
                'path_groups', v_paths_n,
                'place_types', v_types_n
            )
        );
    END IF;

    DELETE FROM public.icons WHERE id = p_icon_id;
    RETURN jsonb_build_object('code', 200);
END;
$function$;
