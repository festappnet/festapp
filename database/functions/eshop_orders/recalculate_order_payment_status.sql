CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_deposit_amount numeric;
    v_price numeric;
    v_state text;
    v_transition jsonb;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Get Paid Amount and Deposit Amount from Payment Info
    SELECT paid, deposit_amount INTO v_paid, v_deposit_amount
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    IF COALESCE(v_paid, 0) >= COALESCE(v_deposit_amount, v_price) THEN
        -- Fully Paid (or Deposit Paid) -> Move to Paid
        IF v_state != 'paid' AND (v_state = 'ordered' OR v_state = 'created' OR v_state = 'expired') THEN
             -- The legacy JSON boundary reports failures instead of raising.
             -- Propagate them so payment, order, ticket intent and webhook receipt
             -- cannot commit independently of the canonical paid transition.
             v_transition := public.update_order_and_tickets_to_paid(p_order_id);
             IF (v_transition->>'code') IS DISTINCT FROM '200' THEN
                 RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                     COALESCE(v_transition->>'message','invalid transition receipt');
             END IF;
        END IF;
    ELSE
        -- Underpaid -> Revert to Ordered (if currently Paid)
        IF v_state IN ('paid','sent') THEN
            PERFORM public.cancel_order_email_intents(p_order_id);
            -- Revert Order
            UPDATE eshop.orders
            SET state = 'ordered', updated_at = now(),email_payment_version=email_payment_version+1
            WHERE id = p_order_id;

            -- Revert Tickets (only those that are 'paid')
            UPDATE eshop.tickets
            SET state = 'ordered', updated_at = now() -- Reverted to 'ordered' as 'valid' is not a supported state

            FROM eshop.order_product_ticket
            WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
            AND eshop.order_product_ticket."order" = p_order_id
            AND eshop.tickets.state IN ('paid','sent');
        END IF;
    END IF;
END;
$$;
