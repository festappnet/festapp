CREATE OR REPLACE FUNCTION get_tickets_with_details(order_id BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    tickets JSONB;
BEGIN
    SELECT jsonb_agg(ticket_detail)
    INTO tickets
    FROM (
        SELECT DISTINCT ON (t.id)
            t.id,
            t.ticket_symbol,
            t.occasion,
            t.note,
            t.state,
            b.title AS table_title,
            (
                SELECT jsonb_agg(ticket_prod)
                FROM (
                    SELECT
                        opt2.id,
                        opt2.product,
                        s.title AS spot_title,
                        (
                            SELECT g.value->>'title'
                            FROM jsonb_array_elements(bp.groups) AS g(value)
                            WHERE (g.value->>'id')::bigint = (
                                SELECT (o2.value->>'group')::bigint
                                FROM jsonb_array_elements(bp.objects) AS o2(value)
                                WHERE (o2.value->>'id')::bigint = s.id
                                  AND o2.value->>'type' = 'spot'
                                LIMIT 1
                            )
                            LIMIT 1
                        ) AS spot_group_title
                    FROM eshop.order_product_ticket opt2
                    LEFT JOIN eshop.spots s
                        ON s.order_product_ticket = opt2.id
                    LEFT JOIN eshop.blueprints bp
                        ON bp.id = s.blueprint
                    WHERE opt2.ticket = t.id
                ) ticket_prod
            ) AS order_product_ticket,
            (
              SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
              FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                   jsonb_array_elements(ticket_json->'products') prod
              WHERE (ticket_json->>'id')::bigint = t.id
            ) AS price,
            (
              SELECT (prod->>'currency_code')
              FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                   jsonb_array_elements(ticket_json->'products') prod
              WHERE (ticket_json->>'id')::bigint = t.id
              LIMIT 1
            ) AS currency_code
        FROM eshop.order_product_ticket opt
        JOIN eshop.tickets t
            ON t.id = opt.ticket
        JOIN eshop.orders ord
            ON ord.id = order_id
        LEFT JOIN public.occasions o
            ON o.id = t.occasion
        LEFT JOIN eshop.blueprints b
            ON b.occasion = o.id
        WHERE opt."order" = order_id AND t.state IS DISTINCT FROM 'waitlisted' AND t.ticket_symbol IS NOT NULL
        ORDER BY t.id
    ) ticket_detail;

    RETURN tickets;
END;
$$;