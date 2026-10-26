BEGIN;

-- Contract coverage for feedback ownership, upsert/read/delete, feature helper,
-- participant gating and editor export. All fixture identities and labels are
-- generated in the transaction; only domain enum values and response codes are
-- asserted.

DO $$
DECLARE
    v_oc             bigint;
    v_disabled_oc    bigint;
    v_event          bigint;
    v_limited_event  bigint;
    v_editor         uuid;
    v_admin          uuid;
    v_user           uuid;
    v_editor_login   text := 'feedback_contract_editor_' || gen_random_uuid();
    v_admin_login    text := 'feedback_contract_admin_' || gen_random_uuid();
    v_user_login     text := 'feedback_contract_user_' || gen_random_uuid();
    v_client         uuid := gen_random_uuid();
    v_other_client   uuid := gen_random_uuid();
    v_first_id       bigint;
    v_admin_target_id bigint;
    v_res            jsonb;
BEGIN
    -- The user test helper relies on the schema defaults pointing at tenant 1.
    -- Keep this contract test self-contained on an empty local baseline.
    INSERT INTO public.organizations (id, title)
    VALUES (1, gen_random_uuid()::text)
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.units (id, title, organization)
    VALUES (1, gen_random_uuid()::text, 1)
    ON CONFLICT (id) DO NOTHING;

    PERFORM create_user_for_test(
        v_editor_login,
        gen_random_uuid() || '@test.local'
    );
    PERFORM create_user_for_test(
        v_user_login,
        gen_random_uuid() || '@test.local'
    );
    PERFORM create_user_for_test(
        v_admin_login,
        gen_random_uuid() || '@test.local'
    );
    v_editor := get_user_id(v_editor_login);
    v_admin := get_user_id(v_admin_login);
    v_user := get_user_id(v_user_login);

    INSERT INTO public.occasions (
        title, link, start_time, end_time, is_open, features
    )
    VALUES (
        gen_random_uuid()::text,
        gen_random_uuid()::text,
        now() - interval '1 day',
        now() + interval '1 day',
        true,
        jsonb_build_array(jsonb_build_object(
            'code', 'event_feedback',
            'is_enabled', true
        ))
    )
    RETURNING id INTO v_oc;

    INSERT INTO public.organization_users (organization, "user", is_admin)
    SELECT organization, v_admin, true
    FROM public.occasions
    WHERE id = v_oc;

    INSERT INTO public.occasions (
        title, link, start_time, end_time, is_open, features
    )
    VALUES (
        gen_random_uuid()::text,
        gen_random_uuid()::text,
        now() - interval '1 day',
        now() + interval '1 day',
        true,
        '[]'::jsonb
    )
    RETURNING id INTO v_disabled_oc;

    PERFORM assert_true(
        public.get_is_event_feedback_enabled_on_occasion(v_oc),
        'feature helper returns true for enabled occasion'
    );
    PERFORM assert_true(
        NOT public.get_is_event_feedback_enabled_on_occasion(v_disabled_oc),
        'feature helper returns false for disabled occasion'
    );

    INSERT INTO public.occasion_users (
        occasion, "user", is_editor, is_editor_view, is_approved
    )
    VALUES (v_oc, v_editor, true, true, true);

    INSERT INTO public.occasion_users (occasion, "user", is_approved)
    VALUES (v_oc, v_user, true);

    INSERT INTO public.events (
        occasion, title, start_time, end_time, data
    )
    VALUES (
        v_oc,
        gen_random_uuid()::text,
        now() - interval '1 hour',
        now() + interval '1 hour',
        jsonb_build_object('feedback_enabled', 'true')
    )
    RETURNING id INTO v_event;

    INSERT INTO public.events (
        occasion, title, start_time, end_time, max_participants, data
    )
    VALUES (
        v_oc,
        gen_random_uuid()::text,
        now() - interval '1 hour',
        now() + interval '1 hour',
        1,
        jsonb_build_object('feedback_enabled', 'true')
    )
    RETURNING id INTO v_limited_event;

    -- Anonymous identity is stable, isolated by client_id and upserted.
    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_res := public.submit_event_feedback(
        v_event, 'happy', gen_random_uuid()::text, v_client
    );
    PERFORM assert_eq(v_res->>'code', '200', 'anonymous submit succeeds');
    v_first_id := (v_res->'data'->>'id')::bigint;

    v_res := public.get_event_feedback(v_event, v_client);
    PERFORM assert_eq(
        (v_res->'data'->>'id')::bigint,
        v_first_id,
        'anonymous read returns own feedback'
    );

    v_res := public.get_event_feedback(v_event, v_other_client);
    PERFORM assert_true(
        v_res->'data' = 'null'::jsonb,
        'other client cannot read it'
    );

    v_res := public.submit_event_feedback(
        v_event, 'neutral', gen_random_uuid()::text, v_client
    );
    PERFORM assert_eq(
        (v_res->'data'->>'id')::bigint,
        v_first_id,
        'anonymous retry updates the same row'
    );

    v_res := public.delete_event_feedback(v_event, v_other_client);
    PERFORM assert_eq(
        (v_res->'data'->>'deleted')::integer,
        0,
        'other client cannot delete it'
    );

    v_res := public.delete_event_feedback(v_event, v_client);
    PERFORM assert_eq(
        (v_res->'data'->>'deleted')::integer,
        1,
        'owner client deletes it'
    );

    v_res := public.submit_event_feedback(
        v_event, 'happy', 'admin deletion target', v_client
    );
    v_admin_target_id := (v_res->'data'->>'id')::bigint;

    -- Limited event requires an authoritative participant relation.
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    v_res := public.submit_event_feedback(v_limited_event, 'sad');
    PERFORM assert_eq(v_res->>'code', '403', 'non-participant is rejected');

    INSERT INTO public.event_users (event, "user")
    VALUES (v_limited_event, v_user);

    v_res := public.submit_event_feedback(v_limited_event, 'sad');
    PERFORM assert_eq(v_res->>'code', '200', 'participant submit succeeds');

    v_res := public.get_event_feedback(v_limited_event);
    PERFORM assert_eq(
        v_res->'data'->>'event',
        v_limited_event::text,
        'signed-in read returns own feedback'
    );

    v_res := public.get_event_feedback_export_for_edit(v_oc);
    PERFORM assert_eq(v_res->>'code', '403', 'regular user cannot export');

    BEGIN
        PERFORM public.delete_event_feedback_for_edit_client_sync_v1(
            v_oc, v_admin_target_id, gen_random_uuid()
        );
        RAISE EXCEPTION 'regular user deleted another feedback row';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    PERFORM assert_true(
        EXISTS (
            SELECT 1 FROM public.event_feedback WHERE id = v_admin_target_id
        ),
        'regular user cannot delete another feedback row'
    );

    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
    BEGIN
        PERFORM public.delete_event_feedback_for_edit_client_sync_v1(
            v_oc, v_admin_target_id, gen_random_uuid()
        );
        RAISE EXCEPTION 'occasion editor deleted another feedback row';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM assert_true(
        EXISTS (
            SELECT 1 FROM public.event_feedback WHERE id = v_admin_target_id
        ),
        'occasion editor without is_admin cannot delete another feedback row'
    );

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.get_event_feedback_export_for_edit(v_oc);
    PERFORM assert_eq(v_res->>'code', '200', 'admin can load feedback table');
    v_res := public.delete_event_feedback_for_edit_client_sync_v1(
        v_oc, v_admin_target_id, gen_random_uuid()
    );
    PERFORM assert_eq(v_res->>'status', 'applied', 'admin delete is applied');
    PERFORM assert_false(
        EXISTS (
            SELECT 1 FROM public.event_feedback WHERE id = v_admin_target_id
        ),
        'admin deletes another feedback row'
    );

    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
    v_res := public.get_event_feedback_export_for_edit(v_oc);
    PERFORM assert_eq(v_res->>'code', '200', 'editor can export');
    PERFORM assert_eq(
        jsonb_array_length(v_res->'data'),
        1,
        'export contains the remaining participant feedback'
    );

    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    v_res := public.delete_event_feedback(v_limited_event);
    PERFORM assert_eq(
        (v_res->'data'->>'deleted')::integer,
        1,
        'signed-in owner deletes own feedback'
    );
END $$ LANGUAGE plpgsql;

ROLLBACK;
