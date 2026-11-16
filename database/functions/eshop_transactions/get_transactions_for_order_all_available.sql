CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
BEGIN
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = payment_info_id
    AND pi.payment_method='bank'
    LIMIT 1;

    IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.payment_info=payment_info_id AND public.payment_method_policy_enabled_internal(oc.unit,'bank') AND public.can_read_orders(oc.id)) THEN RAISE insufficient_privilege; END IF;
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;

    RETURN (
        SELECT jsonb_agg(t ORDER BY t.date DESC)
        FROM eshop.transactions t
        WHERE t.bank_account_id = (
            SELECT pi.bank_account
            FROM eshop.payment_info pi
            WHERE pi.id = payment_info_id
        )
        AND t.payment_info IS NULL AND t.amount>0
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
