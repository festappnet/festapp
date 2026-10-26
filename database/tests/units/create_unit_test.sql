-- Verify create_unit_and_assign_manager:
--   - Creates a new unit owned by the calling user
--   - Returns code 200 with unit id
--   - Sets timezone (Europe/Prague) and reply_to (from user email)
--   - Grants caller manager + editor on the new unit

DO $$
DECLARE
    v_user_id uuid;
    v_org_id bigint;
    v_result jsonb;
    v_unit_id bigint;
    v_unit_data jsonb;
    v_unit_title text;
    v_is_manager boolean;
    v_is_editor boolean;
BEGIN
    -- 1. Fetch a real user to impersonate
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No users found in auth.users to test with.';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- 2. Create test organization with unit creation enabled
    INSERT INTO public.organizations (title, data)
    VALUES ('Test Org for Unit Creation', '{"IS_UNIT_CREATION_ENABLED": true}'::jsonb)
    RETURNING id INTO v_org_id;

    -- 3. Ensure user_info points at this org (preserve original on cleanup via ROLLBACK)
    INSERT INTO public.user_info (id, email_readonly, organization)
    VALUES (v_user_id, 'testuser_' || v_user_id || '@example.com', v_org_id)
    ON CONFLICT (id) DO UPDATE SET email_readonly = 'testuser_' || v_user_id || '@example.com', organization = v_org_id;

    -- 4. Execute function
    v_result := public.create_unit_and_assign_manager('Test Unit Manual Creation');

    -- 5. Validate response
    PERFORM assert_eq(v_result->>'code', '200', 'Response code should be 200');
    v_unit_id := (v_result->'data'->>'id')::bigint;
    PERFORM assert_not_null(v_unit_id::text, 'New Unit ID should not be null');

    -- 6. Validate unit data
    SELECT title, data INTO v_unit_title, v_unit_data
    FROM public.units WHERE id = v_unit_id;

    PERFORM assert_eq(v_unit_title, 'Test Unit Manual Creation', 'Unit title should match');
    PERFORM assert_eq(v_unit_data->>'timezone', 'Europe/Prague', 'Timezone should be Europe/Prague');
    PERFORM assert_eq(v_unit_data->>'reply_to', 'testuser_' || v_user_id || '@example.com', 'Reply-to should be set from user email');

    -- 7. Validate permissions
    SELECT is_manager, is_editor INTO v_is_manager, v_is_editor
    FROM public.unit_users WHERE unit = v_unit_id AND "user" = v_user_id;

    PERFORM assert_true(v_is_manager, 'Creator should be manager');
    PERFORM assert_true(v_is_editor, 'Creator should be editor');
END $$ LANGUAGE plpgsql;
