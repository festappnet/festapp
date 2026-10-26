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
    settings jsonb;
BEGIN
    -- Get occasion for permission check from the inventory pool
    SELECT occasion INTO v_occasion_id
    FROM public.inventory_pools
    WHERE id = p_inventory_pool_id FOR SHARE;

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Inventory Pool not found.';
    END IF;

    -- Permission check
    IF public.can_read_orders(v_occasion_id) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Current UI and MCP share the pool/context and resource projections.
    settings:=public.get_inventory_pool_settings_data_internal(p_inventory_pool_id);
    v_pool_data:=settings->'pool';
    v_contexts_data:=settings->'contexts';
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE o.id=v_occasion_id;
    v_resources_data:=public.get_inventory_resource_rows_internal(v_occasion_id,
      ARRAY(SELECT id FROM public.resources WHERE inventory_pool=p_inventory_pool_id),true);

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

    IF public.can_read_orders(v_occasion_id) IS DISTINCT FROM TRUE THEN
        RAISE insufficient_privilege USING MESSAGE='occasion order viewer required';
    END IF;
    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;
