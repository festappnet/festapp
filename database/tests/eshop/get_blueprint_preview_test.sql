DO $$
DECLARE
    v_org bigint;
    v_unit bigint;
    v_occasion bigint;
    v_blueprint bigint;
    v_key uuid;
    v_user uuid;
    v_result jsonb;
BEGIN
    INSERT INTO public.organizations(title) VALUES ('Blueprint preview test') RETURNING id INTO v_org;
    INSERT INTO public.units(organization, title) VALUES (v_org, 'Preview unit') RETURNING id INTO v_unit;
    INSERT INTO public.occasions(organization, unit, title, link, start_time, end_time)
    VALUES (v_org, v_unit, 'Preview occasion', 'blueprint-preview-' || gen_random_uuid(), now(), now() + interval '1 day')
    RETURNING id INTO v_occasion;
    INSERT INTO eshop.blueprints(organization, occasion, title, objects)
    VALUES (v_org, v_occasion, 'Preview seats', '[]') RETURNING id INTO v_blueprint;
    INSERT INTO public.forms(occasion, blueprint, title, link, is_open)
    VALUES (v_occasion, v_blueprint, 'Closed form', 'blueprint-form-' || gen_random_uuid(), false)
    RETURNING key INTO v_key;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    v_result := public.get_blueprint(NULL, v_key, v_blueprint);
    PERFORM assert_eq((v_result->>'code')::integer, 400, 'Anonymous users cannot preview a closed form');

    SELECT id INTO v_user FROM auth.users LIMIT 1;
    PERFORM assert_not_null(v_user, 'Auth fixture user required');
    PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
    INSERT INTO public.occasion_users(occasion, "user", is_editor_order_view)
    VALUES (v_occasion, v_user, false);
    v_result := public.get_blueprint(NULL, v_key, v_blueprint);
    PERFORM assert_eq((v_result->>'code')::integer, 400, 'An occasion member without order-view rights cannot preview');

    UPDATE public.occasion_users SET is_editor_order_view = true
    WHERE occasion = v_occasion AND "user" = v_user;
    v_result := public.get_blueprint(NULL, v_key, v_blueprint);
    PERFORM assert_eq((v_result->>'code')::integer, 200, 'Order-view editors can load the closed form blueprint');
    PERFORM assert_eq((v_result #>> '{data,id}')::bigint, v_blueprint, 'Preview returns the associated blueprint');

    v_result := public.get_blueprint(NULL, v_key, v_blueprint + 1);
    PERFORM assert_eq((v_result->>'code')::integer, 400, 'Preview rights do not bypass blueprint association');

    PERFORM set_config('request.jwt.claim.sub', '', true);
    UPDATE public.forms SET is_open = true WHERE key = v_key;
    v_result := public.get_blueprint(NULL, v_key, v_blueprint);
    PERFORM assert_eq((v_result->>'code')::integer, 200, 'Anonymous users can still load an open form blueprint');
END $$;
