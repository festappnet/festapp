-- Password reset follows the Users administration scope after canonical merges.
DO $$
DECLARE
    v_admin uuid;
    v_editor uuid;
    v_regular uuid;
    v_privileged uuid;
    v_outsider uuid;
    v_org bigint;
    v_other_org bigint;
    v_unit bigint;
    v_other_unit bigint;
    v_occasion bigint;
    v_other_occasion bigint;
    v_result jsonb;
BEGIN
    PERFORM create_user_for_test('password_scope_admin', 'password_scope_admin@test.local');
    PERFORM create_user_for_test('password_scope_editor', 'password_scope_editor@test.local');
    PERFORM create_user_for_test('password_scope_regular', 'password_scope_regular@test.local');
    PERFORM create_user_for_test('password_scope_privileged', 'password_scope_privileged@test.local');
    PERFORM create_user_for_test('password_scope_outsider', 'password_scope_outsider@test.local');
    v_admin := get_user_id('password_scope_admin');
    v_editor := get_user_id('password_scope_editor');
    v_regular := get_user_id('password_scope_regular');
    v_privileged := get_user_id('password_scope_privileged');
    v_outsider := get_user_id('password_scope_outsider');

    INSERT INTO public.organizations (title) VALUES ('Password scope organization')
    RETURNING id INTO v_org;
    INSERT INTO public.organizations (title) VALUES ('Password scope other organization')
    RETURNING id INTO v_other_org;
    UPDATE public.user_info SET organization = v_other_org WHERE id = v_regular;
    INSERT INTO public.units (title, organization)
    VALUES ('Password scope unit', v_org) RETURNING id INTO v_unit;
    INSERT INTO public.units (title, organization)
    VALUES ('Password scope other unit', v_other_org) RETURNING id INTO v_other_unit;
    INSERT INTO public.occasions (title, link, start_time, end_time, unit, organization)
    VALUES ('Password scope occasion', 'password-scope-' || gen_random_uuid(), now(), now() + interval '1 day', v_unit, v_org)
    RETURNING id INTO v_occasion;
    INSERT INTO public.occasions (title, link, start_time, end_time, unit, organization)
    VALUES ('Password scope other occasion', 'password-scope-other-' || gen_random_uuid(), now(), now() + interval '1 day', v_other_unit, v_other_org)
    RETURNING id INTO v_other_occasion;

    INSERT INTO public.organization_users ("user", organization, is_admin)
    VALUES (v_admin, v_org, true);
    INSERT INTO public.unit_users ("user", unit, is_editor)
    VALUES (v_editor, v_unit, true), (v_privileged, v_unit, true);
    INSERT INTO public.occasion_users ("user", occasion)
    VALUES (v_regular, v_occasion), (v_privileged, v_occasion),
           (v_outsider, v_other_occasion);

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_result := public.reset_user_password(v_regular, 'new-password');
    PERFORM assert_eq(v_result->>'code', '200',
        'organization admin can reset a member whose profile belongs to another organization');

    PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
    v_result := public.reset_user_password(v_regular, 'new-password');
    PERFORM assert_eq(v_result->>'code', '200',
        'unit editor can reset an ordinary user in the unit');
    v_result := public.reset_user_password(v_privileged, 'new-password');
    PERFORM assert_eq(v_result->>'code', '4030',
        'unit editor cannot reset a privileged user');
    v_result := public.reset_user_password(v_outsider, 'new-password');
    PERFORM assert_eq(v_result->>'code', '4030',
        'unit editor cannot reset a user outside the unit');

    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_result := public.reset_user_password(v_regular, 'new-password');
    PERFORM assert_eq(v_result->>'code', '4030',
        'anonymous caller cannot reset another user password');
END;
$$;
