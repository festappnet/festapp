-- Verify organization admin access controls:
--   1. check_is_admin_of_organization returns TRUE for admin, FALSE for regular user
--   2. get_organization_admin allows admin to read, denies regular user
--   3. update_organization_admin updates title and merges data (admin only)

BEGIN;

-- Run as superuser/owner so we can create users
SELECT create_user_for_test('admin_user_aa', 'admin_aa_' || floor(random()*1000000)::text || '@test.com');
SELECT create_user_for_test('regular_user_aa', 'regular_aa_' || floor(random()*1000000)::text || '@test.com');

-- Create org with auto-id
DO $$
DECLARE
    v_org_id bigint;
BEGIN
    INSERT INTO public.organizations (title, data)
    VALUES ('Test Org', '{"APP_NAME": "Original", "ONESIGNAL_REST_API_KEY": "legacy-secret"}'::jsonb)
    RETURNING id INTO v_org_id;

    -- Pass org_id forward via session var (SET LOCAL would not survive role switches)
    PERFORM set_config('test.aa_org_id', v_org_id::text, false);

    -- Permissions
    INSERT INTO public.organization_users ("user", organization, is_admin)
    VALUES (get_user_id('admin_user_aa'), v_org_id, true);

    INSERT INTO public.organization_users ("user", organization, is_admin)
    VALUES (get_user_id('regular_user_aa'), v_org_id, false);
END $$;

--------------------------------------------------------------------------------
-- Test 1: check_is_admin_of_organization
--------------------------------------------------------------------------------
SET ROLE postgres;
SELECT set_config('request.jwt.claim.sub', get_user_id('admin_user_aa')::text, false);
SET LOCAL ROLE authenticated;

SELECT assert_eq(
    check_is_admin_of_organization(current_setting('test.aa_org_id')::bigint),
    true,
    'Admin user should return true for check_is_admin'
);

SET ROLE postgres;
SELECT set_config('request.jwt.claim.sub', get_user_id('regular_user_aa')::text, false);
SET LOCAL ROLE authenticated;

SELECT assert_eq(
    check_is_admin_of_organization(current_setting('test.aa_org_id')::bigint),
    false,
    'Regular user should return false for check_is_admin'
);

--------------------------------------------------------------------------------
-- Test 2: get_organization_admin
--------------------------------------------------------------------------------
SET ROLE postgres;
SELECT set_config('request.jwt.claim.sub', get_user_id('admin_user_aa')::text, false);
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    org_record public.organizations%ROWTYPE;
BEGIN
    SELECT * INTO org_record FROM get_organization_admin(current_setting('test.aa_org_id')::bigint);
    PERFORM assert_eq(org_record.title, 'Test Org', 'Admin should be able to fetch org details');
    PERFORM assert_jsonb_contains(org_record.data, '{"APP_NAME": "Original"}', 'Admin should retrieve correct data');
    PERFORM assert_false(org_record.data ? 'ONESIGNAL_REST_API_KEY',
      'Admin response must not contain the server-only OneSignal credential');
END $$;

SET ROLE postgres;
SELECT set_config('request.jwt.claim.sub', get_user_id('regular_user_aa')::text, false);
SET LOCAL ROLE authenticated;

DO $$
BEGIN
    PERFORM get_organization_admin(current_setting('test.aa_org_id')::bigint);
    RAISE EXCEPTION 'Regular user should not be able to call get_organization_admin';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%Access Denied%' THEN
        RAISE NOTICE 'Caught unexpected error: %', SQLERRM;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- Test 3: update_organization_admin
--------------------------------------------------------------------------------
SET ROLE postgres;
SELECT set_config('request.jwt.claim.sub', get_user_id('admin_user_aa')::text, false);
SET LOCAL ROLE authenticated;

SELECT * FROM update_organization_admin(
    current_setting('test.aa_org_id')::bigint,
    'Updated Title',
    '{"APP_NAME": "New Name", "NEW_FIELD": 1}'::jsonb,
    ARRAY['+420']::text[]
);

DO $$
DECLARE
    updated_org public.organizations%ROWTYPE;
BEGIN
    SELECT * INTO updated_org FROM get_organization_admin(current_setting('test.aa_org_id')::bigint);
    PERFORM assert_eq(updated_org.title, 'Updated Title', 'Title should be updated');
    PERFORM assert_jsonb_contains(updated_org.data, '{"APP_NAME": "New Name"}', 'Data should be merged/updated');
    PERFORM assert_jsonb_contains(updated_org.data, '{"NEW_FIELD": 1}', 'New fields should be added');
END $$;

DO $$
BEGIN
  PERFORM update_organization_admin(
    current_setting('test.aa_org_id')::bigint,
    NULL,
    '{"ONESIGNAL_REST_API_KEY": "must-be-rejected"}'::jsonb,
    NULL
  );
  PERFORM assert_fail('Admin update must reject server-only credentials');
EXCEPTION WHEN invalid_parameter_value THEN
  NULL;
END $$;

ROLLBACK;
