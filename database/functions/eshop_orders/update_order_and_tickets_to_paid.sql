CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
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

    -- Check if the order is in 'ordered' or 'created' state before proceeding
    IF current_state='expired' AND EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
      WHERE o.id=order_id AND p.payment_method='stripe') THEN
      RETURN jsonb_build_object('code',409,'message','Stripe reservation was released');
    END IF;
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

    -- Queue deposit-paid or fully-paid email for orders with deposit
    DECLARE
        v_deposit_amount NUMERIC;
        v_total_amount NUMERIC;
        v_total_paid NUMERIC;
        v_email_code TEXT;
        v_org_id BIGINT;
        v_unit_id BIGINT;
    BEGIN
        -- Fetch payment info for this order
        SELECT pi.deposit_amount, pi.amount, pi.paid
        INTO v_deposit_amount, v_total_amount, v_total_paid
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        WHERE o.id = order_id;

        -- Only queue emails for deposit orders. The template handler branches
        -- internally on amountPaid >= totalAmount to render either the
        -- deposit-paid copy (with remaining balance + QR) or the fully-paid copy.
        IF v_deposit_amount IS NOT NULL AND v_total_paid >= v_deposit_amount THEN
            -- Get organization and unit from occasion
            SELECT occ.organization, occ.unit
            INTO v_org_id, v_unit_id
            FROM public.occasions occ
            WHERE occ.id = occasion_id;

            v_email_code := 'TICKET_ORDER_PAYMENT_DONE';

            IF v_email_code IS NOT NULL THEN
                PERFORM public.enqueue_order_email(v_email_code,jsonb_build_object('order_id',order_id),v_org_id,occasion_id,v_unit_id);
            END IF;
        END IF;
    END;

    PERFORM public.notification_center_order_state_internal(order_id);
    PERFORM public.enqueue_paid_order_tickets(order_id);

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;
