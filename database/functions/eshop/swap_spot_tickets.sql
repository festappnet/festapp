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