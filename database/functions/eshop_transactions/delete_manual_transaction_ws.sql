CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_unit_id bigint;
BEGIN
  SELECT oc.unit INTO v_unit_id
  FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id AND upper(b.type)='CASH'
  JOIN eshop.orders o ON o.payment_info=t.payment_info JOIN public.occasions oc ON oc.id=o.occasion
  JOIN eshop.unit_bank_accounts l ON l.bank_account=b.id AND l.unit=oc.unit
  WHERE t.id=p_transaction_id AND t.payment_info=p_payment_info_id AND t.transaction_type='manual';
  IF NOT FOUND THEN RAISE EXCEPTION 'MANUAL_TRANSACTION_PAIRING_MISMATCH'; END IF;
  IF NOT public.can_manage_unit_bank_accounts(v_unit_id) THEN
    RAISE insufficient_privilege USING MESSAGE='Cash correction requires unit manager'; END IF;

  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id) THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION'; END IF;
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, NULL, 'manual_delete_unlink', 'user'
  );
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind
  ) VALUES (
    p_transaction_id, p_transaction_id, p_payment_info_id,
    NULL, 'manual_deleted', 'manual_delete', auth.uid(), 'user'
  );
  DELETE FROM eshop.transactions WHERE id = p_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  TO authenticated;
