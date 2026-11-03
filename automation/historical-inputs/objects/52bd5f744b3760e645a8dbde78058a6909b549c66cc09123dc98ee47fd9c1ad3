CREATE OR REPLACE FUNCTION assign_spot_to_resource(p_spot_id BIGINT, p_inventory_context_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_pool_id BIGINT;
    v_resource_id BIGINT;
    v_is_spot_assigned BOOLEAN;
BEGIN
    -- 1. Check if the spot is already assigned to prevent overwriting.
    SELECT resource IS NOT NULL INTO v_is_spot_assigned
    FROM eshop.spots
    WHERE id = p_spot_id;

    IF v_is_spot_assigned THEN
        RETURN; -- Spot already has a resource, so we do nothing.
    END IF;

    -- 2. Get the parent inventory_pool from the given context.
    SELECT inventory_pool INTO v_pool_id
    FROM public.inventory_contexts
    WHERE id = p_inventory_context_id;

    -- If the context or pool doesn't exist, we can't proceed.
    IF v_pool_id IS NULL THEN
        RETURN;
    END IF;

    -- 3. Find the first available resource within the pool for the given context.
    --    A resource is "available" if its count of assigned spots is less than its capacity.
    SELECT res.id INTO v_resource_id
    FROM public.resources res
    LEFT JOIN (
        -- Subquery to count assigned spots per resource for this specific context
        SELECT resource as resource_id, COUNT(*) as assigned_spots
        FROM eshop.spots
        WHERE inventory_context = p_inventory_context_id AND resource IS NOT NULL
        GROUP BY resource_id
    ) spot_counts ON res.id = spot_counts.resource_id
    WHERE res.inventory_pool = v_pool_id
    -- Check if the resource's capacity is not yet filled
    AND (spot_counts.assigned_spots IS NULL OR spot_counts.assigned_spots < res.capacity)
    ORDER BY res.id -- Order consistently to always pick the "first" available one
    LIMIT 1;

    -- 4. If an available resource was found, update the spot to link it.
    IF v_resource_id IS NOT NULL THEN
        UPDATE eshop.spots
        SET resource = v_resource_id,
            updated_at = now()
        WHERE id = p_spot_id;
    END IF;
END;
$$;