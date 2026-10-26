-- Test: get_my_admin_organization_id
-- Validates:
-- 1. Returns ID for admin user.
-- 2. Returns NULL for non-admin user.
-- 3. Returns NULL for user with no organization.



DO $$
DECLARE
  v_admin_id uuid := '00000000-0000-0000-0000-000000000001';
  v_member_id uuid := '00000000-0000-0000-0000-000000000002';
  v_other_id uuid := '00000000-0000-0000-0000-000000000003';
  v_org_id bigint := 100;
  v_result_id bigint;
BEGIN
  -- Cleanup
  TRUNCATE auth.users CASCADE;
  TRUNCATE organizations CASCADE;

  -- Setup Context
  INSERT INTO organizations (id, title) VALUES (v_org_id, 'Test Org');

  INSERT INTO auth.users (id, email) VALUES
    (v_admin_id, 'admin@example.com'),
    (v_member_id, 'member@example.com'),
    (v_other_id, 'other@example.com');

  INSERT INTO user_info (id, email_readonly, name, surname, organization) VALUES
    (v_admin_id, 'admin@example.com', 'Admin', 'User', v_org_id),
    (v_member_id, 'member@example.com', 'Member', 'User', v_org_id),
    (v_other_id, 'other@example.com', 'Other', 'User', v_org_id); -- Org required by constraint

  INSERT INTO organization_users ("user", organization, is_admin) VALUES
    (v_admin_id, v_org_id, true),
    (v_member_id, v_org_id, false);

  -- Case 1: Admin User
  PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);
  v_result_id := get_my_admin_organization_id();
  
  IF v_result_id IS NULL OR v_result_id != v_org_id THEN
    RAISE EXCEPTION 'Case 1 Failed: Expected %, got %', v_org_id, v_result_id;
  END IF;

  -- Case 2: Member User (Not Admin)
  PERFORM set_config('request.jwt.claim.sub', v_member_id::text, true);
  v_result_id := get_my_admin_organization_id();
  
  IF v_result_id IS NOT NULL THEN
    RAISE EXCEPTION 'Case 2 Failed: Expected NULL, got %', v_result_id;
  END IF;

  -- Case 3: User with no Org (checking logic, although user_info forces org link due to constraint? 
  -- actually organization_users is the table that matters for the logic.)
  PERFORM set_config('request.jwt.claim.sub', v_other_id::text, true);
  v_result_id := get_my_admin_organization_id();
  
  IF v_result_id IS NOT NULL THEN
    RAISE EXCEPTION 'Case 3 Failed: Expected NULL, got %', v_result_id;
  END IF;

END $$ LANGUAGE plpgsql;
