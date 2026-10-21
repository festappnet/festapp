CREATE OR REPLACE FUNCTION public.get_all_tickets_for_scan(scan_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    occasion_id_val bigint;
    result jsonb;
BEGIN
    SELECT o.id
    INTO occasion_id_val
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF occasion_id_val IS NULL THEN
         RAISE EXCEPTION 'Invalid scan code';
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', t.id,
            'ticket_symbol', t.ticket_symbol,
            'state', t.state,
            'related_order', jsonb_build_object(
                 'data', o.data
            )
        ) 
    )
    INTO result
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
    JOIN eshop.orders o ON opt."order" = o.id
    WHERE o.occasion = occasion_id_val
      AND t.state != 'storno';

    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;
