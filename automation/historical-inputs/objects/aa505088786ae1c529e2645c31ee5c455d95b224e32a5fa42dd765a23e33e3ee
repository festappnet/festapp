CREATE OR REPLACE FUNCTION get_spot_management_bundle(p_inventory_pool_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_spots_data jsonb;
    v_inventory_contexts_data jsonb;
    v_resources_data jsonb;
    v_resource_slots_data jsonb;
    v_order_product_tickets_data jsonb;
    v_orders_data jsonb;
    result jsonb;
BEGIN
    -- Get occasion for permission check from the inventory pool
    SELECT occasion INTO v_occasion_id
    FROM public.inventory_pools
    WHERE id = p_inventory_pool_id;

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Inventory Pool not found.';
    END IF;

    -- Permission check (assuming a similar function exists for order view)
    IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Aggregate all inventory_contexts for the pool
    SELECT COALESCE(jsonb_agg(to_jsonb(ic) ORDER BY ic.block_date), '[]'::jsonb)
    INTO v_inventory_contexts_data
    FROM public.inventory_contexts ic
    WHERE ic.inventory_pool = p_inventory_pool_id;

    -- Aggregate all spots that belong to any context within the specified pool
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.id), '[]'::jsonb)
    INTO v_spots_data
    FROM eshop.spots s
    WHERE s.inventory_context IN (
        SELECT id FROM public.inventory_contexts WHERE inventory_pool = p_inventory_pool_id
    );

    -- Aggregate all resources for the pool
    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.title), '[]'::jsonb)
    INTO v_resources_data
    FROM public.resources r
    WHERE r.inventory_pool = p_inventory_pool_id;

    -- Aggregate all resource slots for all resources within the pool
    SELECT COALESCE(jsonb_agg(to_jsonb(rs) ORDER BY rs.id), '[]'::jsonb)
    INTO v_resource_slots_data
    FROM public.resource_slots rs
    WHERE rs.resource IN (
        SELECT id FROM public.resources WHERE inventory_pool = p_inventory_pool_id
    );

    -- NEW: Aggregate all order_product_tickets related to the spots in the pool
    SELECT COALESCE(jsonb_agg(to_jsonb(opt) ORDER BY opt.id), '[]'::jsonb)
    INTO v_order_product_tickets_data
    FROM eshop.order_product_ticket opt
    WHERE opt.id IN (
        SELECT DISTINCT s.order_product_ticket
        FROM eshop.spots s
        WHERE s.inventory_context IN (
            SELECT id FROM public.inventory_contexts WHERE inventory_pool = p_inventory_pool_id
        ) AND s.order_product_ticket IS NOT NULL
    );

    -- NEW: Aggregate all orders related to those order_product_tickets
    SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.id), '[]'::jsonb)
    INTO v_orders_data
    FROM eshop.orders o
    WHERE o.id IN (
        SELECT DISTINCT opt."order"
        FROM eshop.order_product_ticket opt
        WHERE opt.id IN (
            SELECT DISTINCT s.order_product_ticket
            FROM eshop.spots s
            WHERE s.inventory_context IN (
                SELECT id FROM public.inventory_contexts WHERE inventory_pool = p_inventory_pool_id
            ) AND s.order_product_ticket IS NOT NULL
        ) AND opt."order" IS NOT NULL
    );

    -- Construct the final bundle object with the new data
    result := jsonb_build_object(
        'spots', v_spots_data,
        'inventory_contexts', v_inventory_contexts_data,
        'resources', v_resources_data,
        'resource_slots', v_resource_slots_data,
        'order_product_tickets', v_order_product_tickets_data, -- Added
        'orders', v_orders_data  -- Added
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        -- A more robust error handling for production
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;