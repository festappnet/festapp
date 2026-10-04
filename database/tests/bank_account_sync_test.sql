DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_id bigint;
    v_test_user uuid;
BEGIN
    RAISE NOTICE 'Starting Bank Account Creation After BankSync Cutover...';

    -- 1. Setup: Create Test User, Org, Unit
    SELECT id INTO v_test_user FROM public.user_info LIMIT 1;
    IF v_test_user IS NULL THEN
        RAISE EXCEPTION 'No users found in public.user_info to run test against.';
    END IF;

    -- Mock Auth
    PERFORM set_config('request.jwt.claim.sub', v_test_user::text, true);

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Sync Org') RETURNING id INTO v_org_id;
    INSERT INTO public.organization_users (organization, "user", is_admin) VALUES (v_org_id, v_test_user, true);
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_test_user, true);

    -- 2. Create Floating Bank Account via the account-management RPC (update_bank_account)
    -- This function creates the account AND links it to the unit if unit_id is provided.
    RAISE NOTICE 'Test 1: Create Unit Bank Account...';
    
    -- update_bank_account signature: (id, acc_num, title, type, currencies, readable, unit_id)
    SELECT public.update_bank_account(
        NULL::bigint, 
        (floor(random() * 1000000000)::text || '/2010'), 
        'Floating Sync Acc'::text, 
        'FIO'::text, 
        ARRAY['CZK']::text[], 
        NULL::text, 
        v_unit_id
    ) INTO v_acc_id;

    IF v_acc_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create bank account via account-management RPC.';
    END IF;

    -- 3. Verify Unit Linkage
    PERFORM 1 FROM eshop.unit_bank_accounts WHERE unit = v_unit_id AND bank_account = v_acc_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account creation did not link account to unit.';
    END IF;

    PERFORM assert_true((SELECT pairing_code IS NULL AND NOT is_fetch_enabled
        FROM eshop.bank_accounts WHERE id = v_acc_id),
        'new accounts must not enable legacy polling or generate legacy email codes');
    PERFORM assert_true(EXISTS (SELECT 1 FROM public.get_bank_accounts_for_unit_management(v_unit_id)
        WHERE id = v_acc_id), 'unit managers can retrieve their newly linked account');
END;
$$;
