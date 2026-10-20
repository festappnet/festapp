CREATE OR REPLACE FUNCTION public.adjust_spot_capacity_for_pool(p_inventory_pool_id bigint)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_context RECORD;
    v_resource RECORD;
    v_spots_to_create BIGINT;
    v_spots_to_delete BIGINT;
    v_booked_spots_count BIGINT;
    v_total_spots_count BIGINT;
    v_deletable_spot_ids BIGINT[];
    v_net_change INTEGER := 0;
    v_pool_occasion_id BIGINT;
    v_total_pool_capacity BIGINT;
BEGIN
    PERFORM 1 FROM public.inventory_pools WHERE id=p_inventory_pool_id FOR UPDATE;
    PERFORM 1 FROM public.inventory_contexts WHERE inventory_pool=p_inventory_pool_id ORDER BY id FOR UPDATE;
    PERFORM 1 FROM eshop.spots WHERE inventory_context IN(SELECT id FROM public.inventory_contexts WHERE inventory_pool=p_inventory_pool_id) ORDER BY id FOR UPDATE;
    -- Step 0: Validate input and get occasion ID.
    SELECT occasion INTO v_pool_occasion_id FROM public.inventory_pools WHERE id = p_inventory_pool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'P001', 'message', 'Inventory pool with ID ' || p_inventory_pool_id || ' not found.')::text;
    END IF;

    -- Calculate the total capacity for the entire pool once. This is the target for the generic pool.
    SELECT COALESCE(SUM(capacity), 0) INTO v_total_pool_capacity
    FROM public.resources
    WHERE inventory_pool = p_inventory_pool_id;

    -- =================================================================
    -- Main Synchronization Loop (per context)
    -- =================================================================
    FOR v_context IN
        SELECT id FROM public.inventory_contexts WHERE inventory_pool = p_inventory_pool_id
    LOOP
        -- =============================================================
        -- Part A: Cleanup of RESOURCE-SPECIFIC Spots for this context
        -- =============================================================
        FOR v_resource IN
            SELECT id, capacity FROM public.resources WHERE inventory_pool = p_inventory_pool_id
        LOOP
            -- Count spots for the current resource WITHIN the current context.
            SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND resource = v_resource.id;
            SELECT count(*) INTO v_booked_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND resource = v_resource.id AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()));

            IF v_booked_spots_count > v_resource.capacity THEN
                RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'S001',
                    'message', 'Overbooking detected for specific resource. Manual intervention required.',
                    'details', jsonb_build_object(
                        'contextId', v_context.id,
                        'resourceId', v_resource.id,
                        'bookedSpots', v_booked_spots_count,
                        'capacity', v_resource.capacity
                    )
                )::text;
            END IF;

            IF v_total_spots_count > v_resource.capacity THEN
                v_spots_to_delete := v_total_spots_count - v_resource.capacity;
                SELECT array_agg(id) INTO v_deletable_spot_ids FROM (
                    SELECT id FROM eshop.spots
                    WHERE inventory_context = v_context.id AND resource = v_resource.id AND order_product_ticket IS NULL AND (secret IS NULL OR secret_expiration_time<=clock_timestamp())
                    ORDER BY created_at DESC
                    LIMIT v_spots_to_delete
                ) AS sub;

                IF coalesce(cardinality(v_deletable_spot_ids),0) < v_spots_to_delete THEN
                     RAISE EXCEPTION '%', jsonb_build_object(
                        'code', 'S002',
                        'message', 'Cannot delete excess resource-specific spots. Deletion would require removing a booked spot.',
                        'details', jsonb_build_object(
                            'contextId', v_context.id,
                            'resourceId', v_resource.id
                        )
                    )::text;
                END IF;

                DELETE FROM eshop.spots WHERE id = ANY(v_deletable_spot_ids);
                v_net_change := v_net_change - v_spots_to_delete;
            END IF;
        END LOOP;

        -- =============================================================
        -- Part B: Management of GENERIC Spot Pool for this context
        -- =============================================================
        -- Count total and booked spots for the GENERIC pool (resource IS NULL) within the current context.
        SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id;
        SELECT count(*) INTO v_booked_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()));

        IF v_booked_spots_count > v_total_pool_capacity THEN
            RAISE EXCEPTION '%', jsonb_build_object(
                'code', 'S003',
                'message', 'Overbooking detected for generic pool. Manual intervention required.',
                'details', jsonb_build_object(
                    'contextId', v_context.id,
                    'bookedSpots', v_booked_spots_count,
                    'capacity', v_total_pool_capacity
                )
            )::text;
        END IF;

        -- DELETION of generic spots
        IF v_total_spots_count > v_total_pool_capacity THEN
            v_spots_to_delete := v_total_spots_count - v_total_pool_capacity;
            SELECT array_agg(id) INTO v_deletable_spot_ids FROM (
                SELECT id FROM eshop.spots
                WHERE inventory_context = v_context.id AND resource IS NULL AND order_product_ticket IS NULL AND (secret IS NULL OR secret_expiration_time<=clock_timestamp())
                ORDER BY created_at DESC
                LIMIT v_spots_to_delete
            ) AS sub;

            IF coalesce(cardinality(v_deletable_spot_ids),0) < v_spots_to_delete THEN
                 RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'S004',
                    'message', 'Cannot delete excess generic spots. Deletion would require removing a booked spot.',
                    'details', jsonb_build_object(
                        'contextId', v_context.id
                    )
                )::text;
            END IF;

            DELETE FROM eshop.spots WHERE id = ANY(v_deletable_spot_ids);
            v_net_change := v_net_change - v_spots_to_delete;
        END IF;

        -- CREATION of generic spots
        -- Recount after potential deletion to get the current number.
        SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id;

        IF v_total_spots_count < v_total_pool_capacity THEN
            v_spots_to_create := v_total_pool_capacity - v_total_spots_count;

            -- Insert the required number of new generic spots.
            -- Per instructions, ONLY occasion and inventory_context are set.
            INSERT INTO eshop.spots (occasion, inventory_context)
            SELECT
                v_pool_occasion_id,
                v_context.id
            FROM generate_series(1, v_spots_to_create);

            v_net_change := v_net_change + v_spots_to_create;
        END IF;
    END LOOP;

    RETURN v_net_change;

END;
$$;
REVOKE ALL ON FUNCTION public.adjust_spot_capacity_for_pool(bigint) FROM PUBLIC,anon,authenticated,service_role;
