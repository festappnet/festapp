CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    v_bank_sales boolean;
    v_unit bigint;
BEGIN
    SELECT pi.bank_account,public.payment_method_policy_enabled_internal(oc.unit,'bank'),oc.unit
    INTO bank_acc,v_bank_sales,v_unit
    FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
    JOIN public.occasions oc ON oc.id=o.occasion
    WHERE pi.id=payment_info_id AND pi.payment_method='bank' AND public.can_read_orders(oc.id);
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;
    IF NOT v_bank_sales AND NOT public.bank_sync_recovery_account_internal(bank_acc,v_unit)
    THEN RAISE insufficient_privilege; END IF;

    RETURN (
        SELECT jsonb_agg(to_jsonb(t)||
          CASE WHEN review.delivery_id IS NOT NULL AND review.resolution IS NULL
          THEN jsonb_build_object('bankSyncReview',public.bank_sync_api_review_view_internal(review))
          ELSE '{}'::jsonb END ORDER BY t.date DESC,t.id)
        FROM eshop.transactions t
        LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
          CASE WHEN t.ingest_source='banksync_api' THEN t.id END) review ON true
        WHERE t.bank_account_id IN (
          SELECT bank_acc
          UNION SELECT c.bank_account_id FROM eshop.bank_sync_connections c
           JOIN eshop.bank_sync_account_aliases a ON a.connection_id=c.id
           WHERE a.bank_account_id=bank_acc AND public.can_manage_bank_account(c.bank_account_id)
        )
        AND (t.bank_account_id=bank_acc OR public.bank_sync_accounts_match(t.id,bank_acc))
        AND (v_bank_sales OR public.bank_sync_recovery_receipt_internal(t))
        AND t.payment_info IS NULL AND t.amount>0
        AND review.resolution->>'action' IS DISTINCT FROM 'api_same_movement'
        AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
    );
END;
$$;

-- Explicit account context. Order access never grants statement authority.
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint,p_unit_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) OR NOT public.get_is_manager_on_unit(p_unit_id)
  OR NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false)
  OR NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts WHERE unit=p_unit_id AND bank_account=p_bank_account_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Bank history access denied'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(t ORDER BY t.date DESC,t.id),'[]') FROM eshop.transactions t
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id WHERE b.id=p_bank_account_id AND upper(b.type)<>'CASH');
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint,bigint) TO authenticated;
