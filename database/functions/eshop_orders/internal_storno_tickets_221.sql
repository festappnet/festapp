CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
BEGIN
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE eshop.order_participants SET lifecycle='cancelled',updated_at=clock_timestamp() WHERE ticket_id=ANY(ticket_ids_to_storno);
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT form_id FROM eshop.order_participants WHERE ticket_id=ANY(ticket_ids_to_storno));
    -- 1. Get all related order_product_ticket IDs
    SELECT ARRAY_AGG(opt.id) INTO opt_ids
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ANY(ticket_ids_to_storno);

    -- 2. (NEW) Delete any occasion_users linked to these tickets.
    -- We delete directly because the parent function already
    -- verified the user has 'editor' permissions.
    DELETE FROM public.occasion_users
    WHERE ticket = ANY(ticket_ids_to_storno);

    -- 3. Update the tickets themselves to 'storno'
    UPDATE eshop.tickets
    SET state = 'storno', updated_at = NOW()
    WHERE id = ANY(ticket_ids_to_storno);

    -- 4. Nullify the relevant spots
    IF opt_ids IS NOT NULL THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL,
            secret = NULL,
            secret_expiration_time = NULL,
            updated_at = NOW(),
            resource = NULL,
            state = NULL
        WHERE order_product_ticket = ANY(opt_ids);
    END IF;

    -- 5. Nullify the product link on the order_product_ticket records
    UPDATE eshop.order_product_ticket
    SET product = NULL
    WHERE ticket = ANY(ticket_ids_to_storno);

END;
$$;