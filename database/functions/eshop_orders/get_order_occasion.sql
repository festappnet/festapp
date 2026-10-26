CREATE OR REPLACE FUNCTION get_order_occasion(order_id bigint)
RETURNS bigint
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  occasion bigint;
BEGIN
  SELECT o.occasion
    INTO occasion
  FROM eshop.orders AS o
  WHERE o.id = order_id;

  RETURN occasion;
END;
$$;