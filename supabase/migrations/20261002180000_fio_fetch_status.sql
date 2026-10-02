-- Email ingestion also updates last_fetch_time, so it cannot be used to
-- backfill API success reliably. Start tracking FIO success separately.
ALTER TABLE eshop.bank_accounts ADD COLUMN IF NOT EXISTS last_fio_fetch_time timestamptz;

CREATE OR REPLACE FUNCTION public.set_last_fetch_time(p_bank_account_id bigint)
RETURNS void
SET search_path = public, extensions AS $$
BEGIN
  UPDATE eshop.bank_accounts
  SET last_fetch_time = now(),
      last_fio_fetch_time = now()
  WHERE id = p_bank_account_id;
END;
$$ LANGUAGE plpgsql;

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
    last_fio_fetch_time timestamptz
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
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '************'
             ELSE '************' || right(s.secret, 4)
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ARRAY(
            SELECT u.title
            FROM eshop.unit_bank_accounts uba
            JOIN public.units u ON uba.unit = u.id
            WHERE uba.bank_account = ba.id
        ) as linked_units,
        ba.last_fetch_time,
        ba.last_fio_fetch_time
    FROM eshop.bank_accounts ba
    JOIN eshop.bank_account_users bau ON ba.id = bau.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE bau."user" = auth.uid() AND bau.is_admin = true
    AND ba.type != 'cash'
    ORDER BY ba.title;
END;
$$;

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

REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;
