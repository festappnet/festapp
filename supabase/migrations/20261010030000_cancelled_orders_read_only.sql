-- Cancelled orders and tickets are immutable through editor commands.
-- Bank-import facts and cancellation-email delivery remain independent.

-- Source: database/functions/eshop_orders/check_order_is_mutable.sql
-- Domain commands authorize callers before invoking these private guards.
-- Lock the order through the write so cancellation cannot race with an edit.
CREATE OR REPLACE FUNCTION public.check_order_is_mutable(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  SELECT state INTO v_state FROM eshop.orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_ticket_is_mutable(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint; v_state text;
BEGIN
  FOR v_order IN SELECT DISTINCT opt."order" FROM eshop.order_product_ticket opt
    WHERE opt.ticket=p_ticket ORDER BY opt."order" LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
  SELECT state INTO v_state FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TICKET_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'TICKET_CANCELLED: Cancelled tickets are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_payment_info_is_mutable(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint;
BEGIN
  FOR v_order IN SELECT id FROM eshop.orders WHERE payment_info=p_payment ORDER BY id LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  TO service_role;

-- Source: database/functions/emails/email_domain.sql
-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 IF v_order.state='storno' AND p_code<>'TICKET_ORDER_STORNO' THEN
  RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
 END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_tickets' THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false';
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;


-- Source: database/functions/emails/set_payment_deadline.sql
CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record; v_seconds bigint;
BEGIN
 PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
 UPDATE eshop.payment_info SET deadline=p_new_deadline,data=coalesce(data,'{}')||'{"current_version_reminded":false}'::jsonb,
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id,occ.features FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  SELECT (f->>'reminder_interval_seconds')::bigint INTO v_seconds FROM jsonb_array_elements(o.features) f WHERE f->>'code'='form';
  PERFORM public.queue_payment_reminders(o.id,coalesce(v_seconds,0));
 END LOOP;
END $$;

-- Source: database/functions/eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'currency_code', product_data.currency_code
    ));
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;
    new_state TEXT;

    price_delta NUMERIC;
    history_needed BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order";
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the orders.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id);
    new_price := (new_product_json->>'price')::numeric;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate financials and state
    price_delta := new_price - original_price;
    history_needed := (original_product_id IS DISTINCT FROM p_new_product_id);
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- Recalculate order state
    SELECT CASE
        WHEN COALESCE(pi.paid, 0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM eshop.payment_info pi WHERE pi.id = ord.payment_info;

    -- 6. Build the new orders.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        state = new_state,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- 8. Create history log *only if* the product ID actually changed
    IF history_needed THEN
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        VALUES (ord.id, new_data, new_state, new_order_price, ord.currency_code);
    END IF;

END;
$$;


CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 BIGINT, spot_id_2 BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    spot1 RECORD;
    spot2 RECORD;
    occasion_id_common BIGINT;
    has_permission BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Input Validation
    IF spot_id_1 IS NULL OR spot_id_2 IS NULL THEN
        RAISE EXCEPTION 'Both spot_id_1 and spot_id_2 must be provided' USING ERRCODE = '22023';
    END IF;
    IF spot_id_1 = spot_id_2 THEN
        RAISE EXCEPTION 'Cannot swap a spot with itself' USING ERRCODE = '22023';
    END IF;

    -- 2. Fetch Spot Data
    SELECT * INTO spot1 FROM eshop.spots WHERE id = spot_id_1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 1 not found (ID: %)', spot_id_1 USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO spot2 FROM eshop.spots WHERE id = spot_id_2;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 2 not found (ID: %)', spot_id_2 USING ERRCODE = 'P0002'; END IF;

    -- 3. Permission and Occasion Check
    IF spot1.occasion IS NULL OR spot2.occasion IS NULL THEN
         RAISE EXCEPTION 'Spots are missing occasion information' USING ERRCODE = '22004';
    END IF;
    IF spot1.occasion <> spot2.occasion THEN
        RAISE EXCEPTION 'Spots do not belong to the same occasion (Spot1: %, Spot2: %)', spot1.occasion, spot2.occasion USING ERRCODE = 'P0001';
    END IF;
    occasion_id_common := spot1.occasion;

    -- Check permission
    BEGIN
        SELECT get_is_editor_order_on_occasion(occasion_id_common) INTO has_permission;
    EXCEPTION
        WHEN undefined_function THEN RAISE EXCEPTION 'Permission check function get_is_editor_order_on_occasion() does not exist.' USING ERRCODE = '42883';
        WHEN OTHERS THEN RAISE EXCEPTION 'Error during permission check: %', SQLERRM;
    END;
    IF has_permission <> TRUE THEN
        RAISE EXCEPTION 'User is not authorized to edit orders for this occasion' USING ERRCODE = '42501';
    END IF;

    -- 4. Main Swap Logic: Branch based on assignment status
    -- This logic is now greatly simplified by the helper functions.

    IF spot1.order_product_ticket IS NOT NULL AND spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE A: BOTH SPOTS ARE ASSIGNED
        -- ----------------------------------------------------------------

        -- Ticket 1 (from spot 1) moves to Spot 2, so it must adopt Spot 2's product.
        PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);

        -- Ticket 2 (from spot 2) moves to Spot 1, so it must adopt Spot 1's product.
        PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);

    ELSIF spot1.order_product_ticket IS NOT NULL OR spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE B/C: ONE SPOT IS ASSIGNED, ONE IS UNASSIGNED
        -- ----------------------------------------------------------------

        IF spot1.order_product_ticket IS NOT NULL THEN
            -- Spot 1 is assigned, Spot 2 is unassigned.
            -- Ticket 1 moves to Spot 2 and adopts Spot 2's product.
            PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);
        ELSE
            -- Spot 2 is assigned, Spot 1 is unassigned.
            -- Ticket 2 moves to Spot 1 and adopts Spot 1's product.
            PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);
        END IF;

    ELSE
        -- ----------------------------------------------------------------
        -- CASE D: BOTH SPOTS ARE UNASSIGNED
        -- ----------------------------------------------------------------
        -- Nothing to do.
        RETURN;
    END IF;

    -- 5. Final Spot Update
    -- This block runs for Cases A, B, and C.
    -- We ONLY swap the 'order_product_ticket' FK. The 'product' column
    -- on the spot (spot1.product, spot2.product) never changes.
    UPDATE eshop.spots
    SET
        order_product_ticket = CASE
            WHEN id = spot_id_1 THEN spot2.order_product_ticket -- Spot 1 gets Ticket 2
            WHEN id = spot_id_2 THEN spot1.order_product_ticket -- Spot 2 gets Ticket 1
        END
    WHERE id IN (spot_id_1, spot_id_2);

END;
$$;
-- Source: database/functions/eshop/update_payment_info_variable_symbol.sql
CREATE OR REPLACE FUNCTION public.update_payment_info_variable_symbol(
  p_payment_info_id bigint,
  p_variable_symbol bigint
)
  RETURNS void
  LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.check_payment_info_is_mutable(p_payment_info_id);
  UPDATE eshop.payment_info
     SET variable_symbol = p_variable_symbol
   WHERE id = p_payment_info_id;
END;
$$;

-- Source: database/functions/eshop/update_ticket_note_hidden.sql
CREATE OR REPLACE FUNCTION public.update_ticket_note_hidden(ticket_id bigint, new_note_hidden text)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Retrieve the occasion_id from the ticket
    SELECT occasion INTO occasion_id FROM eshop.tickets WHERE id = ticket_id;

    -- Check if occasion_id was successfully retrieved
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found or occasion not specified');
    END IF;

    -- Check if the user has the right to edit the given occasion
    IF (get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        -- Return an error if the user is not authorized
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- Proceed to update note_hidden if the user is authorized
    UPDATE eshop.tickets
    SET note_hidden = new_note_hidden, updated_at = now()
    WHERE id = ticket_id;

    -- Check if the update was successful
    IF FOUND THEN
        RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
    ELSE
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found');
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Source: database/functions/eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  unit_id BIGINT;
  ou_record RECORD;
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info
    INTO order_oc, payment_info_id
    FROM eshop.orders
   WHERE id = order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Check if the current user is a manager on the order's occasion.
  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = order_oc;

  PERFORM public.check_is_manager_on_unit(unit_id);
  -- Use the established occasion/group/activity prefix before order and email locks.
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  PERFORM public.check_is_manager_on_unit(unit_id);

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  PERFORM public.check_order_is_mutable(order_id);

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion=order_oc)
    AND NOT (public.get_is_manager_on_occasion(order_oc) OR public.get_is_admin_on_occasion(order_oc)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.lock_activity_aggregate_internal_v1(v_occasion);
  PERFORM public.check_is_manager_on_unit(v_unit);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;

-- Source: database/functions/eshop_orders/delete_order_history.sql
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
-- Source: database/functions/eshop_orders/update_order_and_tickets_to_paid.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id FOR UPDATE;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
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

-- Source: database/functions/eshop_orders/update_order_and_tickets_to_sent.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_sent(order_id bigint, ticket_ids bigint[])
RETURNS jsonb
SET search_path = public, extensions AS $$
BEGIN
    PERFORM public.check_order_is_mutable(order_id);

    -- Update the state of the order to 'sent'
    UPDATE eshop.orders
    SET state = 'sent', updated_at = now()
    WHERE id = order_id;

    -- Update the state of the tickets linked to the order and matching ticket_ids,
    -- only if their current state is not 'used'
    UPDATE eshop.tickets
    SET state = 'sent', updated_at = now()
    WHERE id = ANY(ticket_ids)
      AND id IN (SELECT ticket FROM eshop.order_product_ticket WHERE "order" = order_id)
      AND state != 'used';

    -- Check if any rows were updated in the orders table
    IF NOT FOUND THEN
        -- Return a failure message if no orders were updated
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
    ELSE
        -- Add a record to the order history
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        SELECT
            o.id,
            o.data,
            o.state,
            o.price,
            o.currency_code
        FROM eshop.orders o
        WHERE o.id = order_id;

        -- Return a success message with a status code 200
        RETURN jsonb_build_object('code', 200, 'message', 'Order and tickets updated to sent successfully');
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$$ LANGUAGE plpgsql;

-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
BEGIN
    PERFORM public.check_order_is_mutable(order_id);
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

END;
$$;

-- Source: database/functions/eshop_orders/update_order_note_hidden.sql
    CREATE OR REPLACE FUNCTION public.update_order_note_hidden(order_id bigint, new_note_hidden text)
    RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
    DECLARE
        occasion_id bigint;
    BEGIN
        -- Retrieve the occasion_id from the order
        SELECT occasion INTO occasion_id FROM eshop.orders WHERE id = order_id;

        -- Check if occasion_id was successfully retrieved
        IF occasion_id IS NULL THEN
            RETURN jsonb_build_object('code', 404, 'message', 'Order not found or occasion not specified');
        END IF;

        -- Check if the user has the right to edit the given occasion
        IF (get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
            -- Return an error if the user is not authorized
            RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
        END IF;

        PERFORM public.check_order_is_mutable(order_id);

        -- Proceed to update note_hidden if the user is authorized
        UPDATE eshop.orders
        SET note_hidden = new_note_hidden, updated_at = now()
        WHERE id = order_id;

        -- Check if the update was successful
        IF FOUND THEN
            RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
        ELSE
            RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
        END IF;
    END;
    $$ LANGUAGE plpgsql;

-- Source: database/functions/eshop_orders/update_order_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_responses(
    p_order_id BIGINT,
    responses JSONB
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_order_form_id BIGINT;
    v_current_state text;
    v_current_data JSONB;
    v_new_data JSONB;
    v_field_definitions JSONB;
    v_current_fields_map JSONB;
    v_merged_fields_map JSONB;
    v_new_fields_array JSONB;

    v_field_id_text TEXT;
    v_field_type TEXT;
    v_new_value JSONB;

    v_updated_order_state TEXT;
    v_updated_order_price NUMERIC(10, 2);
    v_updated_order_data JSONB;
BEGIN
    -- Fetch the order's current data, occasion, and form ID
    SELECT
        o.data,
        o.occasion,
        o.form,
        o.state
    INTO
        v_current_data,
        v_occasion_id,
        v_order_form_id,
        v_current_state
    FROM eshop.orders o
    WHERE o.id = p_order_id;

    -- Raise an exception if the SELECT INTO returned no row
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Check if the current user has order editing permissions for this occasion
    IF (SELECT get_is_editor_order_on_occasion(v_occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User does not have permission to edit this order.';
    END IF;

    -- Reject the terminal state before form validation, without reversing
    -- the form -> order lock order used by form-field removal.
    IF v_current_state='storno' THEN
        RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
    END IF;

    -- Raise an exception if the order is not linked to a form
    IF v_order_form_id IS NULL THEN
        RAISE EXCEPTION 'Order % has no associated form.', p_order_id;
    END IF;

    -- Coordinate response validation/writes with form saves and field removal.
    PERFORM 1 FROM public.forms WHERE id = v_order_form_id FOR SHARE;
    PERFORM public.check_order_is_mutable(p_order_id);
    SELECT data INTO v_current_data FROM eshop.orders WHERE id=p_order_id;

    -- Fetch all field definitions for this form into a JSONB map { "field_id": "field_type" }
    SELECT jsonb_object_agg(ff.id::text, ff.type)
    INTO v_field_definitions
    FROM public.form_fields ff
    WHERE ff.form = v_order_form_id;

    -- Raise an exception if the form has no fields
    IF v_field_definitions IS NULL THEN
        RAISE EXCEPTION 'No form fields found for form %', v_order_form_id;
    END IF;

    -- FIX: Use a LATERAL join to explicitly reference the columns from jsonb_each,
    -- resolving the "ambiguous column 'value'" error.
    SELECT jsonb_object_agg(je.key, je.value)
    INTO v_current_fields_map
    FROM jsonb_array_elements(v_current_data -> 'fields') AS jae(field_object),
         LATERAL jsonb_each(jae.field_object) AS je(key, value);

    -- Start with the current order data
    v_new_data := v_current_data;

    -- Merge the existing fields map with the new responses. New responses overwrite old ones.
    v_merged_fields_map := COALESCE(v_current_fields_map, '{}'::jsonb) || responses;

    -- Iterate through only the *incoming* responses to handle updates and nulls
    FOR v_field_id_text, v_new_value IN SELECT * FROM jsonb_each(responses)
    LOOP
        -- Get the type of the field being updated
        v_field_type := v_field_definitions ->> v_field_id_text;

        -- Validate that the field ID exists on this order's form
        IF v_field_type IS NULL THEN
            RAISE EXCEPTION 'Field ID % not found on form %', v_field_id_text, v_order_form_id;
        END IF;

        -- Handle null values: remove the key from the top level and from the merged map
        IF v_new_value IS NULL OR v_new_value = 'null'::jsonb THEN

            -- Remove from the map that will build the 'fields' array
            v_merged_fields_map := v_merged_fields_map - v_field_id_text;

            -- Remove top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data - 'name';
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data - 'surname';
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data - 'email';
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data - 'phone';
            END IF;

        -- Handle non-null values: update the top-level keys
        ELSE

            -- Update top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data || jsonb_build_object('name', v_new_value);
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data || jsonb_build_object('surname', v_new_value);
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data || jsonb_build_object('email', v_new_value);
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data || jsonb_build_object('phone', v_new_value);
            END IF;

        END IF;
    END LOOP;

    -- Rebuild the 'fields' array from the (now null-stripped) merged map
    -- It converts { "id": "val" } back to [ {"id": "val"} ]
    SELECT jsonb_agg(jsonb_build_object(key, value))
    INTO v_new_fields_array
    FROM jsonb_each(v_merged_fields_map);

    -- Set the new 'fields' array in the main data object
    v_new_data := jsonb_set(
        v_new_data,
        '{fields}',
        COALESCE(v_new_fields_array, '[]'::jsonb)
    );

    -- Update the order in the database
    UPDATE eshop.orders
    SET
        data = v_new_data,
        updated_at = NOW()
    WHERE
        id = p_order_id
    RETURNING
        state, price, data
    INTO
        v_updated_order_state, v_updated_order_price, v_updated_order_data;

    -- Save the change to the orders_history table
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        p_order_id,
        v_updated_order_state,
        v_updated_order_price,
        v_updated_order_data,
        NOW()
    );

END;
$$;
-- Source: database/functions/eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_paid             numeric;
  v_price            numeric;
  v_new_state        text;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
  v_current_products_for_compare jsonb;
BEGIN
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) decide new state based on money received */
  SELECT COALESCE(pi.paid,0), o.price
    INTO v_paid, v_price
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON o.payment_info = pi.id
   WHERE o.id = v_order_id;

  v_new_state := CASE
                   WHEN v_paid >= v_price AND v_price > 0 THEN 'paid'
                   WHEN v_price <= 0 THEN 'paid'
                   ELSE 'ordered'
                 END;

  IF v_new_state = 'paid' THEN
    IF NOT EXISTS (
      SELECT 1 FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
      WHERE opt."order" = v_order_id AND t.state <> 'sent'
    ) THEN
      v_new_state := 'sent';
    END IF;
  END IF;

  PERFORM public.cancel_order_email_intents(v_order_id);
  UPDATE eshop.orders
     SET email_payment_version=email_payment_version+1, state      = v_new_state,
         updated_at = now()
   WHERE id = v_order_id;

  -- A price edit can pay off the order without the usual paid transition.
  -- Email acceptance only projects paid tickets to sent, so keep eligible
  -- tickets in step with the order before creating its delivery intent.
  IF v_new_state = 'paid' THEN
    UPDATE eshop.tickets t
       SET state = 'paid', updated_at = now()
      FROM eshop.order_product_ticket opt
     WHERE opt.ticket = t.id AND opt."order" = v_order_id
       AND t.state IN ('ordered', 'expired');
  END IF;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM apply_allocations(v_order_id);
  PERFORM public.enqueue_paid_order_tickets(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_new_state,
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

-- Source: database/functions/eshop_orders/update_ticket_to_unused_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_unused_ws(
    ticket_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    updated_count integer;
BEGIN
    SELECT occasion
    INTO STRICT occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

    PERFORM public.check_ticket_is_mutable(ticket_id);

    UPDATE eshop.tickets
    SET
        -- `sent` is the canonical unused state that can be scanned again.
        state = 'sent',
        updated_at = now()
    WHERE id = ticket_id
      AND state = 'used';

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    IF updated_count <> 1 THEN
        RAISE EXCEPTION 'Ticket % is not used.', ticket_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_ticket_to_unused_ws(bigint)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_ticket_to_unused_ws(bigint)
TO authenticated, service_role;

-- Source: database/functions/eshop_orders/update_ticket_to_used.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_used(
    ticket_id bigint,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
    expected_scan_code text;
BEGIN
    -- 1. Validate Ticket Existence
    IF NOT EXISTS (
        SELECT 1 FROM eshop.tickets WHERE id = ticket_id
    ) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Ticket not found.'
        );
    END IF;

    -- 2. Retrieve Associated Occasion ID AND Current State
    SELECT occasion, state
    INTO occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- Check if occasion_id is present (Integrity check)
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion associated with ticket not found.'
        );
    END IF;

    -- 2a. Validate Ticket State (New Check)
    IF current_state = 'used' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket has already been used.'
        );
    ELSIF current_state = 'storno' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket is cancelled (storno).'
        );
    END IF;

    -- 3. Retrieve Expected Scan Code from occasions_hidden via foreign key
    SELECT oh.secret
    INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    -- Check if scan_code is defined
    IF expected_scan_code IS NULL THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Scan code not defined for occasion.'
        );
    END IF;

    -- 4. Validate Provided Scan Code
    IF scan_code IS DISTINCT FROM expected_scan_code THEN
        RETURN jsonb_build_object(
            'code', 401,
            'message', 'Scan code is not correct.'
        );
    END IF;

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- 5. Update Ticket State to 'used' AND update timestamp
    UPDATE eshop.tickets
    SET
        state = 'used',
        updated_at = now()
    WHERE id = ticket_id;

    -- 6. Return Success Message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Ticket state updated to used successfully.'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

-- Source: database/functions/eshop_orders/update_ticket_to_used_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_used_ws(
    ticket_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- 1. Retrieve the occasion ID and State from the ticket.
    -- If the ticket does not exist, this will raise a NO_DATA_FOUND exception (due to STRICT).
    SELECT occasion, state
    INTO STRICT occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- 1a. Check State Validity (New Check)
    IF current_state = 'used' THEN
        RAISE EXCEPTION 'Ticket % is already used.', ticket_id;
    ELSIF current_state = 'storno' THEN
        RAISE EXCEPTION 'Ticket % is cancelled (storno).', ticket_id;
    END IF;

    -- 2. Check if the current user has editor permissions for the occasion.
    -- This function will raise an exception if the user is not an editor.
    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

    PERFORM public.check_ticket_is_mutable(ticket_id);

    -- 3. Update the ticket state to 'used' AND update timestamp.
    -- This is only reached if the previous checks pass without raising an exception.
    UPDATE eshop.tickets
    SET
        state = 'used',
        updated_at = now()
    WHERE id = ticket_id;
END;
$$;
-- Source: database/functions/eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
BEGIN
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    UPDATE eshop.payment_info pi SET
      paid = COALESCE((SELECT sum(t.amount) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type IS DISTINCT FROM 'return'), 0),
      returned = COALESCE((SELECT abs(sum(t.amount)) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type = 'return'), 0)
    WHERE pi.id = v_old_payment_info_id;
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    UPDATE eshop.payment_info pi SET
      paid = COALESCE((SELECT sum(t.amount) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type IS DISTINCT FROM 'return'), 0),
      returned = COALESCE((SELECT abs(sum(t.amount)) FROM eshop.transactions t
        WHERE t.payment_info = pi.id AND t.transaction_type = 'return'), 0)
    WHERE pi.id = p_payment_info_id;
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- Source: database/functions/eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint;
  v_transactions jsonb;
  v_users jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  -- Fetch transactions
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
  INTO v_transactions
  FROM eshop.transactions t
  JOIN eshop.orders o ON t.payment_info = o.payment_info
  WHERE o.id = order_id;

  -- Fetch unique users associated with these transactions
  SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
  INTO v_users
  FROM public.user_info u
  WHERE u.id IN (
      SELECT DISTINCT t.created_by
      FROM eshop.transactions t
      JOIN eshop.orders o ON t.payment_info = o.payment_info
      WHERE o.id = order_id AND t.created_by IS NOT NULL
  );

  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', v_transactions,
      'users', v_users
    )
    FROM eshop.orders o
    WHERE o.id = order_id
  );
END;
$$;
