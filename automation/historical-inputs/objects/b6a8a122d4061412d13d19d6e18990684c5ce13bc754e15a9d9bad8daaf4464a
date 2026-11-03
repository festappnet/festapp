CREATE OR REPLACE FUNCTION get_user_inventory()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    -- 1. Get the current user's ID.
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User not authenticated. Cannot retrieve inventory.';
    END IF;

    -- 2. Create a definitive list of the user's tickets and associated products.
    -- This is the absolute source of truth for which products the user owns.
    WITH user_ticket_products AS (
        SELECT
            opt.id AS order_product_ticket_id,
            opt.product AS product_id
        FROM public.occasion_users ou
        JOIN eshop.order_product_ticket opt ON ou.ticket = opt.ticket
        WHERE ou."user" = v_user_id
          AND ou.ticket IS NOT NULL
          AND opt.product IS NOT NULL
    ),

    -- 3. Find the user's assigned spots and their context ONLY for the tickets identified above.
    user_assigned_inventory AS (
        SELECT
            s.id AS id, -- Renamed to 'id' to match the provided CTE
            s.title AS title, -- Renamed to 'title'
            s.state AS state, -- Renamed to 'state'
            s.resource_slot AS resource_slot, -- Renamed to 'resource_slot'
            s.resource AS resource, -- Renamed to 'resource'
            s.inventory_context AS inventory_context, -- Renamed to 'inventory_context'
            ic.inventory_pool AS inventory_pool, -- Renamed to 'inventory_pool'
            utp.product_id
        FROM eshop.spots s
        JOIN user_ticket_products utp ON s.order_product_ticket = utp.order_product_ticket_id
        JOIN public.inventory_contexts ic ON s.inventory_context = ic.id
    ),

    -- 4. Fetch the full data for each entity, strictly filtering by the IDs gathered above.

    -- MODIFIED: Fetches products STRICTLY from the user's tickets.
    products_json AS (
        SELECT
            jsonb_object_agg(p.id, jsonb_build_object(
                'id', p.id, 'title', p.title, 'description', p.description, 'price', p.price, 'data', p.data,
                'product_type', p.product_type, 'occasion', p.occasion, 'is_hidden', p.is_hidden,
                'currency_code', p.currency_code, 'order', p."order",
                'maximum', p.maximum, 'is_dynamically_available', is_product_dynamically_available(p.id)
            )) AS data
        FROM eshop.products p
        WHERE p.id IN (SELECT DISTINCT product_id FROM user_ticket_products)
    ),

    -- MODIFIED: Fetches PIC records using a precise (context, product) match from the user's assigned spots.
    -- This is the most minimal possible query for this data.
    product_inventory_contexts_json AS (
        SELECT jsonb_object_agg(pic.id, to_jsonb(pic)) AS data
        FROM eshop.product_inventory_contexts pic
        WHERE (pic.inventory_context, pic.product) IN (
            SELECT DISTINCT inventory_context, product_id FROM user_assigned_inventory -- Updated column name
        )
    ),

    -- Build the JSON for contexts, ensuring the 'spots' array is correctly populated.
    contexts_json AS (
        SELECT
            jsonb_object_agg(ic.id, jsonb_build_object(
                'id', ic.id, 'order', ic."order", 'block_date', ic.block_date, 'title', ic.title,
                'data', ic.data, 'inventory_pool', ic.inventory_pool,
                'spots', (
                    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb) -- Updated column name
                    FROM (
                        SELECT uai.id, uai.title, uai.state, uai.resource_slot, uai.resource, uai.product_id -- Updated column names
                        FROM user_assigned_inventory uai
                        WHERE uai.inventory_context = ic.id -- Updated column name
                    ) t
                )
            )) AS data
        FROM public.inventory_contexts ic
        WHERE ic.id IN (SELECT DISTINCT inventory_context FROM user_assigned_inventory) -- Updated column name
    ),

    -- Pools, Places, and Resources are filtered based on the derived inventory.
    pools_json AS (
        SELECT jsonb_object_agg(p.id, jsonb_strip_nulls(jsonb_build_object(
            'id', p.id, 'data', p.data, 'title', p.title, 'description', p.description,
            'type', p.type, 'sellable_capacity', p.sellable_capacity, 'occasion', p.occasion
        ))) AS data
        FROM public.inventory_pools p
        WHERE p.id IN (SELECT DISTINCT inventory_pool FROM user_assigned_inventory) -- Updated column name
    ),
    places_json AS (
        SELECT jsonb_object_agg(pl.id, to_jsonb(pl)) AS data
        FROM public.places pl
        JOIN (
            SELECT DISTINCT (ip.data->>'place_id')::bigint AS id
            FROM public.inventory_pools ip
            WHERE ip.id IN (SELECT DISTINCT inventory_pool FROM user_assigned_inventory) -- Updated column name
              AND ip.data ? 'place_id' AND ip.data->>'place_id' IS NOT NULL
        ) AS place_ids ON pl.id = place_ids.id
    ),
    resources_json AS (
        SELECT jsonb_object_agg(r.id, to_jsonb(r)) AS data
        FROM public.resources r
        WHERE r.id IN (SELECT DISTINCT resource FROM user_assigned_inventory WHERE resource IS NOT NULL) -- Updated column name
    )

    -- 5. Assemble the final, minimal JSON object.
    SELECT jsonb_build_object(
        'inventory_contexts', COALESCE((SELECT data FROM contexts_json), '{}'::jsonb),
        'inventory_pools', COALESCE((SELECT data FROM pools_json), '{}'::jsonb),
        'resources', COALESCE((SELECT data FROM resources_json), '{}'::jsonb),
        'products', COALESCE((SELECT data FROM products_json), '{}'::jsonb),
        'product_inventory_contexts', COALESCE((SELECT data FROM product_inventory_contexts_json), '{}'::jsonb),
        'places', COALESCE((SELECT data FROM places_json), '{}'::jsonb)
    )
    INTO v_result;

    -- 6. Return the final object.
    RETURN v_result;

END;
$$;