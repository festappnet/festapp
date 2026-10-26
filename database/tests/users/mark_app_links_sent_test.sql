DO $$
DECLARE
    v_occasion bigint;
    v_user uuid;
    v_result jsonb;
BEGIN
    PERFORM create_user_for_test(
        'app_links_recipient',
        'app_links_recipient@test.local'
    );
    v_user := get_user_id('app_links_recipient');

    INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
    VALUES (
        'Application links delivery test',
        'app-links-' || gen_random_uuid(),
        now(),
        now() + interval '1 day',
        true
    )
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasion_users (occasion, "user", data)
    VALUES (v_occasion, v_user, jsonb_build_object('note', 'preserve me'));

    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    v_result := public.mark_app_links_sent(v_occasion, v_user);
    PERFORM assert_eq(
        v_result->>'code',
        '403',
        'authenticated callers cannot forge the delivery status'
    );

    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    v_result := public.mark_app_links_sent(v_occasion, v_user);
    PERFORM assert_eq(
        v_result->>'code',
        '200',
        'the delivery worker can mark application links as sent'
    );
    PERFORM assert_eq(
        (SELECT data->>'app_links_sent'
           FROM public.occasion_users
          WHERE occasion = v_occasion AND "user" = v_user),
        'true',
        'delivery acknowledgement stores the status on the occasion user'
    );
    PERFORM assert_eq(
        (SELECT data->>'note'
           FROM public.occasion_users
          WHERE occasion = v_occasion AND "user" = v_user),
        'preserve me',
        'delivery acknowledgement preserves other occasion data'
    );
    PERFORM assert_eq(
        (SELECT version::text
           FROM public.client_aggregate_versions
          WHERE aggregate_type = 'occasion_user'
            AND scope_type = 'occasion'
            AND scope_id = v_occasion
            AND aggregate_id = v_user::text),
        '1',
        'delivery acknowledgement invalidates stale Users-grid versions'
    );

    v_result := public.mark_app_links_sent(v_occasion, v_user);
    PERFORM assert_eq(
        (SELECT version::text
           FROM public.client_aggregate_versions
          WHERE aggregate_type = 'occasion_user'
            AND scope_type = 'occasion'
            AND scope_id = v_occasion
            AND aggregate_id = v_user::text),
        '1',
        're-sending links does not advance an unchanged boolean status'
    );
END;
$$;
