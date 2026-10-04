CREATE OR REPLACE FUNCTION public.delete_order_221(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  unit_id BIGINT;
  is_manager BOOLEAN;
  ou_record RECORD;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info
    INTO order_oc, payment_info_id
    FROM eshop.orders
   WHERE id = order_id
   FOR UPDATE;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Check if the current user is a manager on the order's occasion.
  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = order_oc;

  PERFORM public.check_is_manager_on_unit(unit_id);

  -- Fence unsent mail immediately; retain in-flight/accepted/unknown evidence.
  WITH cancelled AS (
    UPDATE public.email_messages m
       SET workflow_state = 'cancelled', last_error = 'order_deleted',
           lease_token = NULL, lease_until = NULL
     WHERE m.order_id = delete_order_221.order_id
       AND m.workflow_state IN ('pending', 'retry_wait', 'blocked', 'preparing')
     RETURNING m.message_id
  )
  UPDATE public.email_attempts a
     SET state = 'cancelled', finished_at = now(), error_code = 'order_deleted'
   WHERE a.message_id IN (SELECT message_id FROM cancelled)
     AND a.state = 'preparing';

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = order_id;

  -- Before deleting the tickets, find any occasion_users rows that are
  -- bound to these tickets and call the workspace deletion function.
  -- This function runs as SECURITY INVOKER, so it will correctly
  -- check the *caller's* permissions (e.g., is_companion, is_manager).
  IF ticket_ids IS NOT NULL AND array_length(ticket_ids, 1) > 0 THEN
    FOR ou_record IN
      SELECT "user", occasion
      FROM public.occasion_users
      WHERE ticket = ANY(ticket_ids)
    LOOP
      -- Call the function to delete the user from the occasion.
      -- This respects the security and permission logic defined in
      -- delete_occasion_user_ws. If this fails, the whole transaction
      -- will be rolled back.
      PERFORM public.delete_occasion_user_ws(ou_record."user", ou_record.occasion);
    END LOOP;
  END IF;

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = order_id;

END;
$$;
