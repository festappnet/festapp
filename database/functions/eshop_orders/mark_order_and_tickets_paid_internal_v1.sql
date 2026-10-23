-- Shared state transition. Public callers own authorization and delivery intent.
CREATE OR REPLACE FUNCTION public.mark_order_and_tickets_paid_internal_v1(order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; current_state text;
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id FOR UPDATE;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
      WHERE o.id=order_id AND pi.payment_method='stripe' AND NOT EXISTS(
        SELECT 1 FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id
        WHERE a.order_id=o.id AND m.kind='payment' AND m.amount_minor=a.amount_minor
          AND m.connection_id=pi.stripe_connection_id AND m.occurred_at<=a.reservation_expires_at)) THEN
      RETURN jsonb_build_object('code',409,'message','STRIPE_PROVIDER_PAYMENT_REQUIRED');
    END IF;

    IF current_state='expired' AND EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
      WHERE o.id=order_id AND p.payment_method='stripe') THEN
      RETURN jsonb_build_object('code',409,'message','Stripe reservation was released');
    END IF;
    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now(),email_payment_version=email_payment_version+1
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state IN ('ordered','expired','paid');

    PERFORM public.notification_center_order_state_internal(order_id);
    RETURN jsonb_build_object('code',200,'message','Update successful');
END $$;
REVOKE ALL ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) TO service_role;
