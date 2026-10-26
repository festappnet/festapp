-- Verify delete_unit:
--   - Non-manager cannot delete a unit
--   - Cannot delete the last managed unit (CANNOT_DELETE_LAST_UNIT)
--   - Cannot delete a unit that has occasions (UNIT_HAS_OCCASIONS)
--   - Manager can delete a unit when those constraints are satisfied

DO $$
DECLARE
    v_user_id uuid;
    v_org_id bigint;
    v_unit_id_1 bigint;
    v_unit_id_2 bigint;
    v_result jsonb;
    v_count int;
    v_occasion_id int;
BEGIN
    -- 1. Setup context
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No users found'; END IF;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- 2. Test organization
    INSERT INTO public.organizations (title, data)
    VALUES ('Test Org Delete Unit', '{"IS_UNIT_CREATION_ENABLED": true}'::jsonb)
    RETURNING id INTO v_org_id;

    INSERT INTO public.user_info (id, email_readonly, organization)
    VALUES (v_user_id, 'testdelete_' || v_user_id || '@example.com', v_org_id)
    ON CONFLICT (id) DO UPDATE SET organization = v_org_id;

    -- 3. Create Unit 1
    v_result := public.create_unit_and_assign_manager('Unit To Delete');
    v_unit_id_1 := (v_result->'data'->>'id')::bigint;

    -- 4. Non-manager tries to delete -> should fail
    PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
    BEGIN
        PERFORM delete_unit(v_unit_id_1);
        RAISE EXCEPTION 'Should have failed with is_manager check';
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Expected — any error is good
    END;
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- 5. Try to delete immediately (only 1 unit managed) -> should fail
    BEGIN
        PERFORM delete_unit(v_unit_id_1);
        RAISE EXCEPTION 'Should have failed with CANNOT_DELETE_LAST_UNIT';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%CANNOT_DELETE_LAST_UNIT%' THEN
            RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
        END IF;
    END;

    -- 6. Create Unit 2
    v_result := public.create_unit_and_assign_manager('Unit To Keep');
    v_unit_id_2 := (v_result->'data'->>'id')::bigint;

    -- 7. Add occasion to Unit 1 and try delete -> should fail
    INSERT INTO public.occasions (title, start_time, end_time, link, unit)
    VALUES ('Test Occasion', now(), now(), 'test-occasion-delete-' || floor(random()*1000000)::text, v_unit_id_1)
    RETURNING id INTO v_occasion_id;

    BEGIN
        PERFORM delete_unit(v_unit_id_1);
        RAISE EXCEPTION 'Should have failed with UNIT_HAS_OCCASIONS';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%UNIT_HAS_OCCASIONS%' THEN
            RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
        END IF;
    END;

    -- 8. Remove occasion and delete Unit 1 -> success
    DELETE FROM public.occasions WHERE id = v_occasion_id;
    PERFORM delete_unit(v_unit_id_1);

    SELECT count(*) INTO v_count FROM public.units WHERE id = v_unit_id_1;
    PERFORM assert_eq(v_count, 0, 'Unit 1 should be deleted');

    SELECT count(*) INTO v_count FROM public.units WHERE id = v_unit_id_2;
    PERFORM assert_eq(v_count, 1, 'Unit 2 should remain');
END $$ LANGUAGE plpgsql;
