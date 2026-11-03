CREATE OR REPLACE FUNCTION public.get_products_for_ticket_all_available(
  ticket_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id bigint;
  v_available   jsonb;
BEGIN
  -- find the ticket’s occasion
  SELECT occasion
  INTO   v_occasion_id
  FROM   eshop.tickets
  WHERE  id = ticket_id;

  IF NOT FOUND OR v_occasion_id IS NULL THEN
    RETURN jsonb_build_object(
      'code',    404,
      'message', 'Ticket not found'
    );
  END IF;

  IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
    RETURN jsonb_build_object(
      'code',    403,
      'message', 'Not authorized'
    );
  END IF;

  -- aggregate all products for that occasion
  SELECT jsonb_agg(
           jsonb_build_object(
             'id',            p.id,
             'title',         p.title,
             'price',         p.price,
             'currency_code', p.currency_code,
             'type_title',    pt.title
           )
         )
  INTO   v_available
  FROM   eshop.products p
  LEFT JOIN eshop.product_types pt
    ON pt.id = p.product_type
  WHERE  p.occasion = v_occasion_id;

  RETURN jsonb_build_object(
    'code', 200,
    'data', COALESCE(v_available, '[]'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'code',    500,
    'message', SQLERRM
  );
END;
$$;