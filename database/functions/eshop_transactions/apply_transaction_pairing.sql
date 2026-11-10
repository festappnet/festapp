CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    FOR v_order_id IN SELECT id FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      PERFORM public.check_order_is_mutable(v_order_id);
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN PERFORM public.recalculate_order_payment_status(v_order_id); END IF;
  END IF;

  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
