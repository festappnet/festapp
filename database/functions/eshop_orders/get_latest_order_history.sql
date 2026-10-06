CREATE OR REPLACE FUNCTION public.get_latest_order_history(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT to_jsonb(o) || jsonb_build_object('order_symbol', (SELECT ord.order_symbol FROM eshop.orders ord WHERE ord.id=o."order"))
    INTO result
  FROM eshop.orders_history o
  WHERE o."order" = order_id AND (o.price <> 0 OR o.state IS DISTINCT FROM 'storno')
  -- Free orders also need cancellation emails; prefer the existing nonzero history.
  ORDER BY (o.price <> 0) DESC NULLS LAST, o.created_at DESC, o.id DESC
  LIMIT 1;

  RETURN result;
END;
$$;
