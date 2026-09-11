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
  v_link text := 'duplicate-inventory-' || gen_random_uuid()::text;
BEGIN
  PERFORM create_user_for_test(
    'inventory_tenant_user',
    'inventory-tenant@test.local'
  );
  v_user := get_user_id('inventory_tenant_user');

  INSERT INTO public.organizations (title)
  VALUES ('Foreign inventory test organization')
  RETURNING id INTO v_foreign_org;
  INSERT INTO public.organizations (title)
  VALUES ('Own inventory test organization')
  RETURNING id INTO v_own_org;

  UPDATE public.user_info SET organization = v_own_org WHERE id = v_user;

  INSERT INTO public.units (title, organization)
  VALUES ('Foreign inventory test unit', v_foreign_org)
  RETURNING id INTO v_foreign_unit;
  INSERT INTO public.units (title, organization)
  VALUES ('Own inventory test unit', v_own_org)
  RETURNING id INTO v_own_unit;

  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Foreign duplicate inventory occasion', v_link, now(), now() + interval '1 day',
      v_foreign_org, v_foreign_unit)
  RETURNING id INTO v_foreign_occasion;
  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES
    ('Own duplicate inventory occasion', v_link, now(), now() + interval '1 day',
      v_own_org, v_own_unit)
  RETURNING id INTO v_own_occasion;

  INSERT INTO public.occasion_users
    (occasion, "user", is_editor_order_view)
  VALUES (v_own_occasion, v_user, true);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  v_result := public.get_inventory_pools_by_occasion_link(v_link);

  PERFORM assert_eq(
    (v_result#>>'{occasion,id}')::bigint,
    v_own_occasion,
    'inventory reader resolves duplicate links inside the caller organization'
  );
  PERFORM assert_true(
    (v_result#>>'{occasion,id}')::bigint <> v_foreign_occasion,
    'inventory reader never returns the foreign duplicate'
  );
  PERFORM assert_eq(
    v_result->'pools',
    '[]'::jsonb,
    'empty inventory pool data remains a successful response'
  );
END
$$ LANGUAGE plpgsql;

ROLLBACK;
