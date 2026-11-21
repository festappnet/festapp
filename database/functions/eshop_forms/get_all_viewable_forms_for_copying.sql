CREATE OR REPLACE FUNCTION public.get_all_viewable_forms_for_copying()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    forms_data JSONB;
    user_id UUID := auth.uid();
BEGIN
    -- Step 1: Aggregate forms into a JSONB array based on the user's combined permissions.
    -- The user can see forms from occasions where they are a direct editor,
    -- or from any occasion within a unit where they are a unit editor.
    WITH visible_occasions AS MATERIALIZED (
        SELECT ou.occasion
        FROM public.occasion_users ou
        WHERE ou.user = user_id AND ou.is_editor_view = TRUE
        UNION
        SELECT o.id
        FROM public.occasions o
        JOIN public.unit_users uu ON o.unit=uu.unit
        WHERE uu.user = user_id AND uu.is_editor_view = TRUE
    ), visible_forms AS MATERIALIZED (
        SELECT f.* FROM public.forms f JOIN visible_occasions v ON v.occasion=f.occasion
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', jsonb_build_object(
                'id', o.id,
                'title', o.title,
                'link', o.link,
                'start_time', o.start_time,
                'end_time', o.end_time
            ),
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'stats', jsonb_build_object(
                'total', COALESCE(order_stats.total, 0),
                'storno', COALESCE(order_stats.storno, 0),
                'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
                'ordered', COALESCE(order_stats.ordered, 0)
            )
        ) ORDER BY o.start_time DESC, f.created_at DESC
    )
    INTO forms_data
    FROM visible_forms f
    JOIN public.occasions o ON f.occasion=o.id
    LEFT JOIN public.get_order_catalog_counts_internal(
        ARRAY(SELECT occasion FROM visible_occasions),ARRAY(SELECT id FROM visible_forms)
    ) AS order_stats ON f.id=order_stats.form_id;

    -- Step 2: If no forms are found, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 3: Return the aggregated data.
    RETURN forms_data;
END;
$$;
