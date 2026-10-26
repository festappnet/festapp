-- Regression coverage for authoritative CSV group assignment.
DO $$
DECLARE
    v_occasion bigint;
    v_old_group bigint;
    v_game_group bigint;
BEGIN
    PERFORM create_user_for_test('iuga_editor', 'iuga_editor@test.local');
    PERFORM create_user_for_test('iuga_user', 'iuga_user@test.local');
    PERFORM create_user_for_test('iuga_plain', 'iuga_plain@test.local');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES ('CSV group import test', 'iuga-' || gen_random_uuid(),
            now(), now() + interval '1 day', true)
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasion_users
        (occasion, "user", is_editor, is_editor_view, is_approved)
    VALUES
        (v_occasion, get_user_id('iuga_editor'), true, true, true),
        (v_occasion, get_user_id('iuga_user'), false, false, true),
        (v_occasion, get_user_id('iuga_plain'), false, false, true);

    INSERT INTO public.user_group_info (occasion, title)
    VALUES (v_occasion, 'Testovací skupina CSV')
    RETURNING id INTO v_old_group;

    INSERT INTO public.user_group_info (occasion, title, type)
    VALUES (v_occasion, 'Herní skupina', 'game')
    RETURNING id INTO v_game_group;

    INSERT INTO public.user_groups ("user", "group", is_admin)
    VALUES
        (get_user_id('iuga_user'), v_old_group, true),
        (get_user_id('iuga_user'), v_game_group, false);

    CREATE TEMP TABLE _iuga (occasion bigint, game_group bigint);
    INSERT INTO _iuga VALUES (v_occasion, v_game_group);
END $$;

-- A later invalid row rolls the earlier row back with the whole function call.
DO $$
DECLARE
    v_occasion bigint := (SELECT occasion FROM _iuga);
    v_user uuid := get_user_id('iuga_user');
    v_rejected boolean := false;
BEGIN
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('iuga_editor')::text, true);
    BEGIN
        PERFORM public.import_user_group_assignments(
            v_occasion,
            jsonb_build_array(
                jsonb_build_object(
                    'user_id', v_user,
                    'group_title', 'Must Roll Back'),
                jsonb_build_object(
                    'user_id', '00000000-0000-0000-0000-000000000000',
                    'group_title', 'Invalid User'))
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'USER_NOT_ON_OCCASION';
    END;

    PERFORM assert_eq(v_rejected, true, 'invalid later row rejects the batch');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_group_info
         WHERE occasion = v_occasion AND title = 'Must Roll Back'),
        0::bigint,
        'group creation from an earlier row was rolled back');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups ug
         JOIN public.user_group_info ugi ON ugi.id = ug."group"
         WHERE ug."user" = v_user AND ugi.occasion = v_occasion
           AND ugi.type IS NULL),
        1::bigint,
        'original membership survives rollback of the earlier row');
END $$;

DO $$
DECLARE
    v_occasion bigint := (SELECT occasion FROM _iuga);
    v_user uuid := get_user_id('iuga_user');
    v_new_group bigint;
BEGIN
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('iuga_editor')::text, true);

    PERFORM public.import_user_group_assignments(
        v_occasion,
        jsonb_build_array(jsonb_build_object(
            'user_id', v_user,
            'group_title', 'Přesunutá testovací skupina CSV'))
    );

    SELECT id INTO v_new_group
    FROM public.user_group_info
    WHERE occasion = v_occasion
      AND title = 'Přesunutá testovací skupina CSV'
      AND type IS NULL;

    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups ug
         JOIN public.user_group_info ugi ON ugi.id = ug."group"
         WHERE ug."user" = v_user AND ugi.occasion = v_occasion
           AND ugi.type IS NULL),
        1::bigint,
        'user belongs to exactly one standard group after move');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups
         WHERE "user" = v_user AND "group" = v_new_group),
        1::bigint,
        'user was inserted into the requested group');
    PERFORM assert_eq(
        (SELECT imported_user->>'group_title'
         FROM jsonb_array_elements(
             public.get_occasion_users_for_edit(v_occasion)::jsonb
                 #> '{data,occasion_users}') AS imported_user
         WHERE imported_user->>'user' = v_user::text),
        'Přesunutá testovací skupina CSV',
        'users editor exposes the standard group title');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups
         WHERE "user" = v_user AND "group" = (SELECT game_group FROM _iuga)),
        1::bigint,
        'typed game-group membership remains untouched');

    PERFORM public.import_user_group_assignments(
        v_occasion,
        jsonb_build_array(jsonb_build_object(
            'user_id', v_user,
            'group_title', ' přesunutá TESTOVACÍ skupina csv '))
    );
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_group_info
         WHERE occasion = v_occasion AND type IS NULL
           AND lower(btrim(title)) = 'přesunutá testovací skupina csv'),
        1::bigint,
        'reimport reuses the existing normalized group title');

    PERFORM public.import_user_group_assignments(
        v_occasion,
        jsonb_build_array(jsonb_build_object(
            'user_id', v_user,
            'group_title', ''))
    );
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups ug
         JOIN public.user_group_info ugi ON ugi.id = ug."group"
         WHERE ug."user" = v_user AND ugi.occasion = v_occasion
           AND ugi.type IS NULL),
        0::bigint,
        'blank group removes standard-group membership');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_groups
         WHERE "user" = v_user AND "group" = (SELECT game_group FROM _iuga)),
        1::bigint,
        'blank standard group still leaves game group untouched');
END $$;

DO $$
DECLARE
    v_occasion bigint := (SELECT occasion FROM _iuga);
    v_rejected boolean := false;
BEGIN
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('iuga_plain')::text, true);
    BEGIN
        PERFORM public.import_user_group_assignments(
            v_occasion,
            jsonb_build_array(jsonb_build_object(
                'user_id', get_user_id('iuga_user'),
                'group_title', 'Unauthorized'))
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'NOT_AUTHORIZED';
    END;
    PERFORM assert_eq(v_rejected, true, 'non-editor is rejected');
END $$;
