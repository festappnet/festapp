DO $$
DECLARE
    v_acc_1 bigint;
    v_acc_2 bigint;
    v_user_id uuid;
BEGIN
    RAISE NOTICE 'Starting Unique Pairing Code Test...';

    -- 1. Setup Auth and Create two bank accounts
    SELECT id INTO v_user_id FROM public.user_info LIMIT 1;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found in public.user_info for testing permissions';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    INSERT INTO eshop.bank_accounts (title, type, supported_currencies, pairing_code) 
    VALUES ('Test 1', 'CASH', ARRAY['CZK'], 'aaaaaaaaaa') 
    RETURNING id INTO v_acc_1;
    
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_acc_1, v_user_id, true);
    
    INSERT INTO eshop.bank_accounts (title, type, supported_currencies, pairing_code) 
    VALUES ('Test 2', 'CASH', ARRAY['CZK'], 'bbbbbbbbbb') 
    RETURNING id INTO v_acc_2;

    -- 2. Verify Constraint Catch
    BEGIN
        UPDATE eshop.bank_accounts SET pairing_code = 'aaaaaaaaaa' WHERE id = v_acc_2;
        RAISE EXCEPTION 'Constraint violated: Should have failed uniqueness check';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'Caught expected unique_violation.';
    END;

    PERFORM assert_true(to_regprocedure('public.regenerate_bank_account_pairing_code(bigint)') IS NULL,
        'legacy email pairing-code generation must remain retired');
END;
$$;
