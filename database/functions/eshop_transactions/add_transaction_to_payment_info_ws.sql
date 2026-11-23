CREATE OR REPLACE FUNCTION public.add_transaction_to_payment_info_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    occasion_id bigint;
    v_transaction eshop.transactions;
BEGIN
    -- Retrieve the associated order_id from payment_info
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id
    LIMIT 1;

    IF NOT public.can_manage_bank_account(bank_acc) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;

    SELECT * INTO v_transaction FROM eshop.transactions WHERE id=p_transaction_id;
    IF NOT public.can_manage_bank_account(v_transaction.bank_account_id) THEN
      RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;

    SELECT o.occasion
    INTO occasion_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=occasion_id;
  -- Stabilize the existing receipt before applying the recovery policy.
  SELECT * INTO v_transaction FROM eshop.transactions WHERE id=p_transaction_id FOR UPDATE;
  IF NOT public.can_manage_bank_account(v_transaction.bank_account_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied';
  END IF;
  -- Recovery after closing bank sales applies only to an existing verified
  -- receipt and bank instructions already issued on a linked account.
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank')
      FROM public.occasions oc WHERE oc.id=occasion_id),false) THEN
    IF NOT EXISTS(
      SELECT FROM eshop.payment_info pi
      JOIN public.occasions oc ON oc.id=occasion_id
      JOIN eshop.unit_bank_accounts link ON link.unit=oc.unit AND link.bank_account=pi.bank_account
      WHERE pi.id=p_payment_info_id AND pi.payment_method='bank'
       AND public.bank_sync_recovery_receipt_internal(v_transaction)
    ) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
  END IF;

    PERFORM public.apply_transaction_pairing(
      p_transaction_id, p_payment_info_id, 'manual_attach', 'user'
    );

    -- Return success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Transaction added successfully.'
    );

END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.add_transaction_to_payment_info_ws(bigint,bigint)
  TO authenticated;
