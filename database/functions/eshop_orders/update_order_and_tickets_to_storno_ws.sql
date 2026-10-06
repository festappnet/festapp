CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(order_id bigint)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion INTO occasion_id FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Verify if the user is an editor on the occasion
    IF (SELECT get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;

    -- Use the same parent lock order as ticket cancellation.
    PERFORM 1 FROM eshop.orders WHERE id=order_id FOR UPDATE;

    -- Call the original function to update the order and tickets
    PERFORM update_order_and_tickets_to_storno_221(order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
