CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,
      'paymentOperations',public.payment_method_context_internal(o.id),
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(public.payment_method_context_internal(o.id)->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
            WHERE l.unit=oc.unit AND upper(b.type)<>'CASH') THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN pi.payment_method='bank' AND public.can_manage_bank_account(pi.bank_account)
          AND public.can_write_orders(o.occasion) AND o.state IN ('created','ordered','paid','sent') THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND o.state IN ('created','ordered','paid','sent')
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id) END),
        'historyAccounts', (SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title) ORDER BY b.id),'[]')
          FROM public.get_my_admin_bank_accounts() b WHERE upper(b.type)<>'CASH')
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;
