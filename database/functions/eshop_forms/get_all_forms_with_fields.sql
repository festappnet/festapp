CREATE OR REPLACE FUNCTION public.get_all_forms_with_fields(
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
    -- Find the ID of the occasion using its unique link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link)
      AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());

    -- Step 2: If no occasion is found, return a 404 'Not Found' error.
    -- This handles cases where the occasion_link does not exist.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_view_on_occasion` exists to check permissions.
    IF NOT public.can_read_form_catalog(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Shared administrator summary projection; transport-specific secrets are
    -- retained here for the existing UI, and removed by the bounded MCP reader.
    forms_data := public.get_form_catalog_rows_internal(v_occasion_id);

    -- Step 5: If no forms were found for the occasion, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 'OK' status code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$$;
