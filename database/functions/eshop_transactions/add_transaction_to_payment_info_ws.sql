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
BEGIN
    -- Retrieve the associated order_id from payment_info
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id
    LIMIT 1;

    PERFORM public.check_is_admin_for_bank_account(bank_acc);

    SELECT o.occasion
    INTO occasion_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

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
