DO $$
DECLARE
    v_occasion bigint;
BEGIN
    PERFORM create_user_for_test('app_links_manager', 'app_links_manager@test.local');
    PERFORM create_user_for_test('app_links_plain', 'app_links_plain@test.local');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES (
        'Application links permission test',
        'app-links-permission-' || gen_random_uuid(),
        now(),
        now() + interval '1 day',
        true
    )
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasion_users (occasion, "user", is_manager, data)
    VALUES
        (
            v_occasion,
            get_user_id('app_links_manager'),
            true,
            '{}'::jsonb
        ),
        (
            v_occasion,
            get_user_id('app_links_plain'),
            false,
            '{}'::jsonb
        );

    PERFORM set_config(
        'request.jwt.claim.sub',
        get_user_id('app_links_manager')::text,
        true
    );
    PERFORM assert_eq(
        public.get_can_manage_occasion_users(v_occasion),
        true,
        'occasion managers can send application links'
    );

    PERFORM set_config(
        'request.jwt.claim.sub',
        get_user_id('app_links_plain')::text,
        true
    );
    PERFORM assert_eq(
        public.get_can_manage_occasion_users(v_occasion),
        false,
        'plain occasion users cannot send application links'
    );
END;
$$;
