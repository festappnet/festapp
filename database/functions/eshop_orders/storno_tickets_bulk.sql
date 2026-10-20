CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order_id BIGINT;
    v_occasion_id BIGINT;
    v_tickets_in_order BIGINT[];
    v_tickets_to_cancel_in_order BIGINT[];
    v_remaining_count INT;
    v_ticket_id_to_remove BIGINT;
    v_original_data JSONB;
    v_updated_tickets_json JSONB;
    v_ticket_elem JSONB;
    v_product_elem JSONB;
    v_removed_price NUMERIC(10, 2);
    v_current_price NUMERIC(10, 2);
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
    -- 1. Identify all unique orders involved in this batch AND their occasion
    -- We need the occasion ID to perform the security check
    FOR v_order_id, v_occasion_id IN
        SELECT DISTINCT o.id, o.occasion
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE t.id = ANY(p_ticket_ids)
        ORDER BY o.id
    LOOP
        -- 2. SECURITY CHECK
        -- Verify that the current user has editor permissions on the occasion associated with the order.
        IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
            RAISE EXCEPTION 'Permission denied to storno tickets for order % on occasion %', v_order_id, v_occasion_id;
        END IF;

        -- Repeated selected tickets in an otherwise active order are a no-op.
        IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
          WHERE opt."order"=v_order_id AND t.id=ANY(p_ticket_ids) AND t.state IS DISTINCT FROM 'storno') THEN
          CONTINUE;
        END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        -- Serialize cancellations on the same order before counting survivors.
        PERFORM 1 FROM eshop.orders WHERE id = v_order_id FOR UPDATE;

        -- 3. Get all active tickets currently in this order
        SELECT ARRAY_AGG(t.id)
        INTO v_tickets_in_order
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        WHERE opt."order" = v_order_id
        AND (t.state IS NULL OR t.state != 'storno');

        -- 4. Get intersection: Tickets in this order that we want to cancel
        SELECT ARRAY_AGG(id)
        INTO v_tickets_to_cancel_in_order
        FROM UNNEST(v_tickets_in_order) AS id
        WHERE id = ANY(p_ticket_ids);

        -- A replay or a selection containing only cancelled tickets has no effect.
        IF coalesce(cardinality(v_tickets_to_cancel_in_order), 0) = 0 THEN
            CONTINUE;
        END IF;

        -- 5. Calculate how many would remain
        v_remaining_count := array_length(v_tickets_in_order, 1) - array_length(v_tickets_to_cancel_in_order, 1);

        -- -----------------------------------------------------
        -- SCENARIO A: Full Order Cancellation
        -- -----------------------------------------------------
        IF v_remaining_count <= 0 THEN
            -- Helper function to cancel the entire order
            PERFORM update_order_and_tickets_to_storno_ws_internal_v1(v_order_id);

        -- -----------------------------------------------------
        -- SCENARIO B: Partial Cancellation (Modify Order)
        -- -----------------------------------------------------
        ELSE
            -- 1. Mark specific tickets as storno in DB
            PERFORM internal_storno_tickets_221(v_tickets_to_cancel_in_order);

            -- 2. Fetch Order Data
            SELECT data, price INTO v_original_data, v_current_price
            FROM eshop.orders WHERE id = v_order_id;

            v_updated_tickets_json := '[]'::JSONB;
            v_removed_price := 0;

            -- 3. Rebuild JSON data, filtering out cancelled tickets and summing price to remove
            FOR v_ticket_elem IN SELECT * FROM jsonb_array_elements(v_original_data->'tickets')
            LOOP
                v_ticket_id_to_remove := (v_ticket_elem->>'id')::BIGINT;

                -- If this ticket is one of the ones being cancelled
                IF v_ticket_id_to_remove = ANY(v_tickets_to_cancel_in_order) THEN
                    -- Sum up price to deduct
                    FOR v_product_elem IN SELECT * FROM jsonb_array_elements(v_ticket_elem->'products')
                    LOOP
                        v_removed_price := v_removed_price + COALESCE((v_product_elem->>'price')::NUMERIC, 0);
                    END LOOP;
                ELSE
                    -- Keep this ticket in the new JSON
                    v_updated_tickets_json := v_updated_tickets_json || v_ticket_elem;
                END IF;
            END LOOP;

            -- Fence unsent snapshots of the previous ticket set, and keep the
            -- payment amount aligned with the new order total.
            PERFORM public.cancel_order_email_intents(v_order_id);
            UPDATE eshop.payment_info SET amount=GREATEST(0, COALESCE(v_current_price,0)-v_removed_price)
            WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);

            -- 4. Update Order (Data & Price)
            UPDATE eshop.orders
            SET
                data = v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                price = GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                email_payment_version = email_payment_version + 1,
                updated_at = NOW()
            WHERE id = v_order_id;

            -- Refresh only this order's existing reminder schedule for its new amount.
            PERFORM public.set_payment_deadline(pi.id,pi.deadline)
            FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
            WHERE o.id=v_order_id AND o.state='ordered' AND pi.deadline IS NOT NULL;

            -- Existing delivery policy prepares the surviving tickets if their
            -- paid order has not finished sending yet; sent orders stay untouched.
            PERFORM public.enqueue_paid_order_tickets(v_order_id);

            -- 5. Insert ONE history record for this modification
            INSERT INTO eshop.orders_history (
                "order",
                data,
                state,
                price,
                created_at
            )
            VALUES (
                v_order_id,
                v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                (SELECT state FROM eshop.orders WHERE id=v_order_id),
                GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                NOW()
            );
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[]) FROM PUBLIC, anon, authenticated;
