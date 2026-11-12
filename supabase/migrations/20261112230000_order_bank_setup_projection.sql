-- Keep bank setup prompts consistent with the configured unit account; pairing permissions are unchanged.

-- SOURCE: eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint; bank_allowed boolean; bank_configured boolean; payment_context jsonb; provider_rows jsonb:='[]'; provider_complete boolean:=true; method text; movement jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  SELECT pi.payment_method='bank' AND public.payment_method_policy_enabled_internal(oc.unit,'bank'),
   EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
    WHERE l.unit=oc.unit AND upper(b.type)<>'CASH')
  INTO bank_allowed,bank_configured
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  payment_context:=public.payment_method_context_internal(order_id);
  SELECT pi.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  IF public.payment_method_is_online_internal(method) THEN
   BEGIN
    SELECT public.payment_provider_call_internal(method,'movements',jsonb_build_object('paymentId',o.payment_info)) INTO movement FROM eshop.orders o WHERE o.id=order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('source','provider','sourceId',m->>'sourceId','provider',method,
     'date',m->'occurred_at','amount',CASE WHEN m->>'kind'='dispute' THEN NULL ELSE CASE WHEN m->>'kind'='refund' THEN -1 ELSE 1 END*(m->>'amount_minor')::numeric/100 END,
     'heldAmount',CASE WHEN m->>'kind'='dispute' THEN (m->>'amount_minor')::numeric/100 END,'status',m->>'status',
     'currency',m->>'currency','transaction_type',m->>'kind','isRefund',m->>'kind'='refund','voided',false)), '[]')
    INTO provider_rows FROM jsonb_array_elements(movement) m;
    provider_complete:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(movement) m WHERE nullif(m->>'sourceId','') IS NULL);
   EXCEPTION WHEN OTHERS THEN provider_complete:=false; END;
  ELSIF method NOT IN ('bank','cash') OR method IS NULL THEN provider_complete:=false;
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,'ledgerComplete',provider_complete,
      'paymentOperations',payment_context,
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(payment_context->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', bank_allowed AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankSetup',bank_allowed AND NOT bank_configured AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankAccess',bank_allowed AND NOT public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT bank_allowed THEN 'disabled' WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN bank_configured THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN bank_allowed AND pi.payment_method='bank' AND public.can_manage_bank_account(pi.bank_account)
          AND public.can_write_orders(o.occasion) AND o.state IN ('created','ordered','paid','sent') THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND o.state IN ('created','ordered','paid','sent')
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND NOT EXISTS(SELECT 1 FROM eshop.transaction_pairing_events e WHERE e.transaction_snapshot_id=t.id AND e.method='exact_cash_correction')
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE bank_allowed AND public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id) END)
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('source',CASE WHEN t.ingest_source='manual' THEN 'cash' ELSE 'bank' END,'sourceId','transaction:'||t.id,'isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)||provider_rows
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;
