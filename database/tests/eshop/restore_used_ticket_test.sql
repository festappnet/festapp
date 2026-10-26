BEGIN;

DO $$
DECLARE
    v_user uuid := '10000000-0000-0000-0000-000000000001';
    v_unauthorized_user uuid := '10000000-0000-0000-0000-000000000002';
    v_organization bigint;
    v_unit bigint;
    v_occasion bigint;
    v_ticket bigint;
    v_state text;
BEGIN
    INSERT INTO auth.users (id, email)
    VALUES (v_user, 'restore-used-ticket@example.com');

    INSERT INTO auth.users (id, email)
    VALUES (v_unauthorized_user, 'restore-used-ticket-denied@example.com');

    INSERT INTO public.user_info (id, email_readonly)
    VALUES (v_user, 'restore-used-ticket@example.com');

    INSERT INTO public.user_info (id, email_readonly)
    VALUES (v_unauthorized_user, 'restore-used-ticket-denied@example.com');

    INSERT INTO public.organizations (title)
    VALUES ('Restore used ticket test')
    RETURNING id INTO v_organization;

    INSERT INTO public.units (organization, title)
    VALUES (v_organization, 'Restore used ticket unit')
    RETURNING id INTO v_unit;

    INSERT INTO public.occasions (organization, unit, title, link, start_time, end_time)
    VALUES (
        v_organization,
        v_unit,
        'Restore used ticket occasion',
        'restore-used-ticket-' || extensions.gen_random_uuid(),
        now(),
        now() + interval '1 day'
    )
    RETURNING id INTO v_occasion;

    INSERT INTO public.occasion_users (
        occasion, "user", is_manager, is_editor, is_editor_order
    )
    VALUES (v_occasion, v_user, true, true, true);

    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (v_occasion, 'used', 'RESTORE-USED')
    RETURNING id INTO v_ticket;

    PERFORM set_config('request.jwt.claim.sub', v_unauthorized_user::text, true);
    BEGIN
        PERFORM public.update_ticket_to_unused_ws(v_ticket);
        RAISE EXCEPTION 'Expected an unauthorized user to be rejected';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'User is not editor.' THEN
                RAISE;
            END IF;
    END;

    SELECT state INTO v_state
    FROM eshop.tickets
    WHERE id = v_ticket;

    IF v_state <> 'used' THEN
        RAISE EXCEPTION 'Unauthorized call changed ticket state to %', v_state;
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    PERFORM public.update_ticket_to_unused_ws(v_ticket);

    SELECT state INTO v_state
    FROM eshop.tickets
    WHERE id = v_ticket;

    IF v_state <> 'sent' THEN
        RAISE EXCEPTION 'Expected restored ticket state sent, got %', v_state;
    END IF;

    BEGIN
        PERFORM public.update_ticket_to_unused_ws(v_ticket);
        RAISE EXCEPTION 'Expected a non-used ticket to be rejected';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE 'Ticket % is not used.' THEN
                RAISE;
            END IF;
    END;
END;
$$;

ROLLBACK;
