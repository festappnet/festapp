CREATE OR REPLACE FUNCTION public.get_linkable_bank_accounts(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    creditor_name text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz,
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF public.is_demo_unit(p_unit_id) OR NOT public.can_manage_unit_bank_accounts(p_unit_id) OR NOT coalesce(public.payment_method_policy_enabled_internal(p_unit_id,'bank'),false) THEN RAISE insufficient_privilege; END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.creditor_name,
        ba.type,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        NULL::timestamptz as last_fetch_time,
        NULL::timestamptz as last_fio_fetch_time,
        NULL::jsonb AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND upper(ba.type) <> 'CASH'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_linkable_bank_accounts(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_linkable_bank_accounts(bigint) TO authenticated, service_role;
