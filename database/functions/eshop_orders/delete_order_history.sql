CREATE OR REPLACE FUNCTION public.delete_order_history(p_history_id bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions AS $$
DECLARE
    v_occasion_id bigint;
    v_unit_id bigint;
BEGIN
    -- Determine the occasion linked to the history entry
    SELECT o.occasion INTO v_occasion_id
    FROM eshop.orders_history oh
    JOIN eshop.orders o ON oh."order" = o.id
    WHERE oh.id = p_history_id;

    -- If the history entry is not found, raise an exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'History record not found.';
    END IF;

    -- Find the unit associated with the occasion
    SELECT unit INTO v_unit_id
    FROM public.occasions
    WHERE id = v_occasion_id;

    -- If the occasion is not linked to a unit, raise an exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Could not find the unit associated with the order.';
    END IF;

    -- Verify the user is a manager on the unit.
    -- This function will raise an exception if the user does not have manager permissions.
    PERFORM check_is_manager_on_unit(v_unit_id);

    PERFORM public.check_order_is_mutable((SELECT "order" FROM eshop.orders_history WHERE id=p_history_id));

    -- Proceed with the deletion if permission check passes
    DELETE FROM eshop.orders_history WHERE id = p_history_id;
END;
$$;