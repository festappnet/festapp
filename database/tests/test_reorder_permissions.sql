-- Test: Verify reordering permissions (Reproduction)
BEGIN;

DO $$
DECLARE
  v_org_id bigint;
  v_unit_id bigint;
  v_account_id bigint;
  -- Use existing user from DB to satisfy FK constraints
  v_user_id uuid := 'e805fdc3-c43e-4f44-88da-0f7d997c2947'::uuid; 
BEGIN
  -- Spoof Auth (simulate this user is logged in)
  PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
  
  -- Create Organization
  INSERT INTO public.organizations (title) VALUES ('Test Org Reproduce') RETURNING id INTO v_org_id;
  
  -- Create Unit (User is Manager)
  INSERT INTO public.units (title, organization) VALUES ('Test Unit Reproduce', v_org_id) RETURNING id INTO v_unit_id;
  -- We must check if this user is already added? No, new unit shouldn't have them.
  -- But wait, unit_users likely has unique constraint on (unit, user).
  -- Since v_unit_id is new, it should be fine.
  INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

  -- Create Bank Account (User is NOT Admin)
  INSERT INTO eshop.bank_accounts (type, account_number, title) VALUES ('FIO', '123/2010', 'Other Admin Account') RETURNING id INTO v_account_id;
  
  -- Pre-link the account
  INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_account_id, 100);

  -- Attempt to Reorder (Update Priority to 200)
  -- This SHOULD SUCCEED now.
  BEGIN
    PERFORM public.link_bank_account_to_unit(v_account_id, v_unit_id, 200, false);
    RAISE NOTICE 'Test Passed: Reordering succeeded for Unit Manager.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Test Failed: Got unexpected error: %', SQLERRM;
  END;

END $$;

ROLLBACK;
