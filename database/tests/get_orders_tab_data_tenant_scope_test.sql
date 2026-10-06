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
  v_foreign_order bigint;
  v_own_order bigint;
  v_result jsonb;
  v_link text := 'duplicate-orders-' || gen_random_uuid()::text;
BEGIN
  PERFORM create_user_for_test('orders_tenant_user', 'orders-tenant@test.local');
  v_user := get_user_id('orders_tenant_user');

  INSERT INTO public.organizations (title)
  VALUES ('Foreign orders organization') RETURNING id INTO v_foreign_org;
  INSERT INTO public.organizations (title)
  VALUES ('Own orders organization') RETURNING id INTO v_own_org;
  UPDATE public.user_info SET organization = v_own_org WHERE id = v_user;

  INSERT INTO public.units (title, organization)
  VALUES ('Foreign orders unit', v_foreign_org) RETURNING id INTO v_foreign_unit;
  INSERT INTO public.units (title, organization)
  VALUES ('Own orders unit', v_own_org) RETURNING id INTO v_own_unit;

  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES ('Foreign orders occasion', v_link, now(), now() + interval '1 day',
    v_foreign_org, v_foreign_unit) RETURNING id INTO v_foreign_occasion;
  INSERT INTO public.occasions
    (title, link, start_time, end_time, organization, unit)
  VALUES ('Own orders occasion', v_link, now(), now() + interval '1 day',
    v_own_org, v_own_unit) RETURNING id INTO v_own_occasion;

  INSERT INTO eshop.orders (order_symbol, occasion, state, data, price, currency_code)
  VALUES (public.generate_order_symbol(), v_foreign_occasion, 'ordered', '{}', 100, 'CZK')
  RETURNING id INTO v_foreign_order;
  INSERT INTO eshop.orders (order_symbol, occasion, state, data, price, currency_code)
  VALUES (public.generate_order_symbol(), v_own_occasion, 'ordered', '{}', 100, 'CZK')
  RETURNING id INTO v_own_order;
  INSERT INTO public.occasion_users
    (occasion, "user", is_editor_order_view, is_editor_view)
  VALUES (v_own_occasion, v_user, true, true);

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  v_result := public.get_orders_tab_data(v_link);
  RESET ROLE;

  PERFORM assert_eq(jsonb_array_length(v_result->'orders'), 1,
    'duplicate occasion links return only the caller organization orders');
  PERFORM assert_eq((v_result->'orders'->0->>'id')::bigint, v_own_order,
    'orders belong to the authorized occasion');
  PERFORM assert_true(v_result#>>'{orders,0,order_symbol}' ~ '^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$', 'authorized list carries order symbol');
  PERFORM assert_eq(v_result->'email_delivery', '{}'::jsonb,
    'email summaries resolve the same authorized occasion without ambiguity');

  UPDATE public.occasion_users SET is_editor_order_view = false
  WHERE occasion = v_own_occasion AND "user" = v_user;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.get_orders_tab_data(v_link);
    RAISE EXCEPTION 'orders read unexpectedly allowed';
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    IF SQLERRM <> 'get_orders failed: User is not authorized to access this occasion' THEN
      RAISE;
    END IF;
  END;
END
$$ LANGUAGE plpgsql;

ROLLBACK;
