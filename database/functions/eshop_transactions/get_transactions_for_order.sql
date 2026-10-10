CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint;
  v_transactions jsonb;
  v_users jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  -- Fetch transactions
  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
  INTO v_transactions
  FROM eshop.transactions t
  JOIN eshop.orders o ON t.payment_info = o.payment_info
  WHERE o.id = order_id;

  -- Fetch unique users associated with these transactions
  SELECT COALESCE(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
  INTO v_users
  FROM public.user_info u
  WHERE u.id IN (
      SELECT DISTINCT t.created_by
      FROM eshop.transactions t
      JOIN eshop.orders o ON t.payment_info = o.payment_info
      WHERE o.id = order_id AND t.created_by IS NOT NULL
  );

  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', v_transactions,
      'users', v_users
    )
    FROM eshop.orders o
    WHERE o.id = order_id
  );
END;
$$;
