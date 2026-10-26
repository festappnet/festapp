-- Test for public.get_bank_accounts_for_unit_management(p_unit_id)


-- Test for public.get_bank_accounts_for_unit_management(p_unit_id)

DO $$
DECLARE
    v_user_manager uuid;
    v_user_other uuid;
    v_org_id bigint;
    v_unit_id bigint;
    v_acc_fio bigint;
    v_acc_cash bigint;
    v_foreign_org bigint;
    v_foreign_unit bigint;
    v_context jsonb;
    v_count int;
    v_fio_rec record;
BEGIN
    RAISE NOTICE 'Starting get_bank_accounts_for_unit_management Test...';

    -- 1. Setup Data
    SELECT id INTO v_user_manager FROM public.user_info LIMIT 1;
    -- Find another user or create one? Assuming at least one exists.
    -- If only 1 exists, we'll assume permission failure if we strip roles.
    -- Better: Insert a dummy user.
    v_user_other := gen_random_uuid();
    INSERT INTO auth.users (id, aud, role, email, created_at) 
    VALUES (v_user_other, 'authenticated', 'authenticated', 'other@test.com', now());
    
    INSERT INTO public.user_info (id) VALUES (v_user_other);

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org') RETURNING id INTO v_org_id;
    INSERT INTO public.organization_users (organization, "user", is_admin) VALUES (v_org_id, v_user_manager, true);
    
    INSERT INTO public.units (title, organization) VALUES ('Test Unit', v_org_id) RETURNING id INTO v_unit_id;
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_manager, true);
    -- Multiple unit roles must remain scoped to the requested unit.
    INSERT INTO public.organizations(title) VALUES ('Foreign bank context') RETURNING id INTO v_foreign_org;
    INSERT INTO public.units(title,organization) VALUES ('Foreign bank unit',v_foreign_org)
      RETURNING id INTO v_foreign_unit;
    INSERT INTO public.unit_users(unit,"user",is_manager,is_editor)
      VALUES(v_foreign_unit,v_user_manager,false,true);
    -- v_user_other is NOT manager

    -- Create Bank Accounts
    -- FIO (Should be returned)
    INSERT INTO eshop.bank_accounts (title, type, account_number, supported_currencies, pairing_code) 
    VALUES ('Fio Test', 'FIO', '123/2010', ARRAY['CZK'], 'fiotest001') 
    RETURNING id INTO v_acc_fio;

    -- CASH (Should be excluded)
    INSERT INTO eshop.bank_accounts (title, type, supported_currencies, pairing_code) 
    VALUES ('Cash Test', 'CASH', ARRAY['CZK'], 'cashtest01') 
    RETURNING id INTO v_acc_cash;
    
    -- Link FIO to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_fio, 1);
    
    -- Link CASH to Unit (it should exist in link table, but function filters it out)
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_cash, 2);


    -- 2. Test Success (As Manager)
    PERFORM set_config('request.jwt.claim.sub', v_user_manager::text, true);
    
    -- Execute
    SELECT COUNT(*) INTO v_count FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    
    -- Expect 1 result (FIO), not 2 (CASH excluded)
    IF v_count != 1 THEN
        RAISE EXCEPTION 'Expected 1 account (FIO), got %', v_count;
    END IF;

    -- Verify fields
    SELECT * INTO v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id) LIMIT 1;
    
    IF v_fio_rec.title != 'Fio Test' THEN
        RAISE EXCEPTION 'Incorrect title returned.';
    END IF;
    
    IF v_fio_rec.type != 'FIO' THEN
         RAISE EXCEPTION 'Incorrect type returned.';
    END IF;
    
    -- Manager without bank admin rights sees only connection health.
    INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,
      bank_account_id,physical_account,provider,mode,state,pairing_code,manifest_sha256)
    VALUES('management-test','festapp','management-test',v_acc_fio,'123/2010',
      'FIO','api','connected','abcdef0123',repeat('a',64));
    SELECT * INTO v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_fio_rec.is_admin IS DISTINCT FROM false OR
       v_fio_rec.bank_sync IS DISTINCT FROM '{"state":"connected","mode":"api"}'::jsonb THEN
      RAISE EXCEPTION 'Non-admin must receive only connection state and mode';
    END IF;
    INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin)
      VALUES(v_acc_fio,v_user_manager,true);
    SELECT * INTO v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_fio_rec.is_admin IS DISTINCT FROM true OR
       v_fio_rec.bank_sync->>'receiving_address' IS DISTINCT FROM 'abcdef0123@banksync.festapp.net' THEN
      RAISE EXCEPTION 'Bank admin must receive authorized connection details';
    END IF;
    
    -- Historical imports can leave several memberships for the same user.
    -- Effective roles are existential and each linked account appears once.
    INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin,is_support)
      VALUES(v_acc_fio,v_user_manager,false,true),(v_acc_fio,v_user_manager,true,false);
    IF public.get_is_admin_on_bank_account(v_acc_fio) IS DISTINCT FROM true OR
       public.can_read_bank_account_users(v_acc_fio) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Duplicate memberships must preserve effective bank roles';
    END IF;
    SELECT count(*) INTO v_count FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_count <> 1 THEN RAISE EXCEPTION 'Duplicate memberships repeated the account: %',v_count; END IF;
    SELECT * INTO STRICT v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_fio_rec.is_admin IS DISTINCT FROM true OR
       v_fio_rec.bank_sync->>'receiving_address' IS DISTINCT FROM 'abcdef0123@banksync.festapp.net' THEN
      RAISE EXCEPTION 'Duplicate memberships lost authorized connection details';
    END IF;
    UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=v_acc_fio AND "user"=v_user_manager;
    IF public.get_is_admin_on_bank_account(v_acc_fio) IS DISTINCT FROM false OR
       public.can_manage_bank_account(v_acc_fio) IS DISTINCT FROM false OR
       public.can_read_bank_account_users(v_acc_fio) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Duplicate support memberships must not grant bank administration';
    END IF;
    UPDATE eshop.bank_account_users SET is_admin=true WHERE bank_account=v_acc_fio AND "user"=v_user_manager;

    -- Keep these calls separate: an optional organization RPC failure must not be
    -- mistaken for a bank permission failure (SQLSTATE/context identifies owner).
    v_context := public.get_current_organization_data();
    IF v_context->>'code' <> '200' THEN
      RAISE EXCEPTION 'Organization admin context missing: %',v_context;
    END IF;
    BEGIN
      PERFORM public.get_bank_accounts_for_unit_management(v_foreign_unit);
      RAISE EXCEPTION 'Editor in another organization must not get manager bank access';
    EXCEPTION WHEN insufficient_privilege THEN
      IF SQLERRM <> 'User is not manager.' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'Success Case Passed.';


    -- The provider failure remains visible until a successful bank pull.
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    PERFORM public.record_bank_sync_pull(c.id,NULL,'fio_token_invalid_or_inactive')
      FROM eshop.bank_sync_connections c WHERE c.bank_account_id=v_acc_fio;
    SELECT * INTO v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_fio_rec.bank_sync->>'state' <> 'degraded' OR
       v_fio_rec.bank_sync->>'last_error' <> 'fio_token_invalid_or_inactive' THEN
      RAISE EXCEPTION 'Bank failure must be visible in account settings';
    END IF;
    PERFORM public.record_bank_sync_pull(c.id,'2026-10-04T12:00:00Z',NULL)
      FROM eshop.bank_sync_connections c WHERE c.bank_account_id=v_acc_fio;
    SELECT * INTO v_fio_rec FROM public.get_bank_accounts_for_unit_management(v_unit_id);
    IF v_fio_rec.bank_sync->>'state' <> 'connected' OR
       v_fio_rec.bank_sync->>'last_error' IS NOT NULL THEN
      RAISE EXCEPTION 'Successful pull must clear the previous bank error';
    END IF;
    PERFORM set_config('request.jwt.claim.role','authenticated',true);

    -- 3. Test Failure (As Non-Manager)
    PERFORM set_config('request.jwt.claim.sub', v_user_other::text, true);
    
    BEGIN
        PERFORM public.get_bank_accounts_for_unit_management(v_unit_id);
        RAISE EXCEPTION 'Should have failed with permission error.';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'User is not manager.' THEN RAISE; END IF;
    END;

    v_context := public.get_current_organization_data();
    IF v_context->>'code' <> '403' THEN RAISE EXCEPTION 'Foreign organization context leaked'; END IF;
    RAISE NOTICE 'get_bank_accounts_for_unit_management Test Passed.';
END;
$$;
