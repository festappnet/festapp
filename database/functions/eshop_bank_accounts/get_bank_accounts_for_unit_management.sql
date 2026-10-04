DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

CREATE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
RETURNS TABLE (
    id bigint,
    account_number text,
    title text,
    creditor_name text,
    type text,
    is_admin boolean,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    last_fio_fetch_time timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    RETURN QUERY
    SELECT 
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        EXISTS (
            SELECT 1 
            FROM eshop.bank_account_users bau
            WHERE bau.bank_account = ba.id 
            AND bau."user" = auth.uid() 
            AND bau.is_admin = true
        ) as is_admin,
        CASE 
            WHEN s.secret IS NOT NULL THEN 
                '************' || right(s.secret, 4)
            ELSE NULL 
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'; -- Exclude Cash Accounts from management list
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;
