CREATE OR REPLACE FUNCTION apply_allocations(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_order_state TEXT;
    v_item_to_allocate RECORD;
    v_existing_spot_count INT;
    v_spots_to_claim INT;
    v_available_spot_id BIGINT;
    v_occasion_id BIGINT;
    v_spots_to_disallocate BIGINT[];
    v_occasion_features JSONB;
    v_is_blueprint_enabled BOOLEAN;
BEGIN
    PERFORM public.lock_ticket_order_products_internal(p_order_id);
    -- Initial check for the order's state.
    SELECT state, occasion INTO v_order_state, v_occasion_id
    FROM eshop.orders
    WHERE id = p_order_id;

    SELECT features INTO v_occasion_features FROM public.occasions WHERE id = v_occasion_id;
    v_is_blueprint_enabled := jsonb_path_exists(v_occasion_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)');

    -- If the order is not found, raise a structured exception.
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'A001', 'message', 'Order with ID ' || p_order_id || ' not found.')::text;
    END IF;

    -- If the order state is 'storno', disallocate all spots and exit.
    IF v_order_state = 'storno' THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = NULL, updated_at = now()
        WHERE order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id);
        RETURN;
    END IF;

    -- Disallocate spots that are no longer required by the order.
    WITH required_spots AS (
        SELECT opt.id as order_product_ticket_id, pic.inventory_context as inventory_context_id, generate_series(1, pic.quantity)
        FROM eshop.order_product_ticket opt
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE opt."order" = p_order_id
    ),
    current_spots AS (
        SELECT s.id, s.order_product_ticket, s.inventory_context
        FROM eshop.spots s
        WHERE s.order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id)
    )
    SELECT array_agg(cs.id)
    INTO v_spots_to_disallocate
    FROM current_spots cs
    LEFT JOIN required_spots rs ON cs.order_product_ticket = rs.order_product_ticket_id AND cs.inventory_context = rs.inventory_context_id
    JOIN eshop.order_product_ticket opt ON cs.order_product_ticket = opt.id
    JOIN eshop.products p ON opt.product = p.id
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE rs.order_product_ticket_id IS NULL
      AND NOT (v_is_blueprint_enabled AND pt.type = 'spot');

    IF v_spots_to_disallocate IS NOT NULL AND array_length(v_spots_to_disallocate, 1) > 0 THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = NULL, updated_at = now()
        WHERE id = ANY(v_spots_to_disallocate);
    END IF;

    -- Loop through each product in the order that requires an inventory spot to allocate new spots.
    FOR v_item_to_allocate IN
        SELECT
            opt.id AS order_product_ticket_id,
            opt.product AS product_id,
            pic.inventory_context AS inventory_context_id,
            pic.quantity AS required_quantity
        FROM eshop.orders o
        JOIN eshop.order_product_ticket opt ON o.id = opt."order"
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE o.id = p_order_id
    LOOP
        -- Check for existing spots for this specific order item AND inventory context.
        SELECT COUNT(*)
        INTO v_existing_spot_count
        FROM eshop.spots s
        WHERE s.order_product_ticket = v_item_to_allocate.order_product_ticket_id
          AND s.inventory_context = v_item_to_allocate.inventory_context_id;

        -- Calculate exactly how many spots are missing.
        v_spots_to_claim := v_item_to_allocate.required_quantity - v_existing_spot_count;

        IF v_spots_to_claim <= 0 THEN
            CONTINUE;
        END IF;

        IF EXISTS(SELECT 1 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
          WHERE ic.id=v_item_to_allocate.inventory_context_id AND ip.sellable_capacity IS NOT NULL AND
          (SELECT count(*) FROM eshop.spots s WHERE s.inventory_context=ic.id AND (s.order_product_ticket IS NOT NULL OR
            (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())))+v_spots_to_claim>ip.sellable_capacity) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1017,'errorCode','PRODUCT_CAPACITY_EXCEEDED','productId',v_item_to_allocate.product_id)::text;
        END IF;
        -- This loop runs precisely the number of times needed to claim the required spots.
        FOR i IN 1..v_spots_to_claim LOOP
            v_available_spot_id := NULL;

            -- Find an available spot. A spot is available only if it's unassigned.
            WITH available_spot_cte AS (
                SELECT s.id
                FROM eshop.spots s
                WHERE s.inventory_context = v_item_to_allocate.inventory_context_id
                  AND s.order_product_ticket IS NULL
                  AND (s.secret IS NULL OR s.secret_expiration_time IS NULL OR s.secret_expiration_time<=clock_timestamp())
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
            SELECT id INTO v_available_spot_id FROM available_spot_cte;

            -- If no available spot is found, we must fail with a structured error.
            IF v_available_spot_id IS NULL THEN
                 DECLARE
                    product_data RECORD;
                 BEGIN
                    -- Fetch the details of the product that could not be allocated.
                    SELECT
                        p.id,
                        p.title,
                        p.description,
                        p.price,
                        pt.type,
                        pt.title as type_title,
                        p.currency_code
                    INTO product_data
                    FROM eshop.products p
                    LEFT JOIN eshop.product_types pt ON p.product_type = pt.id
                    WHERE p.id = v_item_to_allocate.product_id;

                    -- Raise the specific overbooked exception with product details.
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1017,
                        'message', 'Product is overbooked',
                        'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                            'id', product_data.id,
                            'title', product_data.title,
                            'description', product_data.description,
                            'price', product_data.price,
                            'type', product_data.type,
                            'type_title', product_data.type_title,
                            'currency_code', product_data.currency_code
                        ))
                    )::TEXT;
                 END;
            END IF;

            -- Claim the found spot.
            UPDATE eshop.spots
            SET
                order_product_ticket = v_item_to_allocate.order_product_ticket_id,
                occasion = v_occasion_id,
                state = 'ordered',
                secret = NULL,
                secret_expiration_time = NULL,
                updated_at = now()
            WHERE id = v_available_spot_id;

            -- After claiming the spot, check if it should be automatically assigned to a resource.
            DECLARE
                v_is_auto_assign BOOLEAN;
            BEGIN
                -- Get the auto-assignment setting from the pool associated with the context.
                SELECT (ip.data->>'is_auto_resource_assignment')::boolean
                INTO v_is_auto_assign
                FROM public.inventory_contexts ic
                JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
                WHERE ic.id = v_item_to_allocate.inventory_context_id;

                -- If auto-assignment is enabled for this pool, call the assignment function.
                IF v_is_auto_assign IS TRUE THEN
                    PERFORM assign_spot_to_resource(v_available_spot_id, v_item_to_allocate.inventory_context_id);
                END IF;
            END;

        END LOOP;
    END LOOP;
    PERFORM public.notification_center_order_capacity_internal(p_order_id);
END;
$$;