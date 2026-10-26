
DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_id bigint;
    v_test_user uuid;
    v_is_admin boolean;
BEGIN
    RAISE NOTICE 'Starting Bank Account Creator Admin Test...';

    -- 1. Setup: Create Test User, Org, Unit
    -- We need a real user ID from the system to satisfy foreign key constraints if they exist on public.user_info
    SELECT id INTO v_test_user FROM public.user_info LIMIT 1;
    
    IF v_test_user IS NULL THEN
        RAISE EXCEPTION 'No users found in public.user_info to run test against.';
    END IF;

    -- Mock Auth so that functionality believing it is called by this user works
    PERFORM set_config('request.jwt.claim.sub', v_test_user::text, true);

    -- Create Org & Unit to link the account to (required by our typical flow)
    INSERT INTO public.organizations (title) VALUES ('Test Creator Admin Org') RETURNING id INTO v_org_id;
    -- Make user admin of org (optional but good practice)
    INSERT INTO public.organization_users (organization, "user", is_admin) VALUES (v_org_id, v_test_user, true);
    
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_org_id) RETURNING id INTO v_unit_id;
    -- Make user manager of unit (REQUIRED by update_bank_account security check)
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_test_user, true);

    -- 2. Create Bank Account
    -- update_bank_account(id, number, title, type, currencies, human_readable, unit_id)
    -- Passing NULL as ID means "Create new"
    RAISE NOTICE 'Creating Bank Account...';
    
    SELECT public.update_bank_account(
        NULL::bigint,
        ('TEST-' || floor(random()*1000000)::text || '/2010')::text,
        'Test Admin Creator Acc'::text, 
        'FIO'::text, 
        ARRAY['CZK']::text[], 
        NULL::text, 
        v_unit_id
    ) INTO v_acc_id;

    IF v_acc_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create bank account.';
    END IF;

    -- 3. Verify User is Admin
    RAISE NOTICE 'Verifying Admin Status...';
    
    SELECT is_admin INTO v_is_admin
    FROM eshop.bank_account_users
    WHERE bank_account = v_acc_id AND "user" = v_test_user;

    IF v_is_admin IS NULL THEN
        RAISE EXCEPTION 'User was not added to bank_account_users table.';
    END IF;

    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'User was added but is_admin is FALSE. Expected TRUE.';
    END IF;

    RAISE NOTICE 'SUCCESS: Creator was automatically made admin.';

    -- Rollback is handled by the test runner usually, but if running manually, changes persist.
    -- Since this is just a verification script, we can rely on transactional rollback
    -- or explicit cleanup if we were running in a long-lived env. 
    -- For now, we assume the test runner handles it or we accept the garbage data in dev.
END;
$$ LANGUAGE plpgsql;
