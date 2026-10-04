DO $$
DECLARE
    v_account_id bigint;
    v_fio_time timestamptz;
BEGIN
    IF has_function_privilege('anon', 'public.get_my_admin_bank_accounts()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.get_bank_accounts_for_unit_management(bigint)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Bank account readers must remain inaccessible to anonymous callers';
    END IF;
    IF NOT has_function_privilege('authenticated', 'public.get_my_admin_bank_accounts()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.get_bank_accounts_for_unit_management(bigint)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Bank account readers lost authenticated execution grants';
    END IF;
    INSERT INTO eshop.bank_accounts (title, type)
    VALUES ('FIO fetch status test', 'FIO') RETURNING id INTO v_account_id;

    -- Email/general activity must not imply an API success.
    UPDATE eshop.bank_accounts SET last_fetch_time = now() WHERE id = v_account_id;
    SELECT last_fio_fetch_time INTO v_fio_time FROM eshop.bank_accounts WHERE id = v_account_id;
    IF v_fio_time IS NOT NULL THEN RAISE EXCEPTION 'General activity changed FIO status'; END IF;

    PERFORM assert_true(to_regprocedure('public.set_last_fetch_time(bigint)') IS NULL,
        'legacy polling must not report fetch success after BankSync cutover');

END;
$$;
