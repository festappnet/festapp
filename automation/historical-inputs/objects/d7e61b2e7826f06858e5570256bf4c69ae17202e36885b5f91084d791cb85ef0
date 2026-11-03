DROP FUNCTION IF EXISTS update_scan_code(text, text);

CREATE OR REPLACE FUNCTION update_scan_code(
    occasion_link TEXT,
    new_scan_code TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    occasions_hidden_id BIGINT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to edit this occasion.'
        );
    END IF;

    PERFORM 1 FROM public.scanner_settings WHERE scanner_settings.occasion_id=v_occasion_id FOR UPDATE;
    UPDATE public.scanner_settings SET epoch=epoch+1 WHERE scanner_settings.occasion_id=v_occasion_id;
    -- 4. Check if occasions_hidden exists for the occasion
    SELECT o.occasion_hidden
    INTO occasions_hidden_id
    FROM public.occasions o
    WHERE o.id = v_occasion_id;

    IF occasions_hidden_id IS NOT NULL THEN
        -- Update existing scan_code
        UPDATE public.occasions_hidden
        SET secret = new_scan_code
        WHERE id = occasions_hidden_id;
    ELSE
        -- Insert new occasions_hidden record
        INSERT INTO public.occasions_hidden (secret)
        VALUES (new_scan_code)
        RETURNING id INTO occasions_hidden_id;

        -- Update the occasion to link to the new occasions_hidden
        UPDATE public.occasions
        SET occasion_hidden = occasions_hidden_id
        WHERE id = v_occasion_id;
    END IF;

    -- 5. Return a success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code updated successfully.'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;
