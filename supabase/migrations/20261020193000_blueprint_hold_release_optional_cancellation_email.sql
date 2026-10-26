DROP FUNCTION public.storno_tickets_bulk_internal_v1(bigint[]);
CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[], p_send_email BOOLEAN DEFAULT TRUE)
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
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_ticket_ids)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(p_ticket_ids)));
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

        -- Already-cancelled tickets are an idempotent no-op after authorization.
        -- They must not invoke the edit guard or create a second cancellation intent.
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
            -- Commit cancellation and its durable email intent together. Replays
            -- cannot reach this branch once the active tickets are cancelled.
            IF p_send_email AND EXISTS (SELECT 1 FROM eshop.orders WHERE id=v_order_id
                AND position('@' in data->>'email')>0 AND length(data->>'email')<=320) THEN
            PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',
                jsonb_build_object('order_id', v_order_id),
                (SELECT organization FROM public.occasions WHERE id=v_occasion_id),
                v_occasion_id,
                (SELECT unit FROM public.occasions WHERE id=v_occasion_id),
                now(), 'last-ticket-cancelled:' || v_order_id);
            END IF;


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



REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[],boolean) FROM service_role;
CREATE OR REPLACE FUNCTION public.storno_tickets_client_sync_v1(
  p_tickets bigint[],p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[]; v_changed_orders bigint[]; v_cancelled jsonb; v_updated jsonb;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(p_tickets)));
  IF cardinality(p_tickets)>(SELECT hard_cap FROM public.abuse_policy_rules WHERE rule_key='order.mutation.items') THEN RAISE SQLSTATE 'PT429' USING MESSAGE='abuse_limit_exceeded'; END IF;
  SELECT min(t.occasion) INTO v_occasion FROM eshop.tickets t
    WHERE t.id=ANY(p_tickets);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_tickets)=0
    OR (SELECT count(*) FROM eshop.tickets t
      WHERE t.id=ANY(p_tickets) AND t.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tickets',p_tickets)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.tickets.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,cardinality(p_tickets));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_tickets)));
  -- Lock in the same order as the bulk mutation, then capture only actual changes.
  PERFORM o.id FROM eshop.orders o WHERE o.id IN (
    SELECT opt."order" FROM eshop.order_product_ticket opt
    JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets)) ORDER BY o.id FOR UPDATE;
  SELECT array_agg(DISTINCT opt."order") INTO v_changed_orders
    FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets) AND t.state IS DISTINCT FROM 'storno';
  PERFORM public.storno_tickets_bulk_internal_v1(p_tickets, false);
  SELECT coalesce(jsonb_agg(o.id ORDER BY o.id) FILTER(WHERE o.state='storno'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('id',o.id,'email',o.data->>'email') ORDER BY o.id)
      FILTER(WHERE o.state IS DISTINCT FROM 'storno'),'[]'::jsonb)
    INTO v_cancelled,v_updated FROM eshop.orders o WHERE o.id=ANY(v_changed_orders);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.tickets.cancel',
    jsonb_build_array(jsonb_build_object('entityType','ticket','entityId',NULL,
      'operation','update','safeLabel','Ticket cancellation',
      'changedFields',jsonb_build_array('state','membership','allocations'))),
    v_before_users,jsonb_build_object('ticketIds',to_jsonb(p_tickets),
      'cancelledOrderIds',v_cancelled,'updatedOrders',v_updated));
END; $$;



-- Administrative release of temporary holds. Buyers still use select_spot.
CREATE OR REPLACE FUNCTION public.release_blueprint_holds_client_sync_v1(
 p_spots bigint[], p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); occ bigint; ids bigint[]; bp bigint; started jsonb; users uuid[]; fingerprint text;
BEGIN
 IF actor IS NULL OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>256 THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT min(b.occasion),min(s.blueprint) INTO occ,bp FROM eshop.spots s JOIN eshop.blueprints b ON b.id=s.blueprint WHERE s.id=ANY(p_spots);
 IF occ IS NULL OR public.get_is_editor_order_on_occasion(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint=bp) <>
  cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_spots) x)) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM public.check_occasion_writable(occ);
 fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('spots',p_spots)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.holds.release',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) requested
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(ids) AND (blueprint IS DISTINCT FROM bp OR order_product_ticket IS NOT NULL)) THEN
  RAISE check_violation USING MESSAGE='Spot is already ordered'; END IF;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=occ;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now()
 WHERE id=ANY(ids) AND order_product_ticket IS NULL;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.blueprint.holds.release',
  jsonb_build_array(jsonb_build_object('entityType','spot','entityId',NULL,'operation','update','safeLabel','Temporary reservation released','changedFields',jsonb_build_array('reservation'))),
  users,jsonb_build_object('spotIds',to_jsonb(ids)));
END $$;
REVOKE ALL ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.release_blueprint_holds_client_sync_v1(bigint[],uuid) TO authenticated;
