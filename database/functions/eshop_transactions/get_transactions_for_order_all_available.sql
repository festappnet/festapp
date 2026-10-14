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
    LIMIT 1;

    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.get_is_editor_order_view_on_occasion(demo_bank.occasion)) THEN
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
        AND t.payment_info IS NULL
    );
END;
$$;
