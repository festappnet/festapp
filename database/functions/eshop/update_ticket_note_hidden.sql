CREATE OR REPLACE FUNCTION public.update_ticket_note_hidden(ticket_id bigint, new_note_hidden text)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Retrieve the occasion_id from the ticket
    SELECT occasion INTO occasion_id FROM eshop.tickets WHERE id = ticket_id;

    -- Check if occasion_id was successfully retrieved
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found or occasion not specified');
    END IF;

    -- Check if the user has the right to edit the given occasion
    IF (get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        -- Return an error if the user is not authorized
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- Proceed to update note_hidden if the user is authorized
    UPDATE eshop.tickets
    SET note_hidden = new_note_hidden, updated_at = now()
    WHERE id = ticket_id;

    -- Check if the update was successful
    IF FOUND THEN
        RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
    ELSE
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found');
    END IF;
END;
$$ LANGUAGE plpgsql;
