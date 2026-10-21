CREATE OR REPLACE FUNCTION check_is_admin_for_bank_account(bank_acc bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_bank_account_writable(bank_acc);
    IF NOT public.can_manage_bank_account(bank_acc) THEN
        RAISE EXCEPTION 'User is not an admin for the specified bank account.' USING ERRCODE='42501';
    END IF;
END;
$$;
