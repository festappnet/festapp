CREATE OR REPLACE FUNCTION update_order_and_tickets_to_sent_ws(order_id bigint, ticket_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
BEGIN
    SELECT occasion INTO v_occasion_id
    FROM eshop.orders
    WHERE id = order_id;

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    IF (SELECT get_is_editor_order_on_occasion(v_occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;

    RETURN update_order_and_tickets_to_sent(order_id, ticket_ids);
END;
$$;