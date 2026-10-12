CREATE OR REPLACE FUNCTION public.update_ticket_to_used(
    ticket_id bigint,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
    expected_scan_code text;
BEGIN
    -- 1. Validate Ticket Existence
    IF NOT EXISTS (
        SELECT 1 FROM eshop.tickets WHERE id = ticket_id
    ) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Ticket not found.'
        );
    END IF;

    -- 2. Retrieve Associated Occasion ID AND Current State
    SELECT occasion, state
    INTO occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- Check if occasion_id is present (Integrity check)
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion associated with ticket not found.'
        );
    END IF;

    -- 2a. Validate Ticket State (New Check)
    IF current_state = 'used' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket has already been used.'
        );
    ELSIF current_state = 'storno' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket is cancelled (storno).'
        );
    END IF;

    -- 3. Retrieve Expected Scan Code from occasions_hidden via foreign key
    SELECT oh.secret
    INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    -- Check if scan_code is defined
    IF expected_scan_code IS NULL THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Scan code not defined for occasion.'
        );
    END IF;

    -- 4. Validate Provided Scan Code
    IF scan_code IS DISTINCT FROM expected_scan_code THEN
        RETURN jsonb_build_object(
            'code', 401,
            'message', 'Scan code is not correct.'
        );
    END IF;

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- 5. Update Ticket State to 'used' AND update timestamp
    UPDATE eshop.tickets
    SET
        state = 'used',
        updated_at = now()
    WHERE id = ticket_id;

    -- 6. Return Success Message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Ticket state updated to used successfully.'
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
