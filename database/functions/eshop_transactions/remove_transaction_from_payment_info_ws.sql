CREATE OR REPLACE FUNCTION public.remove_transaction_from_payment_info_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bank_account_id bigint;
  v_occasion_id bigint;
BEGIN
  SELECT pi.bank_account, o.occasion INTO v_bank_account_id, v_occasion_id
  FROM eshop.payment_info pi
  JOIN eshop.orders o ON o.payment_info = pi.id
  WHERE pi.id = p_payment_info_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
  IF NOT public.can_manage_bank_account(v_bank_account_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Bank transaction write access denied'; END IF;
  IF NOT public.can_manage_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='Source bank transaction write access denied'; END IF;
  PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);
  PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.occasions oc WHERE oc.id=v_occasion_id;
  IF NOT coalesce((SELECT public.payment_method_policy_enabled_internal(oc.unit,'bank') FROM public.occasions oc WHERE oc.id=v_occasion_id),false) THEN RAISE EXCEPTION 'PAYMENT_METHOD_POLICY_DISABLED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM eshop.transactions t
    WHERE t.id = p_transaction_id AND t.payment_info = p_payment_info_id) THEN
    RAISE EXCEPTION 'TRANSACTION_PAIRING_MISMATCH';
  END IF;
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, NULL, 'manual_unlink', 'user'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.remove_transaction_from_payment_info_ws(bigint,bigint)
  TO authenticated;
