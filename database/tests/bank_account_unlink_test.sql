DO $$
DECLARE
    v_unit_id bigint;
    v_acc_czk bigint;
    v_acc_eur bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_product_type_id bigint;
    v_product_id bigint;
    v_test_user uuid;
BEGIN
    RAISE NOTICE 'Starting Bank Account Unlink Test...';
    
    -- 1. Setup Data: Pick a real user or create one (if possible, but picking is safer for FKs)
    SELECT id INTO v_test_user FROM public.user_info LIMIT 1;
    IF v_test_user IS NULL THEN
        -- Fallback if no users exist (shouldn't happen on live, but strictly speaking)
        -- We can try to insert one if possible, or just fail.
        RAISE EXCEPTION 'No users found in public.user_info to run test against.';
    END IF;

    -- Mock Auth: Set the config to the REAL user ID we found
    PERFORM set_config('request.jwt.claim.sub', v_test_user::text, true);

    -- Create Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org') RETURNING id INTO v_unit_id; 
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_unit_id) RETURNING id INTO v_unit_id;
    
    -- Make user manager
    INSERT INTO public.unit_users (unit, "user", is_manager)
    VALUES (v_unit_id, v_test_user, true);

    -- Create Bank Accounts
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret') RETURNING id INTO v_acc_czk;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type) 
    VALUES ('Test CZK', ARRAY['CZK'], v_acc_czk, 'FIO') RETURNING id INTO v_acc_czk;
    
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret') RETURNING id INTO v_acc_eur;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type) 
    VALUES ('Test EUR', ARRAY['EUR'], v_acc_eur, 'FIO') RETURNING id INTO v_acc_eur;
    
    -- Make user account admin
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_acc_czk, v_test_user, true);
    INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin) VALUES (v_acc_eur, v_test_user, true);

    -- Link Bank Accounts
    PERFORM public.link_bank_account_to_unit(v_acc_czk, v_unit_id, 1);
    PERFORM public.link_bank_account_to_unit(v_acc_eur, v_unit_id, 2);

    -- Create Occasion -> Form -> Product (EUR)
    INSERT INTO public.occasions (title, unit, link, start_time, end_time) 
    VALUES ('Test Occasion', v_unit_id, 'test-occ', now(), now()) RETURNING id INTO v_occasion_id;

    INSERT INTO public.forms (title, occasion, is_open) 
    VALUES ('Test Form', v_occasion_id, true) RETURNING id INTO v_form_id;

    INSERT INTO eshop.product_types (title, occasion) 
    VALUES ('Test PT', v_occasion_id) RETURNING id INTO v_product_type_id;

    INSERT INTO eshop.products (title, product_type, currency_code, is_hidden, occasion)
    VALUES ('Test Product EUR', v_product_type_id, 'EUR', false, v_occasion_id) RETURNING id INTO v_product_id;

    -- Link Form to Product Type
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- TEST 1: Unlink EUR (hard=false) -> Should FAIL (Dependency Check)
    RAISE NOTICE 'Test 1: Attempting un-link with dependencies (expecting failure)...';
    BEGIN
        PERFORM public.link_bank_account_to_unit(v_acc_eur, v_unit_id, NULL, false);
        RAISE EXCEPTION 'TEST 1 FAILED: Expected exception, but got none.';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%LINK_DEPENDENCY_ERROR%' THEN
            RAISE NOTICE 'TEST 1 PASSED: Got LINK_DEPENDENCY_ERROR as expected.';
        ELSE
            RAISE EXCEPTION 'TEST 1 FAILED: Got unexpected error: %', SQLERRM;
        END IF;
    END;

    -- TEST 2: Unlink EUR (hard=true) -> Should PASS
    RAISE NOTICE 'Test 2: Attempting forced un-link (expecting success)...';
    BEGIN
        PERFORM public.link_bank_account_to_unit(v_acc_eur, v_unit_id, NULL, true);
        
        -- Verify it is gone
        IF EXISTS (SELECT 1 FROM eshop.unit_bank_accounts WHERE unit = v_unit_id AND bank_account = v_acc_eur) THEN
             RAISE EXCEPTION 'TEST 2 FAILED: Account still linked.';
        ELSE
             RAISE NOTICE 'TEST 2 PASSED: Account unlinked.';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Got error: %', SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;
