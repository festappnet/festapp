CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
  p_transaction_id bigint,
  p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE source eshop.transactions; oid bigint;
BEGIN
  SELECT * INTO source FROM eshop.transactions WHERE id=p_transaction_id AND payment_info=p_payment_info_id;
  SELECT id INTO oid FROM eshop.orders WHERE payment_info=p_payment_info_id;
  IF source.id IS NULL OR oid IS NULL THEN RAISE EXCEPTION 'MANUAL_TRANSACTION_PAIRING_MISMATCH'; END IF;
  PERFORM public.check_order_is_mutable(oid);
  -- Released void RPC delegates to the same exact-source command. Preserve the
  -- original cash fact and reverse it once, instead of deleting financial history.
  PERFORM public.command_payment_operation(jsonb_build_object('operation','correct_record','method','cash','orderId',oid,
    'transactionId',source.id,'amount',(-source.amount)::text,'currency',trim(source.currency),
    'receivedAt',source.date,'reason','Oprava původního hotovostního záznamu'),
    md5('legacy-manual-correction:'||source.id)::uuid);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_manual_transaction_ws(bigint,bigint)
  TO authenticated;
