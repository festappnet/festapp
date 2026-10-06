DO $$
DECLARE
    v_org bigint;
    v_unit bigint;
    v_occasion bigint;
    v_order bigint;
    v_ticket bigint;
    v_first uuid;
    v_second uuid;
BEGIN
    PERFORM assert_false(
        has_function_privilege(
            'anon', 'public.get_user_delivery_email(uuid)', 'EXECUTE'
        ),
        'anonymous callers cannot resolve delivery overrides'
    );
    PERFORM assert_false(
        has_function_privilege(
            'authenticated', 'public.get_user_delivery_email(uuid)', 'EXECUTE'
        ),
        'authenticated callers cannot resolve another account delivery address'
    );
    PERFORM assert_true(
        has_function_privilege(
            'service_role', 'public.get_user_delivery_email(uuid)', 'EXECUTE'
        ),
        'account-email Edge Functions may use the resolver'
    );

    INSERT INTO public.organizations(title)
    VALUES ('Email identity contract test')
    RETURNING id INTO v_org;

    v_first := public.create_user_in_organization_with_data_pure(
        v_org,
        'shared@test.local',
        'shared@test.local',
        'test-password',
        jsonb_build_object('name', 'First', 'surname', 'Person')
    );

    PERFORM assert_eq(
        public.allocate_user_sign_in_email(v_org, 'shared@test.local'),
        'shared+1@test.local',
        'allocator assigns the first available numeric alias'
    );

    v_second := public.create_user_in_organization_with_data_pure(
        v_org,
        'shared+1@test.local',
        'shared@test.local',
        'test-password',
        jsonb_build_object('name', 'Second', 'surname', 'Person')
    );

    PERFORM assert_eq(
        (SELECT email_readonly FROM public.user_info WHERE id = v_second),
        'shared+1@test.local',
        'second identity keeps its sign-in alias'
    );
    PERFORM assert_eq(
        public.get_user_delivery_email(v_second),
        'shared@test.local',
        'delivery resolver returns the shared canonical mailbox'
    );
    PERFORM assert_eq(
        public.get_user_delivery_email(v_first),
        'shared@test.local',
        'resolver falls back to the account email without an override'
    );
    UPDATE public.user_info SET email_delivery = '   ' WHERE id = v_first;
    PERFORM assert_eq(
        public.get_user_delivery_email(v_first),
        'shared@test.local',
        'blank delivery override also falls back to the account email'
    );
    UPDATE public.user_info SET email_delivery = NULL WHERE id = v_first;
    PERFORM assert_eq(
        (SELECT email FROM auth.users WHERE id = v_second),
        v_org::text || '+shared+1@test.local',
        'Auth email remains organization-prefixed sign-in identity'
    );

    BEGIN
        PERFORM public.create_user_in_organization_with_data_pure(
            v_org,
            'SHARED+1@test.local',
            'other@test.local',
            'test-password',
            '{}'::jsonb
        );
        RAISE EXCEPTION 'expected duplicate sign-in identity to fail';
    EXCEPTION
        WHEN OTHERS THEN
            PERFORM assert_true(
                SQLERRM LIKE '%SIGN_IN_EMAIL_ALREADY_EXISTS%',
                'duplicate sign-in identity is rejected before Auth creation'
            );
    END;

    PERFORM assert_eq(
        (SELECT email_delivery IS NULL FROM public.user_info WHERE id = v_first),
        true,
        'ordinary identity does not duplicate its account email as an override'
    );

    INSERT INTO public.units(organization, title)
    VALUES (v_org, 'Email identity unit')
    RETURNING id INTO v_unit;
    INSERT INTO public.occasions(
        organization, unit, title, link, start_time, end_time, is_open
    ) VALUES (
        v_org, v_unit, 'Email identity occasion',
        'email-identity-' || gen_random_uuid(), now(), now() + interval '1 day',
        true
    ) RETURNING id INTO v_occasion;
    INSERT INTO public.occasion_users(occasion, "user", data, services)
    VALUES (
        v_occasion, v_second,
        jsonb_build_object(
            'email', 'shared+1@test.local', 'name', 'Second',
            'surname', 'Person'
        ),
        '{}'::jsonb
    );
    INSERT INTO eshop.orders(order_symbol, occasion, state, data)
    VALUES (public.generate_order_symbol(),
        v_occasion, 'paid',
        jsonb_build_object(
            'email', 'new-delivery@test.local', 'name', 'Second',
            'surname', 'Person'
        )
    ) RETURNING id INTO v_order;
    INSERT INTO eshop.tickets(occasion, state, ticket_symbol)
    VALUES (v_occasion, 'paid', 'EMAIL-IDENTITY-TICKET')
    RETURNING id INTO v_ticket;
    INSERT INTO eshop.order_product_ticket("order", ticket)
    VALUES (v_order, v_ticket);
    UPDATE public.occasion_users
       SET ticket = v_ticket
     WHERE occasion = v_occasion AND "user" = v_second;

    PERFORM public.import_users_from_tickets(v_occasion);

    PERFORM assert_eq(
        (SELECT email_delivery FROM public.user_info WHERE id = v_second),
        'shared@test.local',
        'ticket sync does not replace the delivery override from an order snapshot'
    );
    PERFORM assert_eq(
        (SELECT data->>'email' FROM public.occasion_users
         WHERE occasion = v_occasion AND "user" = v_second),
        'shared+1@test.local',
        'ticket sync preserves the sign-in alias in participation data'
    );
END $$;

-- The real ticket/application import creates two distinct identities for two
-- tickets sharing one delivery mailbox and remains idempotent on retry.
DO $$
DECLARE
    v_org bigint;
    v_unit bigint;
    v_occasion bigint;
    v_order_1 bigint;
    v_order_2 bigint;
    v_ticket_1 bigint;
    v_ticket_2 bigint;
    v_result jsonb;
BEGIN
    INSERT INTO public.organizations(title)
    VALUES ('Ticket delivery alias test')
    RETURNING id INTO v_org;
    INSERT INTO public.units(organization, title)
    VALUES (v_org, 'Ticket delivery alias unit')
    RETURNING id INTO v_unit;
    INSERT INTO public.occasions(
        organization, unit, title, link, start_time, end_time, is_open
    ) VALUES (
        v_org, v_unit, 'Ticket delivery alias occasion',
        'ticket-delivery-' || gen_random_uuid(), now(), now() + interval '1 day',
        true
    ) RETURNING id INTO v_occasion;

    INSERT INTO eshop.orders(order_symbol, occasion, state, data)
    VALUES (public.generate_order_symbol(),
        v_occasion, 'paid',
        jsonb_build_object(
            'email', 'family@test.local', 'name', 'Klára',
            'surname', 'Vomelová'
        )
    ) RETURNING id INTO v_order_1;
    INSERT INTO eshop.orders(order_symbol, occasion, state, data)
    VALUES (public.generate_order_symbol(),
        v_occasion, 'paid',
        jsonb_build_object(
            'email', 'family@test.local', 'name', 'Marie',
            'surname', 'Vomelová'
        )
    ) RETURNING id INTO v_order_2;
    INSERT INTO eshop.tickets(occasion, state, ticket_symbol)
    VALUES (v_occasion, 'paid', 'FAMILY-1') RETURNING id INTO v_ticket_1;
    INSERT INTO eshop.tickets(occasion, state, ticket_symbol)
    VALUES (v_occasion, 'paid', 'FAMILY-2') RETURNING id INTO v_ticket_2;
    INSERT INTO eshop.order_product_ticket("order", ticket)
    VALUES (v_order_1, v_ticket_1), (v_order_2, v_ticket_2);

    v_result := public.import_users_from_tickets(v_occasion);
    PERFORM assert_eq(jsonb_array_length(v_result->'inserted'), 2,
        'ticket import creates both people sharing one mailbox');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info
         WHERE organization = v_org
           AND email_readonly IN ('family@test.local', 'family+1@test.local')),
        2::bigint,
        'ticket import assigns canonical account emails with +N');
    PERFORM assert_true(
        (SELECT email_delivery IS NULL FROM public.user_info
         WHERE organization = v_org
           AND email_readonly = 'family@test.local'),
        'base account relies on delivery fallback');
    PERFORM assert_eq(
        (SELECT email_delivery FROM public.user_info
         WHERE organization = v_org
           AND email_readonly = 'family+1@test.local'),
        'family@test.local',
        'aliased account stores the shared delivery override');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.occasion_users
         WHERE occasion = v_occasion AND ticket IN (v_ticket_1, v_ticket_2)),
        2::bigint,
        'both imported identities are linked to their tickets');

    v_result := public.import_users_from_tickets(v_occasion);
    PERFORM assert_eq(jsonb_array_length(v_result->'inserted'), 0,
        'ticket import retry creates no additional identity');
    PERFORM assert_eq(
        (SELECT count(*) FROM public.user_info WHERE organization = v_org),
        2::bigint,
        'ticket import retry keeps exactly two identities');
END $$;
