-- Regression coverage for the set-based occasion users editor bundle.
DO $$
DECLARE
    v_occasion bigint;
    v_ticket bigint;
    v_order bigint;
    v_form_key uuid := gen_random_uuid();
    v_group_alpha bigint;
    v_group_zeta bigint;
    v_group_game bigint;
    v_orphan uuid := gen_random_uuid();
    v_payload jsonb;
    v_user jsonb;
BEGIN
    PERFORM assert_eq(
        public.get_user_profile_data_patch(jsonb_build_object(
            'name', 'Canonical',
            'phone', 'profile-phone',
            'note', 'occasion-only',
            'is_invited', true
        )),
        jsonb_build_object(
            'name', 'Canonical',
            'phone', 'profile-phone'
        ),
        'profile patch accepts identity fields and rejects occasion fields'
    );

    PERFORM assert_eq(
        pg_get_function_result(
            'public.get_occasion_users_for_edit(bigint)'::regprocedure
        ),
        'json',
        'Users and Stay share the single-pass JSON response type'
    );

    PERFORM create_user_for_test('oue_editor', 'oue_editor@test.local');
    PERFORM create_user_for_test('oue_grouped', 'oue_grouped@test.local');
    PERFORM create_user_for_test('oue_plain', 'oue_plain@test.local');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES (
        'Occasion users editor test',
        'oue-' || gen_random_uuid(),
        now(),
        now() + interval '1 day',
        true
    )
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasion_users
        (occasion, "user", is_editor, is_editor_view, is_approved, data, services)
    VALUES
        (
            v_occasion,
            get_user_id('oue_editor'),
            true,
            true,
            true,
            jsonb_build_object('email', 'oue_editor@test.local'),
            '{}'::jsonb
        ),
        (
            v_occasion,
            get_user_id('oue_grouped'),
            false,
            false,
            true,
            jsonb_build_object(
                'email', 'stale@test.local',
                'name', 'Occasion name',
                'surname', 'Occasion surname',
                'sex', 'occasion-sex',
                'phone', 'occasion-phone',
                'birthDate', '1999-01-01',
                'note', 'occasion note'
            ),
            '{}'::jsonb
        ),
        (
            v_occasion,
            get_user_id('oue_plain'),
            false,
            false,
            true,
            jsonb_build_object('email', 'oue_plain@test.local'),
            '{}'::jsonb
        ),
        (
            v_occasion,
            v_orphan,
            false,
            false,
            true,
            jsonb_build_object('email', 'orphan@test.local'),
            '{}'::jsonb
        );

    UPDATE public.user_info
    SET email_readonly = 'canonical@test.local',
        name = 'Canonical name',
        surname = 'Canonical surname',
        sex = 'canonical-sex',
        phone = 'canonical-phone',
        birth_date = date '2000-02-03',
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object(
            'is_invited', true,
            'note', 'global note must not leak into the occasion'
        )
    WHERE id = get_user_id('oue_grouped');

    INSERT INTO public.user_group_info (occasion, title)
    VALUES (v_occasion, 'Zeta')
    RETURNING id INTO v_group_zeta;

    INSERT INTO public.user_group_info (occasion, title)
    VALUES (v_occasion, 'Alpha')
    RETURNING id INTO v_group_alpha;

    INSERT INTO public.user_group_info (occasion, title, type)
    VALUES (v_occasion, 'Game group', 'game')
    RETURNING id INTO v_group_game;

    INSERT INTO public.user_groups ("user", "group", is_admin)
    VALUES
        (get_user_id('oue_grouped'), v_group_zeta, false),
        (get_user_id('oue_grouped'), v_group_alpha, false),
        (get_user_id('oue_grouped'), v_group_game, false);

    INSERT INTO public.forms (occasion, key, title, link)
    VALUES (v_occasion, v_form_key, 'Editor form', 'oue-form');

    INSERT INTO eshop.orders (order_sequence, order_symbol, occasion, data, created_at, state)
    VALUES (public.next_order_sequence(v_occasion), public.generate_order_symbol(),
        v_occasion,
        jsonb_build_object('form', v_form_key::text),
        timestamptz '2026-08-02 10:00:00+00',
        'created'
    )
    RETURNING id INTO v_order;

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'ordered', 'OUE-TICKET')
    RETURNING id INTO v_ticket;

    INSERT INTO eshop.order_product_ticket ("order", ticket)
    VALUES (v_order, v_ticket);

    UPDATE public.occasion_users
    SET ticket = v_ticket
    WHERE occasion = v_occasion
      AND "user" = get_user_id('oue_grouped');

    PERFORM set_config(
        'request.jwt.claim.sub',
        get_user_id('oue_editor')::text,
        true
    );

    v_payload := public.get_occasion_users_for_edit(v_occasion);

    PERFORM assert_eq(v_payload->>'code', '200', 'editor bundle succeeds');
    PERFORM assert_eq(
        jsonb_array_length(v_payload #> '{data,occasion_users}'),
        4,
        'every occasion user, including a legacy orphan, is returned exactly once'
    );

    SELECT item INTO v_user
    FROM jsonb_array_elements(v_payload #> '{data,occasion_users}') AS item
    WHERE item->>'user' = get_user_id('oue_grouped')::text;

    PERFORM assert_not_null(v_user, 'grouped user is present');
    PERFORM assert_false(
        v_user ? 'email_readonly',
        'unused user_info fields are not duplicated into editor rows'
    );
    PERFORM assert_eq(
        v_user #>> '{data,email}',
        'canonical@test.local',
        'canonical profile email overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,name}',
        'Canonical name',
        'canonical profile name overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,surname}',
        'Canonical surname',
        'canonical profile surname overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,sex}',
        'canonical-sex',
        'canonical profile gender overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,phone}',
        'canonical-phone',
        'canonical profile phone overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,birthDate}',
        '2000-02-03',
        'canonical profile birth date overrides the occasion snapshot'
    );
    PERFORM assert_eq(
        v_user #>> '{data,is_invited}',
        'false',
        'invitation state is projected from email evidence, not global profile JSON'
    );
    PERFORM assert_eq(
        v_user #>> '{data,note}',
        'occasion note',
        'occasion-specific notes are not overwritten by global profile JSON'
    );
    PERFORM assert_eq(
        v_user->>'group_title',
        'Alpha, Zeta',
        'standard groups are aggregated in title order and typed groups are excluded'
    );
    PERFORM assert_eq(
        v_user->>'form_id',
        v_form_key::text,
        'ticket order form is included'
    );
    PERFORM assert_eq(
        v_user->>'order_created_at',
        '2026-08-02T10:00:00+00:00',
        'ticket order creation time is included'
    );

    UPDATE public.occasion_users
    SET is_manager = true
    WHERE occasion = v_occasion
      AND "user" = get_user_id('oue_editor');

    PERFORM assert_eq(
        public.save_occasion_user_for_edit(jsonb_build_object(
            'occasion', v_occasion,
            'user', get_user_id('oue_grouped'),
            'data', (v_user->'data') || jsonb_build_object(
                'phone', 'updated-canonical-phone',
                'birthDate', '2001-04-05'
            ),
            'services', '{}'::jsonb
        ))->>'code',
        '200',
        'manager can save canonical profile edits through the shared grid RPC'
    );

    PERFORM assert_eq(
        (SELECT phone FROM public.user_info WHERE id = get_user_id('oue_grouped')),
        'updated-canonical-phone',
        'saving a grid edit synchronizes canonical phone'
    );
    PERFORM assert_eq(
        (SELECT birth_date::text FROM public.user_info WHERE id = get_user_id('oue_grouped')),
        '2001-04-05',
        'saving a grid edit synchronizes canonical birth date'
    );
    PERFORM assert_eq(
        (SELECT data->>'note' FROM public.user_info
         WHERE id = get_user_id('oue_grouped')),
        'global note must not leak into the occasion',
        'saving participation does not copy occasion notes into the profile'
    );
END $$;

DO $$
BEGIN
    PERFORM assert_true(
        to_regclass('eshop.order_product_ticket_ticket_id_idx') IS NOT NULL,
        'ticket-order lookup index exists'
    );
END $$;
