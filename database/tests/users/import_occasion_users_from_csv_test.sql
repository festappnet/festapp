-- Regression coverage for the atomic, patch-based CSV import boundary.
DO $$
DECLARE
    v_org bigint;
    v_unit bigint;
    v_occasion bigint;
    v_old_group bigint;
BEGIN
    PERFORM create_user_for_test('csv_manager', 'csv_manager@test.local');
    PERFORM create_user_for_test('csv_existing', 'csv_existing@test.local');
    PERFORM create_user_for_test('csv_addable', 'csv_addable@test.local');
    PERFORM create_user_for_test('csv_delete', 'csv_delete@test.local');
    PERFORM create_user_for_test('csv_plain', 'csv_plain@test.local');

    INSERT INTO public.organizations (title)
    VALUES ('Atomic CSV import test')
    RETURNING id INTO v_org;

    INSERT INTO public.units (organization, title)
    VALUES (v_org, 'Atomic CSV import unit')
    RETURNING id INTO v_unit;

    INSERT INTO public.occasions (
        organization, unit, title, link, start_time, end_time, is_open
    ) VALUES (
        v_org, v_unit, 'Atomic CSV import occasion',
        'csv-atomic-' || gen_random_uuid(), now(), now() + interval '1 day', true
    ) RETURNING id INTO v_occasion;

    INSERT INTO public.role_info (id, title, occasion)
    VALUES (1, 'CSV role 1', v_occasion), (2, 'CSV role 2', v_occasion)
    ON CONFLICT (id) DO NOTHING;

    UPDATE public.user_info
       SET organization = v_org,
           email_readonly = CASE id
               WHEN get_user_id('csv_manager') THEN 'csv_manager@test.local'
               WHEN get_user_id('csv_existing') THEN 'csv_existing@test.local'
               WHEN get_user_id('csv_addable') THEN 'csv_addable@test.local'
               WHEN get_user_id('csv_delete') THEN 'csv_delete@test.local'
               WHEN get_user_id('csv_plain') THEN 'csv_plain@test.local'
           END
     WHERE id IN (
        get_user_id('csv_manager'), get_user_id('csv_existing'),
        get_user_id('csv_addable'), get_user_id('csv_delete'),
        get_user_id('csv_plain')
     );

    INSERT INTO public.occasion_users (
        occasion, "user", is_manager, is_editor_view, is_cleaning_crew,
        is_approved, role, data, services
    ) VALUES
        (v_occasion, get_user_id('csv_manager'), true, true, false, true, 1,
         jsonb_build_object('email', 'csv_manager@test.local'), '{}'::jsonb),
        (v_occasion, get_user_id('csv_existing'), false, true, true, true, 2,
         jsonb_build_object(
            'email', 'csv_existing@test.local', 'name', 'Bujn', 'surname', 'Mi',
            'sex', 'male', 'note', 'Původní poznámka'
         ),
         jsonb_build_object(
            'accommodation', jsonb_build_object('room-a', 'paid'),
            'food', jsonb_build_object('lunch', 'paid')
         )),
        (v_occasion, get_user_id('csv_delete'), false, false, false, true, 2,
         jsonb_build_object('email', 'csv_delete@test.local'), '{}'::jsonb),
        (v_occasion, get_user_id('csv_plain'), false, false, false, true, 2,
         jsonb_build_object('email', 'csv_plain@test.local'), '{}'::jsonb);

    INSERT INTO public.user_group_info (occasion, title)
    VALUES (v_occasion, 'Původní skupina')
    RETURNING id INTO v_old_group;

    INSERT INTO public.user_groups ("user", "group", is_admin)
    VALUES (get_user_id('csv_existing'), v_old_group, false);

    CREATE TEMP TABLE _csv_import_context (
        occasion bigint,
        existing_user uuid,
        addable_user uuid,
        deleted_user uuid
    );
    INSERT INTO _csv_import_context VALUES (
        v_occasion,
        get_user_id('csv_existing'),
        get_user_id('csv_addable'),
        get_user_id('csv_delete')
    );
END $$;

-- If a proposed +N address already belongs to a real account, email_readonly
-- wins. The server reuses that canonical identity and never guesses +2 from
-- delivery address or profile name.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_org bigint;
    v_reserved_user uuid;
    v_result jsonb;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    SELECT organization INTO v_org FROM public.occasions
     WHERE id = v_context.occasion;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    v_reserved_user := public.create_user_in_organization_with_data_pure(
        v_org, 'reserved+1@test.local', 'reserved+1@test.local',
        'test-password',
        jsonb_build_object('name', 'Reserved', 'surname', 'Mailbox')
    );

    v_result := public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(
            jsonb_build_object(
                'email_delivery', 'reserved@test.local',
                'data', jsonb_build_object(
                    'email', 'reserved@test.local', 'name', 'First',
                    'surname', 'Shared'
                )
            ),
            jsonb_build_object(
                'email_delivery', 'reserved@test.local',
                'data', jsonb_build_object(
                    'email', 'reserved+1@test.local', 'name', 'Second',
                    'surname', 'Shared'
                )
            )
        ),
        '[]'::jsonb
    );

    PERFORM assert_eq((v_result->>'created')::integer, 2,
        'both canonical account identities are added to the occasion');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info
         WHERE organization = v_org
           AND lower(email_readonly) = 'reserved+2@test.local'),
        0::bigint,
        'the server does not invent a new identity from delivery email');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_reserved_user),
        1::bigint,
        'the existing +1 account is resolved only by email_readonly');

END $$;

-- Two people may share one delivery mailbox. They receive distinct sign-in
-- identifiers and retain the same canonical delivery address. Repeating the
-- same payload updates the same two identities instead of allocating +2.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_result jsonb;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    v_result := public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(
            jsonb_build_object(
                'email_delivery', 'shared@test.local',
                'data', jsonb_build_object(
                    'email', 'shared@test.local', 'name', 'Klára',
                    'surname', 'Vomelová'
                )
            ),
            jsonb_build_object(
                'email_delivery', 'shared@test.local',
                'data', jsonb_build_object(
                    'email', 'shared+1@test.local', 'name', 'Marie',
                    'surname', 'Vomelová'
                )
            )
        ),
        '[]'::jsonb
    );

    PERFORM assert_eq((v_result->>'created')::integer, 2,
        'both people sharing a mailbox are created');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info
         WHERE organization = (SELECT organization FROM public.occasions
                                WHERE id = v_context.occasion)
           AND email_delivery = 'shared@test.local'),
        1::bigint,
        'only the aliased identity needs a delivery override');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info ui
         WHERE ui.organization = (SELECT organization FROM public.occasions
                                   WHERE id = v_context.occasion)
           AND public.get_user_delivery_email(ui.id) = 'shared@test.local'),
        2::bigint,
        'both identities resolve to the shared delivery address');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info
         WHERE organization = (SELECT organization FROM public.occasions
                                WHERE id = v_context.occasion)
           AND email_readonly IN ('shared@test.local', 'shared+1@test.local')),
        2::bigint,
        'sign-in identifiers are distinct');

    v_result := public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(
            jsonb_build_object(
                'email_delivery', 'shared@test.local',
                'data', jsonb_build_object(
                    'email', 'shared@test.local', 'name', 'Klára',
                    'surname', 'Vomelová'
                )
            ),
            jsonb_build_object(
                'email_delivery', 'shared@test.local',
                'data', jsonb_build_object(
                    'email', 'shared+1@test.local', 'name', 'Marie',
                    'surname', 'Vomelová'
                )
            )
        ),
        '[]'::jsonb
    );

    PERFORM assert_eq((v_result->>'created')::integer, 0,
        'retry creates no new identity');
    PERFORM assert_eq((v_result->>'updated')::integer, 2,
        'retry updates both existing identities');
END $$;

-- Update, add-to-occasion, delete and group replacement commit together while
-- omitted fields, services, roles and permissions remain untouched.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_result jsonb;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    v_result := public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(
            jsonb_build_object(
                'user_id', v_context.existing_user,
                'data', jsonb_build_object(
                    'email', 'csv_existing@test.local',
                    'name', 'Bujn',
                    'surname', 'Mi',
                    'note', 'Poznámka z atomického importu'
                ),
                'group_title', 'Nová skupina'
            ),
            jsonb_build_object(
                'data', jsonb_build_object(
                    'email', 'csv_addable@test.local',
                    'name', 'CSV',
                    'surname', 'Addable'
                )
            )
        ),
        jsonb_build_array(v_context.deleted_user)
    );

    PERFORM assert_eq(v_result->>'code', '200', 'bulk import succeeds');
    PERFORM assert_eq((v_result->>'created')::integer, 1,
        'one organization user was added to the occasion');
    PERFORM assert_eq((v_result->>'updated')::integer, 1,
        'one existing occasion user was patched');
    PERFORM assert_eq((v_result->>'deleted')::integer, 1,
        'one occasion user was deleted');

    PERFORM assert_eq(
        (SELECT data->>'note' FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        'Poznámka z atomického importu',
        'present CSV data is updated');
    PERFORM assert_false(
        (SELECT COALESCE(data, '{}'::jsonb) ? 'note' FROM public.user_info
         WHERE id = v_context.existing_user),
        'occasion CSV notes are not copied into the canonical profile');
    PERFORM assert_eq(
        (SELECT data->>'sex' FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        'male',
        'omitted sex is preserved');
    PERFORM assert_eq(
        (SELECT services FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        jsonb_build_object(
            'accommodation', jsonb_build_object('room-a', 'paid'),
            'food', jsonb_build_object('lunch', 'paid')
        ),
        'omitted services are preserved');
    PERFORM assert_eq(
        (SELECT role FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        2::bigint,
        'role is preserved');
    PERFORM assert_eq(
        (SELECT is_editor_view FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        true,
        'editor-view permission is preserved');
    PERFORM assert_eq(
        (SELECT is_cleaning_crew FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        true,
        'unrelated permission is preserved');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.addable_user),
        1::bigint,
        'existing organization user is added to the occasion');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.deleted_user),
        0::bigint,
        'selected user is deleted');
    PERFORM assert_eq(
        (SELECT ugi.title FROM public.user_groups ug
         JOIN public.user_group_info ugi ON ugi.id = ug."group"
         WHERE ug."user" = v_context.existing_user
           AND ugi.occasion = v_context.occasion AND ugi.type IS NULL),
        'Nová skupina',
        'group is replaced in the same transaction');
END $$;

-- A retry from a stale client may omit user_id. Resolve the existing occasion
-- member by email and patch it; never route it through add_user_to_occasion,
-- which would replace occasion-specific state with profile data.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_result jsonb;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    v_result := public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(jsonb_build_object(
            'data', jsonb_build_object(
                'email', 'csv_existing@test.local',
                'name', 'Bujn',
                'surname', 'Mi',
                'note', 'Bezpečný retry bez user_id'
            )
        )),
        '[]'::jsonb
    );

    PERFORM assert_eq((v_result->>'created')::integer, 0,
        'retry does not add an existing occasion member');
    PERFORM assert_eq((v_result->>'updated')::integer, 1,
        'retry patches the existing occasion member');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        1::bigint,
        'retry leaves exactly one occasion membership');
    PERFORM assert_eq(
        (SELECT services FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        jsonb_build_object(
            'accommodation', jsonb_build_object('room-a', 'paid'),
            'food', jsonb_build_object('lunch', 'paid')
        ),
        'retry preserves occasion-specific services');
END $$;

-- A service patch replaces only the named top-level family.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    PERFORM public.import_occasion_users_from_csv(
        v_context.occasion,
        jsonb_build_array(jsonb_build_object(
            'user_id', v_context.existing_user,
            'data', jsonb_build_object(
                'email', 'csv_existing@test.local', 'name', 'Bujn', 'surname', 'Mi'
            ),
            'services', jsonb_build_object(
                'accommodation', jsonb_build_object('room-b', 'paid')
            )
        )),
        '[]'::jsonb
    );

    PERFORM assert_eq(
        (SELECT services->'accommodation' FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        jsonb_build_object('room-b', 'paid'),
        'present accommodation family is replaced');
    PERFORM assert_eq(
        (SELECT services->'food' FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        jsonb_build_object('lunch', 'paid'),
        'omitted food family is preserved');
END $$;

-- A later invalid row rolls every earlier write in the RPC back.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_rejected boolean := false;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);

    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_context.occasion,
            jsonb_build_array(
                jsonb_build_object(
                    'user_id', v_context.existing_user,
                    'data', jsonb_build_object(
                        'email', 'csv_existing@test.local',
                        'name', 'Bujn',
                        'surname', 'Mi',
                        'note', 'Tato změna se musí rollbacknout'
                    )
                ),
                jsonb_build_object(
                    'user_id', '00000000-0000-0000-0000-000000000000',
                    'data', jsonb_build_object(
                        'email', 'missing@test.local',
                        'name', 'Missing',
                        'surname', 'User'
                    )
                )
            ),
            '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'USER_NOT_ON_OCCASION';
    END;

    PERFORM assert_eq(v_rejected, true, 'invalid later row rejects the batch');
    PERFORM assert_eq(
        (SELECT data->>'note' FROM public.occasion_users
         WHERE occasion = v_context.occasion AND "user" = v_context.existing_user),
        'Bezpečný retry bez user_id',
        'earlier row is rolled back with the entire RPC');
END $$;

-- Invalid account and delivery addresses are rejected before any write.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_rejected boolean := false;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);
    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_context.occasion,
            jsonb_build_array(jsonb_build_object(
                'data', jsonb_build_object(
                    'email', 'not-an-email', 'name', 'Invalid',
                    'surname', 'Address'
                )
            )),
            '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'INVALID_EMAIL';
    END;
    PERFORM assert_true(v_rejected,
        'malformed account email rejects the entire batch');

    v_rejected := false;
    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_context.occasion,
            jsonb_build_array(jsonb_build_object(
                'email_delivery', 'not-an-email',
                'data', jsonb_build_object(
                    'email', 'valid@test.local', 'name', 'Invalid',
                    'surname', 'Delivery'
                )
            )),
            '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'INVALID_EMAIL';
    END;
    PERFORM assert_true(v_rejected,
        'malformed delivery email rejects the entire batch');
END $$;

-- Ambiguous last-row-wins input is rejected before account resolution.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_rejected boolean := false;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);
    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_context.occasion,
            jsonb_build_array(
                jsonb_build_object('data', jsonb_build_object(
                    'email', 'duplicate@test.local', 'name', 'First',
                    'surname', 'Person')),
                jsonb_build_object('data', jsonb_build_object(
                    'email', ' DUPLICATE@test.local ', 'name', 'Second',
                    'surname', 'Person'))
            ),
            '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'DUPLICATE_ACCOUNT_EMAIL';
    END;
    PERFORM assert_true(v_rejected,
        'duplicate canonical account email is never last-row-wins');
END $$;

-- An import batch cannot both update and delete the same participant.
DO $$
DECLARE
    v_context _csv_import_context%rowtype;
    v_rejected boolean := false;
BEGIN
    SELECT * INTO v_context FROM _csv_import_context;
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_manager')::text, true);
    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_context.occasion,
            jsonb_build_array(jsonb_build_object(
                'user_id', v_context.existing_user,
                'data', jsonb_build_object(
                    'email', 'csv_existing@test.local', 'name', 'Bujn',
                    'surname', 'Mi'
                )
            )),
            jsonb_build_array(v_context.existing_user)
        );
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'CONFLICTING_IMPORT_OPERATION';
    END;
    PERFORM assert_true(v_rejected,
        'one participant cannot be updated and deleted in the same batch');
END $$;

-- A regular participant cannot invoke the bulk import boundary.
DO $$
DECLARE
    v_occasion bigint := (SELECT occasion FROM _csv_import_context);
    v_rejected boolean := false;
BEGIN
    PERFORM set_config(
        'request.jwt.claim.sub', get_user_id('csv_plain')::text, true);
    BEGIN
        PERFORM public.import_occasion_users_from_csv(
            v_occasion, '[]'::jsonb, '[]'::jsonb);
    EXCEPTION WHEN OTHERS THEN
        v_rejected := SQLERRM = 'NOT_AUTHORIZED';
    END;
    PERFORM assert_eq(v_rejected, true, 'unauthorized caller is rejected');
END $$;
