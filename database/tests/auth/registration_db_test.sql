
DO $$
DECLARE
    v_org_id bigint := 1;
    v_test_run_id text := floor(random()*1000000)::text;
    v_email text := 'test.db.reg.' || v_test_run_id || '@example.com';
    v_password text := 'password123';
    v_payload_flat jsonb := '{"name": "Jan", "surname": "Novak", "lang": "cs", "firstName": "Ignored"}';
    v_payload_nested jsonb := '{"data": {"firstName": "Jan", "lastName": "Novak"}, "email": "ignored@example.com"}';
    v_user_id uuid;
    v_result_json jsonb;
    v_user_name text;
    v_user_surname text;
    v_email_delivery text;
BEGIN
    -- 0. Enable Registration for Org 1 (Required for WS function)
    UPDATE organizations 
    SET data = jsonb_set(COALESCE(data, '{}'), '{IS_REGISTRATION_ENABLED}', 'true') 
    WHERE id = v_org_id;

    -- 1. Test FLAT payload (Correct Format)
    -- Insert user using the specialized registration function
    v_result_json := create_user_from_registration(v_org_id, v_email, v_password, v_payload_flat);
    
    -- Extract ID from JSON result: {"code": 200, "id": "..."}
    IF (v_result_json->>'code')::int != 200 THEN
        RAISE EXCEPTION 'Registration failed: %', v_result_json;
    END IF;
    
    v_user_id := (v_result_json->>'id')::uuid;
    
    -- Verify user_info
    SELECT name, surname INTO v_user_name, v_user_surname
    FROM public.user_info
    WHERE id = v_user_id;
    
    PERFORM assert_not_null(v_user_name, 'Name should not be null');
    PERFORM assert_eq(v_user_name, 'Jan', 'Name should be extracted from flat payload');
    PERFORM assert_eq(v_user_surname, 'Novak', 'Surname should be extracted from flat payload');
    SELECT email_delivery INTO v_email_delivery
      FROM public.user_info WHERE id = v_user_id;
    PERFORM assert_true(v_email_delivery IS NULL,
        'ordinary registration does not need a delivery override');
    PERFORM assert_eq(public.get_user_delivery_email(v_user_id), lower(v_email),
        'ordinary registration delivers to the canonical account email');

    -- Verify Automatic Unit Creation
    DECLARE
        v_unit_id bigint;
        v_unit_title text;
        v_is_manager boolean;
        v_is_editor boolean;
        v_is_editor_view boolean;
    BEGIN
        SELECT unit, is_manager, is_editor, is_editor_view 
        INTO v_unit_id, v_is_manager, v_is_editor, v_is_editor_view
        FROM public.unit_users
        WHERE "user" = v_user_id;

        PERFORM assert_not_null(v_unit_id, 'New user should be automatically linked to a unit');
        PERFORM assert_true(v_is_manager, 'User should be manager of the new unit');
        PERFORM assert_true(v_is_editor, 'User should be editor of the new unit');
        PERFORM assert_true(v_is_editor_view, 'User should be editor view of the new unit');

        SELECT title INTO v_unit_title FROM public.units WHERE id = v_unit_id;
        PERFORM assert_eq(v_unit_title, 'Moje akce', 'Automatic unit should be named "Moje akce"');
        
        -- Verify Unit Data
        DECLARE
            v_unit_data jsonb;
        BEGIN
            SELECT data INTO v_unit_data FROM public.units WHERE id = v_unit_id;
            PERFORM assert_eq(v_unit_data->>'reply_to', lower(trim(v_email)), 'Unit reply_to should match user email');
            PERFORM assert_eq(v_unit_data->>'timezone', 'Europe/Prague', 'Unit timezone should be Europe/Prague');
        END;
    END;
    
    
    -- 2. Test NESTED payload (Incorrect Format - Regression Test)
    v_email := 'test.db.reg.nested.' || v_test_run_id || '@example.com';
    v_result_json := create_user_from_registration(v_org_id, v_email, v_password, v_payload_nested);
    v_user_id := (v_result_json->>'id')::uuid;
    
    SELECT name, surname INTO v_user_name, v_user_surname
    FROM public.user_info
    WHERE id = v_user_id;

    -- The current implementation uses COALESCE(..., ''), so it returns empty string if key is missing
    PERFORM assert_eq(v_user_name, '', 'Name should be empty for nested payload (confirming extraction logic ignores nested data)');
    PERFORM assert_eq(v_user_surname, '', 'Surname should be empty for nested payload');


    -- 3. Test Localized Unit Title (Explicit unit_title argument)
    v_email := 'test.db.reg.en.' || v_test_run_id || '@example.com';
    -- Calling with 5th argument 'My events'
    v_result_json := create_user_from_registration(v_org_id, v_email, v_password, v_payload_flat, 'My events');
    v_user_id := (v_result_json->>'id')::uuid;
    
    DECLARE
        v_en_unit_id bigint;
        v_en_unit_title text;
    BEGIN
        SELECT unit INTO v_en_unit_id FROM public.unit_users WHERE "user" = v_user_id LIMIT 1;
        SELECT title INTO v_en_unit_title FROM public.units WHERE id = v_en_unit_id;
        
        PERFORM assert_eq(v_en_unit_title, 'My events', 'Unit title should be localized to "My events"');
    END;

    RAISE NOTICE 'Registration DB Logic Verified';
    
EXCEPTION WHEN OTHERS THEN
    -- If assert fails, it raises exception using assert_fail
    RAISE;
END;
$$ LANGUAGE plpgsql;
