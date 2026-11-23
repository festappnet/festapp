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
    v_recovery_only boolean;
BEGIN
    SELECT pi.bank_account,public.payment_method_policy_enabled_internal(oc.unit,'bank'),oc.unit,o.state='expired'
    INTO bank_acc,v_bank_sales,v_unit,v_recovery_only
    FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
    JOIN public.occasions oc ON oc.id=o.occasion
    WHERE pi.id=payment_info_id AND pi.payment_method='bank' AND public.can_read_orders(oc.id);
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;
    v_recovery_only:=v_recovery_only OR NOT v_bank_sales;
    IF v_recovery_only AND NOT public.bank_sync_recovery_account_internal(bank_acc,v_unit)
    THEN RAISE insufficient_privilege; END IF;

    RETURN (
        SELECT jsonb_agg(to_jsonb(c.movement)||
          CASE WHEN (c.review).delivery_id IS NOT NULL
          THEN jsonb_build_object('bankSyncReview',public.bank_sync_api_review_view_internal(c.review))
          ELSE '{}'::jsonb END ORDER BY (c.movement).date DESC,(c.movement).id)
        FROM public.bank_sync_pairing_candidates_internal(bank_acc,v_recovery_only) c
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
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(t)||
    CASE WHEN r.resolution IS NOT NULL THEN jsonb_build_object('bankSyncDecision',r.resolution->>'action')
    ELSE '{}'::jsonb END ORDER BY t.date DESC,t.id),'[]')
   FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
   LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
     CASE WHEN t.ingest_source='banksync_api' THEN t.id END) r ON true
   WHERE b.id=p_bank_account_id AND upper(b.type)<>'CASH');
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint,bigint) TO authenticated;
