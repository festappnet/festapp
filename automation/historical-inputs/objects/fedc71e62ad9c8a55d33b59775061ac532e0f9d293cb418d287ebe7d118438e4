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
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    LEFT JOIN (
        -- Subquery to calculate order statistics for each form.
        SELECT
            (data->>'form')::uuid AS form_key,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE state = 'storno') AS storno,
            COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
            COUNT(*) FILTER (WHERE state = 'ordered') AS ordered
        FROM eshop.orders
        WHERE data->>'form' IS NOT NULL
        GROUP BY form_key
    ) AS order_stats ON f.key = order_stats.form_key
    WHERE f.occasion IN (
        -- Subquery to get all occasion IDs the user has editor view access to.
        -- This includes direct occasion permissions.
        SELECT ou.occasion
        FROM public.occasion_users ou
        WHERE ou.user = user_id AND ou.is_editor_view = TRUE

        UNION

        -- And permissions inherited from unit-level roles.
        SELECT o_unit.id
        FROM public.occasions o_unit
        JOIN public.unit_users uu ON o_unit.unit = uu.unit
        WHERE uu.user = user_id AND uu.is_editor_view = TRUE
    );

    -- Step 2: If no forms are found, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 3: Return the aggregated data.
    RETURN forms_data;
END;
$$;