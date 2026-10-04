CREATE OR REPLACE FUNCTION public.delete_product(p_product_id BIGINT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id BIGINT;
  v_order_count INT;
BEGIN
  -- Determine the occasion of the product to check permissions.
  SELECT pt.occasion
    INTO v_occasion_id
  FROM eshop.products p
  JOIN eshop.product_types pt ON p.product_type = pt.id
  WHERE p.id = p_product_id FOR UPDATE OF p;

  -- If the product does not exist, raise a structured error.
  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object(
        'code', 'PRD404',
        'message', 'Product with ID ' || p_product_id || ' not found.'
    )::text;
  END IF;

  -- Authorization check. This function is expected to throw on failure.
  PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

  -- Safety Check: Ensure the product is not part of any existing orders.
  SELECT COUNT(*) INTO v_order_count
    FROM eshop.order_product_ticket
   WHERE product = p_product_id;
  IF v_order_count > 0 THEN
    RAISE EXCEPTION '%', jsonb_build_object(
        'code', 'PRD409',
        'message', 'Cannot delete product because it is included in ' || v_order_count || ' order(s).',
        'hint', 'Remove this product from all orders before deleting it.'
    )::text;
  END IF;

  -- **INTEGRATION:** Before deleting the product, clear all its inventory context associations.
  -- This call will also trigger the necessary de-allocation of spots.
  PERFORM public.update_product_inventory_contexts_internal_v1(p_product_id, '[]'::jsonb);

  DELETE FROM eshop.planned_changes WHERE subject_id=p_product_id AND change_type='products.price' AND NOT applied;

  -- Finally, delete the product itself.
  DELETE FROM eshop.products
   WHERE id = p_product_id;

END;
$$;
