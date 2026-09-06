BEGIN;

DO $$
DECLARE
    v_target_user uuid;
    v_editor_target uuid;
    v_order_editor_target uuid;
    v_organization bigint;
    v_unit bigint;
    v_hidden bigint;
    v_occasion bigint;
    v_ticket bigint;
    v_editor_ticket bigint;
    v_order_editor_ticket bigint;
    v_result jsonb;
    v_password_before text;
    v_password_after text;
    v_scan_code text := 'reset-password-target-authorization-test';
BEGIN
    PERFORM create_user_for_test(
        'reset_scan_target',
        'reset-scan-target@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_editor_target',
        'reset-scan-editor-target@test.local'
    );
    PERFORM create_user_for_test(
        'reset_scan_order_editor_target',
        'reset-scan-order-editor-target@test.local'
    );

    v_target_user := get_user_id('reset_scan_target');
    v_editor_target := get_user_id('reset_scan_editor_target');
    v_order_editor_target := get_user_id('reset_scan_order_editor_target');

    INSERT INTO public.organizations (title)
    VALUES ('Reset password target authorization test')
    RETURNING id INTO v_organization;

    INSERT INTO public.units (organization, title)
    VALUES (v_organization, 'Reset password target authorization unit')
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
        'Reset password target authorization occasion',
        'reset-password-target-authorization-' || extensions.gen_random_uuid(),
        now(),
        now() + interval '1 day'
    )
    RETURNING id INTO v_occasion;

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'sent', 'RESET-PASSWORD-ORDINARY-TARGET')
    RETURNING id INTO v_ticket;

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'sent', 'RESET-PASSWORD-EDITOR-TARGET')
    RETURNING id INTO v_editor_ticket;

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'sent', 'RESET-PASSWORD-ORDER-EDITOR-TARGET')
    RETURNING id INTO v_order_editor_ticket;

    INSERT INTO public.occasion_users (occasion, "user", ticket)
    VALUES (v_occasion, v_target_user, v_ticket);

    INSERT INTO public.occasion_users (
        occasion,
        "user",
        ticket,
        is_editor
    )
    VALUES (v_occasion, v_editor_target, v_editor_ticket, true);

    INSERT INTO public.occasion_users (
        occasion,
        "user",
        ticket,
        is_editor_order
    )
    VALUES (
        v_occasion,
        v_order_editor_target,
        v_order_editor_ticket,
        true
    );

    PERFORM assert_true(
        has_function_privilege(
            'anon',
            'public.reset_password_via_scan(bigint,text,text)',
            'EXECUTE'
        ),
        'anonymous callers can execute the password reset RPC'
    );

    PERFORM assert_false(
        has_function_privilege(
            'anon',
            'public.check_is_scan_password_reset_target_allowed(uuid)',
            'EXECUTE'
        ),
        'anonymous callers cannot bypass the reset RPC through its helper'
    );

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);

    SELECT encrypted_password
      INTO v_password_before
      FROM auth.users
     WHERE id = v_target_user;

    v_result := public.reset_password_via_scan(
        v_ticket,
        'null-scan-code-must-not-reset',
        NULL
    );

    PERFORM assert_eq(
        v_result->>'code',
        '401',
        'a NULL scan code is rejected'
    );

    SELECT encrypted_password
      INTO v_password_after
      FROM auth.users
     WHERE id = v_target_user;

    PERFORM assert_true(
        v_password_after IS NOT DISTINCT FROM v_password_before,
        'a NULL scan code leaves the ordinary target password unchanged'
    );

    v_result := public.reset_password_via_scan(
        v_ticket,
        'ordinary-target-password',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '200',
        'anonymous scanner can reset an ordinary ticket holder password: '
            || coalesce(v_result->>'detail', 'no detail')
    );

    SELECT encrypted_password
      INTO v_password_after
      FROM auth.users
     WHERE id = v_target_user;

    PERFORM assert_true(
        crypt('ordinary-target-password', v_password_after) = v_password_after,
        'ordinary target receives the requested password'
    );

    SELECT encrypted_password
      INTO v_password_before
      FROM auth.users
     WHERE id = v_editor_target;

    v_result := public.reset_password_via_scan(
        v_editor_ticket,
        'editor-target-must-not-reset',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '403',
        'editor target cannot have a password reset through scan'
    );

    SELECT encrypted_password
      INTO v_password_after
      FROM auth.users
     WHERE id = v_editor_target;

    PERFORM assert_true(
        v_password_after IS NOT DISTINCT FROM v_password_before,
        'denied privileged-target reset leaves the password unchanged'
    );

    v_result := public.reset_password_via_scan(
        v_order_editor_ticket,
        'order-editor-target-must-not-reset',
        v_scan_code
    );

    PERFORM assert_eq(
        v_result->>'code',
        '403',
        'order editor target cannot have a password reset through scan'
    );
END;
$$;

ROLLBACK;
