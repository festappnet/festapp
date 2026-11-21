CREATE OR REPLACE FUNCTION public.get_all_forms(occasion_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Step 2: If no occasion is found, return a 404 error.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_on_occasion` exists.
    IF NOT get_is_editor_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The subquery for 'response_count' is now corrected to count responses from the 'eshop.orders' table.
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
            'response_count',COALESCE(order_stats.total,0)
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    LEFT JOIN public.get_order_catalog_counts_internal(
      ARRAY[v_occasion_id], ARRAY(SELECT id FROM public.forms WHERE occasion=v_occasion_id)
    ) AS order_stats ON f.id=order_stats.form_id
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, return an empty array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$function$;
