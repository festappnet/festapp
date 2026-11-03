CREATE OR REPLACE FUNCTION public.get_inventory_pool_bundle(p_inventory_pool_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_pool_data jsonb;
    v_occasion_data jsonb;
    v_resources_data jsonb;
    v_contexts_data jsonb;
    v_places_data jsonb;
    v_products_data jsonb;
    v_product_inventory_contexts_data jsonb; -- New variable for the join table data
    result jsonb;
BEGIN
    -- Get occasion for permission check from the inventory pool
    SELECT occasion INTO v_occasion_id
    FROM public.inventory_pools
    WHERE id = p_inventory_pool_id;

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Inventory Pool not found.';
    END IF;

    -- Permission check
    IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the main inventory pool details
    SELECT to_jsonb(ip) INTO v_pool_data FROM public.inventory_pools ip WHERE ip.id = p_inventory_pool_id;

    -- Get the full occasion details
    SELECT to_jsonb(o) INTO v_occasion_data
    FROM public.occasions o
    WHERE o.id = v_occasion_id;

    -- Aggregate all resources for the pool, and for each resource, aggregate its slots.
    SELECT COALESCE(jsonb_agg(resources_with_slots), '[]'::jsonb)
    INTO v_resources_data
    FROM (
        SELECT
            jsonb_build_object(
                'id', r.id,
                'created_at', r.created_at,
                'updated_at', r.updated_at,
                'title', r.title,
                'description', r.description,
                'capacity', r.capacity,
                'booking_rules', r.booking_rules,
                'inventory_pool', r.inventory_pool,
                'place', r.place,
                'occasion', r.occasion,
                'unit', r.unit,
                'data', r.data,
                'aggregate_version', COALESCE((
                    SELECT av.version
                    FROM public.client_aggregate_versions av
                    WHERE av.aggregate_type = 'resource'
                      AND av.scope_type = 'occasion'
                      AND av.scope_id = v_occasion_id
                      AND av.aggregate_id = r.id::text
                ), 0),
                'slots', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'id', rs.id,
                            'resource', rs.resource,
                            'title', rs.title,
                            'data', rs.data
                        ) ORDER BY rs.id
                    ), '[]'::jsonb)
                    FROM public.resource_slots rs
                    WHERE rs.resource = r.id
                )
            ) AS resources_with_slots
        FROM public.resources r
        WHERE r.inventory_pool = p_inventory_pool_id
        ORDER BY r.title
    ) AS subquery;

    -- Aggregate all inventory contexts for the pool, sorted by the 'order' field
    SELECT COALESCE(jsonb_agg(to_jsonb(ic) ORDER BY ic.order), '[]'::jsonb)
    INTO v_contexts_data
    FROM public.inventory_contexts ic
    WHERE ic.inventory_pool = p_inventory_pool_id;

    -- Aggregate all places for the occasion
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.order), '[]'::jsonb)
    INTO v_places_data
    FROM public.places p
    WHERE p.occasion = v_occasion_id;

    -- MODIFICATION START
    -- Aggregate products that are linked to the inventory contexts of this specific pool.
    SELECT COALESCE(jsonb_agg(to_jsonb(pr)), '[]'::jsonb)
    INTO v_products_data
    FROM (
        SELECT DISTINCT pr.*
        FROM eshop.products pr
        JOIN eshop.product_inventory_contexts pic ON pr.id = pic.product
        JOIN public.inventory_contexts ic ON pic.inventory_context = ic.id
        WHERE ic.inventory_pool = p_inventory_pool_id
    ) pr;

    -- Aggregate the product <-> inventory_context join table entries for this pool's contexts.
    SELECT COALESCE(jsonb_agg(to_jsonb(pic)), '[]'::jsonb)
    INTO v_product_inventory_contexts_data
    FROM eshop.product_inventory_contexts pic
    JOIN public.inventory_contexts ic ON pic.inventory_context = ic.id
    WHERE ic.inventory_pool = p_inventory_pool_id;

    -- Construct the final bundle object, now including context-specific products and the join table data.
    result := jsonb_build_object(
        'pool', v_pool_data,
        'occasion', v_occasion_data,
        'resources', v_resources_data,
        'contexts', v_contexts_data,
        'places', v_places_data,
        'products', v_products_data,
        'product_inventory_contexts', v_product_inventory_contexts_data
        ,'aggregate_version', COALESCE((SELECT av.version
          FROM public.client_aggregate_versions av
          WHERE av.aggregate_type='inventory_pool' AND av.scope_type='occasion'
            AND av.scope_id=v_occasion_id
            AND av.aggregate_id=p_inventory_pool_id::text),0)
    );
    -- MODIFICATION END

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;
