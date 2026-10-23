-- Retained scan_ticket_v2 response contract; technical authentication delegates
-- to the same live proof resolver as session bootstrap and participant lookup.
CREATE OR REPLACE FUNCTION public.scan_ticket_v2(scanned_id text, scanned_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    ticket_row RECORD;
    order_json JSONB;
    products_json JSONB;
    spot_json JSONB;
    inventory_json JSONB; -- New variable for the inventory bundle
    order_id BIGINT;
    occasion_id BIGINT;
    expected_scan_code TEXT;
BEGIN
    -- 1. Check if the ticket exists
    SELECT *
      INTO ticket_row
    FROM eshop.tickets
    WHERE ticket_symbol = scanned_id
    LIMIT 1;

    IF ticket_row IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket not found');
    END IF;

    -- 2. Retrieve the associated order ID
    SELECT opt."order" INTO order_id
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ticket_row.id
    LIMIT 1;

    IF order_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order for ticket not found');
    END IF;

    -- 3. Retrieve the occasion ID from the order
    SELECT o.occasion INTO occasion_id
    FROM eshop.orders o
    WHERE o.id = order_id
    LIMIT 1;

    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion for order not found');
    END IF;

    -- 4. Retrieve the expected scan_code
    SELECT oh.secret
      INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    IF expected_scan_code IS NULL THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Scan code not defined for this occasion'
        );
    END IF;

    -- 5. Validate the scanned_code
    IF NOT EXISTS(SELECT 1 FROM public.get_scanner_occasion_for_scan_code_internal(scanned_code) proof
      WHERE proof.id=occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 401,
            'message', 'Scan code is not correct'
        );
    END IF;

    -- 6. Proceed with fetching all required details

    -- Fetch the order details as JSON
    SELECT row_to_json(o)
      INTO order_json
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- Fetch the associated spot as JSON
    SELECT row_to_json(s)
      INTO spot_json
    FROM eshop.spots s
    WHERE s.order_product_ticket IN (
        SELECT opt.id
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    )
    LIMIT 1;

    -- =================================================================
    -- NEW: Fetch the full inventory bundle associated with the ticket
    -- =================================================================
    WITH scanned_ticket_products AS (
        SELECT
            opt.id AS order_product_ticket_id,
            opt.product AS product_id
        FROM eshop.order_product_ticket opt
        WHERE opt.ticket = ticket_row.id
          AND opt.product IS NOT NULL
    ),
    scanned_ticket_inventory AS (
        SELECT
            s.id AS id,
            s.title AS title,
            s.state AS state,
            s.resource_slot AS resource_slot,
            s.resource AS resource,
            s.inventory_context AS inventory_context,
            ic.inventory_pool AS inventory_pool,
            stp.product_id
        FROM eshop.spots s
        JOIN scanned_ticket_products stp ON s.order_product_ticket = stp.order_product_ticket_id
        JOIN public.inventory_contexts ic ON s.inventory_context = ic.id
    ),
    products_data AS (
        SELECT
            jsonb_object_agg(p.id, jsonb_build_object(
                'id', p.id, 'title', p.title, 'description', p.description, 'price', p.price, 'data', p.data,
                'product_type', p.product_type, 'occasion', p.occasion, 'is_hidden', p.is_hidden,
                'currency_code', p.currency_code, 'title_short', p.title_short, 'order', p."order",
                'maximum', p.maximum, 'is_dynamically_available', is_product_dynamically_available(p.id)
            )) AS data
        FROM eshop.products p
        WHERE p.id IN (SELECT DISTINCT product_id FROM scanned_ticket_products)
    ),
    product_inventory_contexts_data AS (
        SELECT jsonb_object_agg(pic.id, to_jsonb(pic)) AS data
        FROM eshop.product_inventory_contexts pic
        WHERE (pic.inventory_context, pic.product) IN (
            SELECT DISTINCT inventory_context, product_id FROM scanned_ticket_inventory
        )
    ),
    contexts_data AS (
        SELECT
            jsonb_object_agg(ic.id, jsonb_build_object(
                'id', ic.id, 'order', ic."order", 'block_date', ic.block_date, 'title', ic.title,
                'data', ic.data, 'inventory_pool', ic.inventory_pool,
                'spots', (
                    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
                    FROM (
                        SELECT sti.id, sti.title, sti.state, sti.resource_slot, sti.resource, sti.product_id
                        FROM scanned_ticket_inventory sti
                        WHERE sti.inventory_context = ic.id
                    ) t
                )
            )) AS data
        FROM public.inventory_contexts ic
        WHERE ic.id IN (SELECT DISTINCT inventory_context FROM scanned_ticket_inventory)
    ),
    pools_data AS (
        SELECT jsonb_object_agg(p.id, jsonb_strip_nulls(jsonb_build_object(
            'id', p.id, 'data', p.data, 'title', p.title, 'description', p.description,
            'type', p.type, 'sellable_capacity', p.sellable_capacity, 'occasion', p.occasion
        ))) AS data
        FROM public.inventory_pools p
        WHERE p.id IN (SELECT DISTINCT inventory_pool FROM scanned_ticket_inventory)
    ),
    places_data AS (
        SELECT jsonb_object_agg(pl.id, to_jsonb(pl)) AS data
        FROM public.places pl
        JOIN (
            SELECT DISTINCT (ip.data->>'place_id')::bigint AS id
            FROM public.inventory_pools ip
            WHERE ip.id IN (SELECT DISTINCT inventory_pool FROM scanned_ticket_inventory)
              AND ip.data ? 'place_id' AND ip.data->>'place_id' IS NOT NULL
        ) AS place_ids ON pl.id = place_ids.id
    ),
    resources_data AS (
        SELECT jsonb_object_agg(r.id, to_jsonb(r)) AS data
        FROM public.resources r
        WHERE r.id IN (SELECT DISTINCT resource FROM scanned_ticket_inventory WHERE resource IS NOT NULL)
    )
    SELECT jsonb_build_object(
        'inventory_contexts', COALESCE((SELECT data FROM contexts_data), '{}'::jsonb),
        'inventory_pools', COALESCE((SELECT data FROM pools_data), '{}'::jsonb),
        'resources', COALESCE((SELECT data FROM resources_data), '{}'::jsonb),
        'products', COALESCE((SELECT data FROM products_data), '{}'::jsonb),
        'product_inventory_contexts', COALESCE((SELECT data FROM product_inventory_contexts_data), '{}'::jsonb),
        'places', COALESCE((SELECT data FROM places_data), '{}'::jsonb)
    )
    INTO inventory_json;

    -- This overwrites the simple products_json from before with the richer one from the bundle
    SELECT inventory_json->'products' INTO products_json;

    -- 7. Return the compiled JSONB response
    RETURN jsonb_build_object(
        'code', 200,
        'ticket', row_to_json(ticket_row),
        'order', order_json,
        'products', products_json,
        'spot', spot_json,
        'inventory', inventory_json -- Added the full inventory bundle
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$function$
;
REVOKE ALL ON FUNCTION public.scan_ticket_v2(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.scan_ticket_v2(text,text) TO anon,authenticated,service_role;
