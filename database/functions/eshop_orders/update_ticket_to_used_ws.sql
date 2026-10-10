CREATE OR REPLACE FUNCTION public.update_ticket_to_used_ws(
    ticket_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- 1. Retrieve the occasion ID and State from the ticket.
    -- If the ticket does not exist, this will raise a NO_DATA_FOUND exception (due to STRICT).
    SELECT occasion, state
    INTO STRICT occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- 1a. Check State Validity (New Check)
    IF current_state = 'used' THEN
        RAISE EXCEPTION 'Ticket % is already used.', ticket_id;
    ELSIF current_state = 'storno' THEN
        RAISE EXCEPTION 'Ticket % is cancelled (storno).', ticket_id;
    END IF;

    -- 2. Check if the current user has editor permissions for the occasion.
    -- This function will raise an exception if the user is not an editor.
    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- 3. Update the ticket state to 'used' AND update timestamp.
    -- This is only reached if the previous checks pass without raising an exception.
    UPDATE eshop.tickets
    SET
        state = 'used',
        updated_at = now()
    WHERE id = ticket_id;
END;
$$;