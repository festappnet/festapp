
DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_id bigint;
    v_test_user uuid;
    v_is_admin boolean;
    v_count int;
BEGIN
    RAISE NOTICE 'Starting Hidden Admin Test...';

    -- 1. Setup
    SELECT id INTO v_test_user FROM public.user_info LIMIT 1;
    IF v_test_user IS NULL THEN
        RAISE EXCEPTION 'No users found';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_test_user::text, true);

    INSERT INTO public.organizations (title) VALUES ('Test Hidden Org') RETURNING id INTO v_org_id;
    
    -- MAKE USER HIDDEN ADMIN
    INSERT INTO public.organization_users (organization, "user", is_admin, is_hidden) 
    VALUES (v_org_id, v_test_user, true, true);
    
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_test_user, true);

    -- 2. Create Bank Account
    SELECT public.update_bank_account(NULL::bigint, '888777666/2010', 'Hidden Admin Acc', 'FIO', ARRAY['CZK'], NULL, v_unit_id) INTO v_acc_id;

    -- 3. Verify Persistence (Should exist in table)
    SELECT is_admin INTO v_is_admin FROM eshop.bank_account_users WHERE bank_account = v_acc_id AND "user" = v_test_user;
    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'User IS NOT in table or not admin!';
    END IF;
    RAISE NOTICE 'User is correctly persisted in DB as admin.';

    -- 4. Verify Visibility via RPC (The one used by UI)
    -- We need to check if the user is returned by get_bank_account_users
    
    -- NOTE: In test environment, the 'get_bank_account_users' might depend on organization_users table availability.
    -- The test transaction creates the organization_user record.
    
    SELECT count(*) INTO v_count FROM public.get_bank_account_users(v_acc_id, v_unit_id) WHERE user_id = v_test_user;
    
    IF v_count = 0 THEN
        RAISE NOTICE 'SUCCESS: User is HIDDEN from RPC output as requested.';
    ELSE
        RAISE EXCEPTION 'User IS visible in RPC output! This violates the hidden requirement.';
    END IF;

END;
$$ LANGUAGE plpgsql;
