BEGIN;

DO $$
DECLARE
    v_plain_user uuid;
    v_editor uuid;
    v_manager uuid;
    v_other_editor uuid;
    v_target_user uuid;
    v_organization bigint;
    v_unit bigint;
    v_hidden bigint;
    v_occasion bigint;
    v_other_occasion bigint;
    v_ticket bigint;
    v_result jsonb;
    v_password_before text;
    v_password_after text;
    v_scan_code text := 'reset-password-authorization-test';
BEGIN
    PERFORM create_user_for_test(
        'reset_scan_plain',
        'reset-scan-plain@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_editor',
        'reset-scan-editor@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_manager',
        'reset-scan-manager@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_target',
        'reset-scan-target@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_other_editor',
        'reset-scan-other-editor@test.local'
    );

    v_plain_user := get_user_id('reset_scan_plain');
    v_editor := get_user_id('reset_scan_editor');
    v_manager := get_user_id('reset_scan_manager');
    v_target_user := get_user_id('reset_scan_target');
    v_other_editor := get_user_id('reset_scan_other_editor');

    INSERT INTO public.organizations (title)
    VALUES ('Reset password authorization test')
    RETURNING id INTO v_organization;

    INSERT INTO public.units (organization, title)
    VALUES (v_organization, 'Reset password authorization unit')
    RETURNING id INTO v_unit;

    INSERT INTO public.occasions_hidden (secret)
    VALUES (v_scan_code)
    RETURNING id INTO v_hidden;

    INSERT INTO public.occasions (
        organization,
        unit,
        occasion_hidden,
        title,
        link,
        start_time,
        end_time
    )
    VALUES (
        v_organization,
        v_unit,
        v_hidden,
        'Reset password authorization occasion',
        'reset-password-authorization-' || extensions.gen_random_uuid(),
        now(),
        now() + interval '1 day'
    )
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasions (
        organization,
        unit,
        title,
        link,
        start_time,
        end_time
    )
    VALUES (
        v_organization,
        v_unit,
        'Other reset password authorization occasion',
        'other-reset-password-authorization-' || extensions.gen_random_uuid(),
        now(),
        now() + interval '1 day'
    )
    RETURNING id INTO v_other_occasion;

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'sent', 'RESET-PASSWORD-AUTHORIZATION-TICKET')
    RETURNING id INTO v_ticket;

    INSERT INTO public.occasion_users (occasion, "user", ticket)
    VALUES (v_occasion, v_target_user, v_ticket);

    INSERT INTO public.occasion_users (occasion, "user")
    VALUES (v_occasion, v_plain_user);

    INSERT INTO public.occasion_users (occasion, "user", is_editor)
    VALUES (v_occasion, v_editor, true);

    INSERT INTO public.occasion_users (occasion, "user", is_manager)
    VALUES (v_occasion, v_manager, true);

    INSERT INTO public.occasion_users (occasion, "user", is_editor)
    VALUES (v_other_occasion, v_other_editor, true);

    SELECT encrypted_password
      INTO v_password_before
      FROM auth.users
     WHERE id = v_target_user;

    PERFORM set_config(
        'request.jwt.claim.sub',
        v_plain_user::text,
        true
    );
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

    v_result := public.reset_password_via_scan(
        v_ticket,
        'ordinary-user-must-not-reset',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '403',
        'ordinary occasion user cannot reset a ticket holder password'
    );

    SELECT encrypted_password
      INTO v_password_after
      FROM auth.users
     WHERE id = v_target_user;

    PERFORM assert_true(
        v_password_after IS NOT DISTINCT FROM v_password_before,
        'denied reset leaves the target password unchanged'
    );

    PERFORM assert_false(
        has_function_privilege(
            'anon',
            'public.reset_password_via_scan(bigint,text,text)',
            'EXECUTE'
        ),
        'anonymous callers cannot execute the password reset RPC'
    );

    PERFORM set_config('request.jwt.claim.sub', v_other_editor::text, true);

    v_result := public.reset_password_via_scan(
        v_ticket,
        'other-occasion-editor-must-not-reset',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '403',
        'editor from another occasion cannot reset the target password'
    );

    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);

    v_result := public.reset_password_via_scan(
        v_ticket,
        'editor-authorized-password',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '200',
        'occasion editor can reset an ordinary ticket holder password'
    );

    SELECT encrypted_password
      INTO v_password_after
      FROM auth.users
     WHERE id = v_target_user;

    PERFORM assert_true(
        v_password_after IS DISTINCT FROM v_password_before
        AND crypt('editor-authorized-password', v_password_after)
            = v_password_after,
        'authorized editor reset stores the requested password hash'
    );

    PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);

    v_result := public.reset_password_via_scan(
        v_ticket,
        'manager-authorized-password',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '200',
        'occasion manager can reset an ordinary ticket holder password'
    );
END;
$$;

ROLLBACK;
