CREATE OR REPLACE FUNCTION check_is_admin_for_bank_account(bank_acc bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_bank_account_writable(bank_acc);
    IF NOT EXISTS (
        SELECT 1
        FROM eshop.bank_account_users
        WHERE bank_account = bank_acc
          AND "user" = auth.uid()
          AND (is_admin)
    ) THEN
        RAISE EXCEPTION 'User is not an admin for the specified bank account.';
    END IF;
END;
$$;