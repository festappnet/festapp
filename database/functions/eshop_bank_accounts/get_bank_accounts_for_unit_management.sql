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
    last_fio_fetch_time timestamptz,
    bank_sync jsonb,
    bank_sync_warning jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_unit_manager boolean;
BEGIN
    v_unit_manager := public.can_manage_unit_bank_accounts(p_unit_id);
    IF NOT public.can_read_unit_bank_accounts(p_unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE='User is not manager.';
    END IF;
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        ba.creditor_name,
        ba.type,
        coalesce(membership.is_admin,false) as is_admin,
        NULL::text as token_masked,
        NULL::timestamptz as token_expiry_date,
        ba.supported_currencies,
        ba.last_fio_fetch_time,
        CASE WHEN public.bank_account_write_rule(membership.is_admin,v_unit_manager,protected.bank_account IS NOT NULL)
          THEN public.get_bank_sync_connection(ba.id)
          ELSE (
            SELECT jsonb_build_object('state',connection.state,'mode',connection.mode)
            FROM eshop.bank_sync_connections connection
            WHERE connection.bank_account_id = ba.id
          ) END AS bank_sync,
        public.bank_sync_warning(ba.id) AS bank_sync_warning
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    -- Historical memberships need not be unique. Preserve any active admin
    -- grant while returning one row for each linked bank account.
    LEFT JOIN (
      SELECT grants.bank_account,bool_or(grants.is_admin) AS is_admin
      FROM eshop.bank_account_users grants WHERE grants."user"=auth.uid()
      GROUP BY grants.bank_account
    ) membership ON membership.bank_account=ba.id
    LEFT JOIN (SELECT DISTINCT bank_account FROM public.demo_occasions) protected ON protected.bank_account=ba.id
    WHERE uba.unit = p_unit_id
    AND ba.type != 'CASH'
    -- The entry guard admits a manager or a listed demo reader. Managers are
    -- always outside demo units; demo readers retain the account-level fence.
    AND (v_unit_manager OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=ba.id AND public.can_read_orders(demo_bank.occasion)));
END;
$$;

REVOKE ALL ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_accounts_for_unit_management(bigint) TO authenticated, service_role;
