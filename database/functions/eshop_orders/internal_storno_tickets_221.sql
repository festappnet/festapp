CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
    nc_changed record;
    nc_changes jsonb;
    nc_products bigint[];
    nc_event uuid;
    nc_contexts bigint[];
    nc_blueprints bigint[];
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(ticket_ids_to_storno)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ticket_ids_to_storno)));
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT o.form FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE x.ticket=ANY(ticket_ids_to_storno));
    UPDATE eshop.waitlist_offer_slots SET outcome='cancelled',updated_at=clock_timestamp()
      WHERE ticket_id=ANY(ticket_ids_to_storno) AND outcome='pending';
    SELECT array_agg(DISTINCT s.inventory_context),array_agg(DISTINCT s.blueprint) INTO nc_contexts,nc_blueprints FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x.ticket=ANY(ticket_ids_to_storno);
    SELECT array_agg(DISTINCT product) INTO nc_products FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno) AND product IS NOT NULL;
    SELECT coalesce(jsonb_agg(to_jsonb(changes)),'[]') INTO nc_changes FROM (
      SELECT x."order" order_id,array_agg(DISTINCT t.id ORDER BY t.id) ticket_ids FROM eshop.order_product_ticket x
      JOIN eshop.tickets t ON t.id=x.ticket WHERE t.id=ANY(ticket_ids_to_storno) AND t.state IS DISTINCT FROM 'storno' GROUP BY x."order"
    ) changes;
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

    FOR nc_changed IN SELECT * FROM jsonb_to_recordset(nc_changes) AS r(order_id bigint,ticket_ids bigint[]) LOOP
      PERFORM public.notification_center_order_internal(nc_changed.order_id,'order_cancelled',encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex'),auth.uid(),
        jsonb_build_object('count',cardinality(nc_changed.ticket_ids)));
      SELECT id INTO nc_event FROM public.notification_center_events WHERE kind='order_cancelled' AND data->>'orderId'=nc_changed.order_id::text
        AND source_key='order_cancelled:'||nc_changed.order_id||':'||encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex');
      PERFORM public.notification_center_form_capacity_internal((SELECT form FROM eshop.orders WHERE id=nc_changed.order_id),auth.uid(),nc_event);
    END LOOP;
    PERFORM public.notification_center_product_capacity_internal(p) FROM unnest(nc_products) p;
    PERFORM public.notification_center_inventory_capacity_internal(c) FROM unnest(nc_contexts) c WHERE c IS NOT NULL;
    PERFORM public.notification_center_blueprint_capacity_internal(b) FROM unnest(nc_blueprints) b WHERE b IS NOT NULL;
END;
$$;