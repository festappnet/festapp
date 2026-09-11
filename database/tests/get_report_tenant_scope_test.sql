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
  v_link text := 'duplicate-report-' || gen_random_uuid()::text;
BEGIN
  PERFORM create_user_for_test(
    'report_tenant_user',
    'report-tenant@test.local'
  );
  v_user := get_user_id('report_tenant_user');

  INSERT INTO public.organizations (title)
  VALUES ('Foreign report test organization')
  RETURNING id INTO v_foreign_org;
  INSERT INTO public.organizations (title)
  VALUES ('Own report test organization')
  RETURNING id INTO v_own_org;

  UPDATE public.user_info SET organization = v_own_org WHERE id = v_user;

  INSERT INTO public.units (title, organization)
  VALUES ('Foreign report test unit', v_foreign_org)
  RETURNING id INTO v_foreign_unit;
  INSERT INTO public.units (title, organization)
  VALUES ('Own report test unit', v_own_org)
  RETURNING id INTO v_own_unit;

  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Foreign duplicate report occasion', v_link, now(), now() + interval '1 day',
      v_foreign_org, v_foreign_unit)
  RETURNING id INTO v_foreign_occasion;
  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Own duplicate report occasion', v_link, now(), now() + interval '1 day',
      v_own_org, v_own_unit)
  RETURNING id INTO v_own_occasion;

  INSERT INTO public.occasion_users
    (occasion, "user", is_editor_order_view)
  VALUES (v_own_occasion, v_user, true);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.get_report_ws(v_link);

  PERFORM assert_eq(
    (v_result->>'code')::integer,
    200,
    'report reader resolves duplicate links inside the caller organization'
  );
  PERFORM assert_true(
    (v_result->>'data') LIKE '%Počet objednávek celkem:%',
    'report reader returns report data for the authorized occasion'
  );
  PERFORM assert_true(
    v_foreign_occasion <> v_own_occasion,
    'duplicate report fixture uses two distinct occasions'
  );
END
$$ LANGUAGE plpgsql;

ROLLBACK;
