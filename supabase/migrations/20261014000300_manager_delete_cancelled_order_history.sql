-- Unit managers may delete an order history entry independently of parent state.
-- Parent order, ticket, finance and all other cancelled-order write guards remain unchanged.

CREATE OR REPLACE FUNCTION public.delete_order_history(p_history_id bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions AS $$
DECLARE
    v_order_id bigint;
    v_occasion_id bigint;
    v_unit_id bigint;
BEGIN
    SELECT oh."order" INTO v_order_id
    FROM eshop.orders_history oh WHERE oh.id = p_history_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'History record not found.';
    END IF;

    -- Match order deletion's parent-before-history lock order. Pin the unit
    -- used for authorization as well as the history's actual parent binding.
    SELECT o.occasion, occ.unit INTO v_occasion_id, v_unit_id
    FROM eshop.orders o JOIN public.occasions occ ON occ.id = o.occasion
    WHERE o.id = v_order_id
    FOR UPDATE OF o FOR SHARE OF occ;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Could not find the unit associated with the order.';
    END IF;
    PERFORM 1 FROM eshop.orders_history oh
    WHERE oh.id = p_history_id AND oh."order" = v_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'History record not found or order changed.';
    END IF;

    -- Verify the user is a manager on the unit.
    -- This function will raise an exception if the user does not have manager permissions.
    PERFORM public.check_is_manager_on_unit(v_unit_id);

    -- Removing an audit entry does not mutate the parent order or its finance.
    -- Proceed with the deletion if permission check passes
    DELETE FROM eshop.orders_history WHERE id = p_history_id AND "order" = v_order_id;
END;
$$;
