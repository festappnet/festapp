-- Lightweight event catalog (id/title/times) for admin pickers,
-- e.g. the exclusivity editor. Includes hidden events; editor-only.
CREATE OR REPLACE FUNCTION public.get_events_catalog(p_occasion BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_events JSONB;
BEGIN
    IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',         e.id,
        'title',      e.title,
        'start_time', e.start_time,
        'end_time',   e.end_time
    ) ORDER BY e.start_time, e.id), '[]'::jsonb)
    INTO v_events
    FROM public.events e
    WHERE e.occasion = p_occasion;

    RETURN jsonb_build_object('code', 200, 'data', v_events);
END;
$$;
