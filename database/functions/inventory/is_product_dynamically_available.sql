CREATE OR REPLACE FUNCTION is_product_dynamically_available(p_product_id BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE
SET search_path = public, extensions AS $$
DECLARE
    context_record RECORD;
    occupied_spots BIGINT;
    total_spots BIGINT;
BEGIN
    -- If a product is not linked to any inventory contexts,
    -- it is considered available by default.
    IF NOT EXISTS (SELECT 1 FROM eshop.product_inventory_contexts WHERE product = p_product_id) THEN
        RETURN TRUE;
    END IF;

    -- Iterate through each inventory context required by the product.
    FOR context_record IN
        SELECT
            pic.inventory_context,
            pic.quantity,
            ip.sellable_capacity
        FROM eshop.product_inventory_contexts pic
        JOIN public.inventory_contexts ic ON pic.inventory_context = ic.id
        JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
        WHERE pic.product = p_product_id
    LOOP
        -- Calculate the total number of physical spots available for the context.
        SELECT count(*)
        INTO total_spots
        FROM eshop.spots
        WHERE inventory_context = context_record.inventory_context;

        -- Calculate the number of spots that are currently occupied.
        -- A spot is considered occupied if it's assigned to an order (opt is not null)
        -- or if it has been temporarily reserved via a secret.
        SELECT count(*)
        INTO occupied_spots
        FROM eshop.spots
        WHERE inventory_context = context_record.inventory_context
          AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time > now()));

        -- Check 1: Ensure purchasing does not exceed the total physical spots.
        IF (occupied_spots + context_record.quantity) > total_spots THEN
            RETURN FALSE;
        END IF;

        -- Check 2: If a commercial sellable capacity is set on the pool,
        -- ensure purchasing does not exceed this limit.
        IF context_record.sellable_capacity IS NOT NULL AND (occupied_spots + context_record.quantity) > context_record.sellable_capacity THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- If all checks for all contexts pass, the product is available for purchase.
    RETURN TRUE;
END;
$$;