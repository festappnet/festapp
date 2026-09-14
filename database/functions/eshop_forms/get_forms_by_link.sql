CREATE OR REPLACE FUNCTION public.get_forms_by_link(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE link = occasion_link
      AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());

    -- Step 2: If no occasion is found, throw a 'no_data_found' exception.
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link USING ERRCODE = 'PGRST001'; -- Custom error for PostgREST
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- If not, throw an 'insufficient_privilege' exception.
    IF NOT (get_is_editor_view_on_occasion(v_occasion_id) OR get_is_editor_order_view_on_occasion(v_occasion_id)) THEN
        RAISE EXCEPTION 'User is not authorized to view forms for this occasion.' USING ERRCODE = '42501'; -- insufficient_privilege
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The order statistics are nested within a 'stats' JSON object.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
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
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    LEFT JOIN (
        -- This subquery calculates all required counts in a single pass over the orders table.
        SELECT
            (data->>'form')::uuid AS form_key,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE state = 'storno') AS storno,
            COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
            COUNT(*) FILTER (WHERE state = 'ordered') AS ordered
        FROM eshop.orders
        WHERE data->>'form' IS NOT NULL -- Ensure the key exists before casting
        GROUP BY form_key
    ) AS order_stats ON f.key = order_stats.form_key
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, ensure an empty JSON array is returned.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the data directly.
    RETURN forms_data;
END;
$$;
