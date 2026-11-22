DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_czk bigint;
    v_acc_eur bigint;
    v_acc_eur_backup bigint;
    v_backup_secret bigint;
    v_error_payload jsonb;
    v_reorder_request jsonb;
    v_command_id uuid := gen_random_uuid();
    v_initial_order bigint[];
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
    INSERT INTO public.organizations (title) VALUES ('Test Org') RETURNING id INTO v_org_id;
    INSERT INTO eshop.organization_payment_method_policies (organization_id, method, enabled)
    VALUES (v_org_id, 'bank', true)
    ON CONFLICT (organization_id, method) DO UPDATE SET enabled = EXCLUDED.enabled;
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_org_id) RETURNING id INTO v_unit_id;
    
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

    INSERT INTO public.forms (title, occasion, is_open, data)
    VALUES ('Test Form', v_occasion_id, true, '{"payments":{"bankEnabled":true}}') RETURNING id INTO v_form_id;

    INSERT INTO eshop.product_types (title, occasion) 
    VALUES ('Test PT', v_occasion_id) RETURNING id INTO v_product_type_id;

    INSERT INTO eshop.products (title, product_type, currency_code, is_hidden, occasion, price)
    VALUES ('Test Product EUR', v_product_type_id, 'EUR', false, v_occasion_id, 100) RETURNING id INTO v_product_id;

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

    INSERT INTO eshop.secrets (secret) VALUES ('test_backup_secret') RETURNING id INTO v_backup_secret;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Backup EUR', ARRAY['EUR'], v_backup_secret, 'FIO')
    RETURNING id INTO v_acc_eur_backup;
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
    VALUES (v_unit_id, v_acc_eur_backup, 3);

    v_initial_order := ARRAY[v_acc_czk, v_acc_eur, v_acc_eur_backup];
    v_reorder_request := jsonb_build_object(
        'expectedOrder', v_initial_order,
        'accountOrder', ARRAY[v_acc_eur_backup, v_acc_czk, v_acc_eur]);
    PERFORM assert_true(public.manage_bank_authoring(v_unit_id, v_org_id, 'reorder', v_reorder_request, v_command_id)
       #>> '{data,accountOrder,0}' = v_acc_eur_backup::text, 'reorder receipt records actual account order');
    PERFORM assert_true(ARRAY(SELECT bank_account FROM eshop.unit_bank_accounts
       WHERE unit=v_unit_id ORDER BY priority, bank_account) = ARRAY[v_acc_eur_backup, v_acc_czk, v_acc_eur],
       'reordering updates all priorities together');
    PERFORM assert_true(public.manage_bank_authoring(v_unit_id, v_org_id, 'reorder', v_reorder_request, v_command_id)
       #>> '{mutation,receiptId}' = v_command_id::text, 'same intent is replayable after its own reorder');

    BEGIN
        PERFORM public.manage_bank_authoring(v_unit_id, v_org_id, 'reorder', v_reorder_request, gen_random_uuid());
        RAISE EXCEPTION 'Stale order unexpectedly succeeded.';
    EXCEPTION WHEN serialization_failure THEN
        PERFORM assert_true(SQLERRM='BANK_ACCOUNT_ORDER_CHANGED','stale order has a conflict result');
    END;
    BEGIN
        PERFORM public.manage_bank_authoring(v_unit_id, v_org_id, 'reorder',
           jsonb_build_object('expectedOrder', ARRAY[v_acc_eur_backup,v_acc_czk,v_acc_eur],
                              'accountOrder', ARRAY[v_acc_czk,v_acc_czk,v_acc_eur]), gen_random_uuid());
        RAISE EXCEPTION 'Invalid order unexpectedly succeeded.';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
    PERFORM assert_true(ARRAY(SELECT bank_account FROM eshop.unit_bank_accounts
       WHERE unit=v_unit_id ORDER BY priority,bank_account) = ARRAY[v_acc_eur_backup,v_acc_czk,v_acc_eur],
       'failed reorder leaves the previous order intact');
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    BEGIN
        PERFORM public.manage_bank_authoring(v_unit_id, v_org_id, 'reorder', v_reorder_request, v_command_id);
        RAISE EXCEPTION 'Unauthorized replay unexpectedly succeeded.';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('request.jwt.claim.sub', v_test_user::text, true);

    UPDATE public.forms SET bank_account = v_acc_eur WHERE id = v_form_id;
    BEGIN
        PERFORM public.link_bank_account_to_unit(v_acc_eur, v_unit_id, NULL, false);
        RAISE EXCEPTION 'The explicitly selected account unlinked without warning.';
    EXCEPTION WHEN raise_exception THEN
        v_error_payload := SQLERRM::jsonb;
        PERFORM assert_true(v_error_payload->>'code' = 'LINK_DEPENDENCY_ERROR',
           'Explicit receiving account requires confirmation even with a backup');
        PERFORM assert_true(v_error_payload->'conflicts' @> '[{"form": "Test Form", "currency": "EUR"}]',
           'Unlink warning identifies the affected form and currency');
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
