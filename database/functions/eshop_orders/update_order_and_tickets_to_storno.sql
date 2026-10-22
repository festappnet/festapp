CREATE OR REPLACE FUNCTION public.cancel_order_domain_internal_v1(order_id BIGINT,p_notify boolean)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
    v_order eshop.orders;
    v_occasion public.occasions;
    v_notice jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=order_id)]);
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=order_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
    IF v_order.state='storno' THEN RETURN; END IF;
    PERFORM public.check_order_is_mutable(order_id);
    -- Card finances and admission are resolved by provider facts and the
    -- audited refund decision, never by resetting an order's original price.
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi
      WHERE pi.id=v_order.payment_info AND pi.payment_method='stripe') THEN
        RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION';
    END IF;
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;

    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

    -- The full transition owns the durable automatic commitment for every caller.
    SELECT * INTO v_occasion FROM public.occasions WHERE id=v_order.occasion;
    IF p_notify AND position('@' in v_order.data->>'email')>0
      AND length(v_order.data->>'email')<=320 THEN
      v_notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',
        jsonb_build_object('order_id',order_id),v_occasion.organization,
        v_occasion.id,v_occasion.unit);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_order_domain_internal_v1(bigint,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Compatibility for trusted SQL callers; domain logic exists only above.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.cancel_order_domain_internal_v1(order_id,true);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
