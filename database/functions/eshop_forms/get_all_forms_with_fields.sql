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
    WHERE link = occasion_link
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
    IF NOT public.get_is_editor_view_on_occasion(v_occasion_id)
       AND NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms and their associated fields for the occasion into a JSONB array.
    -- For each form, a subquery aggregates its related form_fields.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
                'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
                'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'response_count', (
                -- Subquery to count the number of responses (orders) for each form.
                SELECT COUNT(*)
                FROM eshop.orders o
                WHERE (o.data->>'form')::uuid = f.key
            ),
            'fields', (
                -- Subquery to aggregate all form_fields associated with the current form.
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'type', ff.type,
                        'is_ticket_field', ff.is_ticket_field
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                WHERE ff.form = f.id
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

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
