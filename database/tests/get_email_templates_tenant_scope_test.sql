BEGIN;

DO $$
DECLARE
  v_user uuid;
  v_foreign_org bigint;
  v_own_org bigint;
  v_foreign_unit bigint;
  v_own_unit bigint;
  v_foreign_occasion bigint;
  v_own_occasion bigint;
  v_result jsonb;
  v_link text := 'duplicate-email-templates-' || gen_random_uuid()::text;
BEGIN
  PERFORM create_user_for_test(
    'email_templates_tenant_user',
    'email-templates-tenant@test.local'
  );
  v_user := get_user_id('email_templates_tenant_user');

  INSERT INTO public.organizations (title)
  VALUES ('Foreign email templates test organization')
  RETURNING id INTO v_foreign_org;
  INSERT INTO public.organizations (title)
  VALUES ('Own email templates test organization')
  RETURNING id INTO v_own_org;

  UPDATE public.user_info SET organization = v_own_org WHERE id = v_user;

  INSERT INTO public.units (title, organization)
  VALUES ('Foreign email templates test unit', v_foreign_org)
  RETURNING id INTO v_foreign_unit;
  INSERT INTO public.units (title, organization)
  VALUES ('Own email templates test unit', v_own_org)
  RETURNING id INTO v_own_unit;

  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Foreign duplicate email occasion', v_link, now(), now() + interval '1 day',
      v_foreign_org, v_foreign_unit)
  RETURNING id INTO v_foreign_occasion;
  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Own duplicate email occasion', v_link, now(), now() + interval '1 day',
      v_own_org, v_own_unit)
  RETURNING id INTO v_own_occasion;

  INSERT INTO public.occasion_users
    (occasion, "user", is_editor_view)
  VALUES (v_own_occasion, v_user, true);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.get_all_email_templates_via_occasion_link(v_link);

  PERFORM assert_eq(
    (v_result#>>'{occasion,id}')::bigint,
    v_own_occasion,
    'e-mail templates resolve duplicate links inside the caller organization'
  );
  PERFORM assert_true(
    (v_result#>>'{occasion,id}')::bigint <> v_foreign_occasion,
    'e-mail templates never return the foreign duplicate'
  );
  PERFORM assert_true(
    jsonb_typeof(v_result->'templates') = 'array',
    'e-mail templates return a valid template list'
  );
END
$$ LANGUAGE plpgsql;

ROLLBACK;
