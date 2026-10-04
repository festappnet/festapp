DROP FUNCTION IF EXISTS public.get_my_admin_bank_accounts();

CREATE FUNCTION public.get_my_admin_bank_accounts()
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
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.account_number_human_readable,
        ba.title,
        ba.creditor_name,
        ba.type,
        NULL::text as token_masked,
        (public.get_bank_sync_connection(ba.id)->>'token_expiry_at')::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title 
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        ba.last_fetch_time,
        ba.last_fio_fetch_time,
        public.get_bank_sync_connection(ba.id) AS bank_sync
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND ba.type != 'cash'
    ORDER BY ba.title;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated, service_role;
