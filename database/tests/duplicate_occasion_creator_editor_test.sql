BEGIN;

DO $$
DECLARE
  v_actor uuid;
  v_organization bigint;
  v_unit bigint;
  v_source bigint;
  v_copy bigint;
  v_blueprint bigint;
  v_product_type bigint;
  v_product bigint;
  v_spot bigint;
  v_form bigint;
  v_result jsonb;
  v_saved jsonb;
BEGIN
  PERFORM create_user_for_test('occasion_copy_manager', 'occasion_copy_manager@test.local');
  v_actor := get_user_id('occasion_copy_manager');

  INSERT INTO public.organizations(title)
  VALUES ('Occasion copy editor test') RETURNING id INTO v_organization;
  INSERT INTO public.units(title, organization)
  VALUES ('Occasion copy unit', v_organization) RETURNING id INTO v_unit;
  INSERT INTO public.unit_users(unit, "user", is_manager, is_editor)
  VALUES (v_unit, v_actor, true, true);
  INSERT INTO public.occasions
    (organization, unit, title, link, start_time, end_time,
     is_open, is_hidden, is_promoted, data, features)
  VALUES
    (v_organization, v_unit, 'Copy source',
     'copy-creator-' || gen_random_uuid()::text,
     now(), now() + interval '1 day', true, false, false,
     '{"image":"https://img.festapp.net/images/event.jpg"}'::jsonb,
     '[{"code":"ticket","is_enabled":true,"ticket_background":"https://img.festapp.net/images/ticket.jpg"}]'::jsonb)
  RETURNING id INTO v_source;

  INSERT INTO eshop.blueprints(occasion, organization, title, objects)
  VALUES (v_source, v_organization, 'Dance floor', '[]'::jsonb)
  RETURNING id INTO v_blueprint;
  INSERT INTO eshop.product_types(occasion, title, type)
  VALUES (v_source, 'Seat category', 'ticket') RETURNING id INTO v_product_type;
  INSERT INTO eshop.products(occasion, product_type, title, price)
  VALUES (v_source, v_product_type, 'Seat', 250)
  RETURNING id INTO v_product;
  INSERT INTO eshop.spots(occasion, blueprint, product, title)
  VALUES (v_source, v_blueprint, v_product, 'A1') RETURNING id INTO v_spot;
  UPDATE eshop.blueprints
  SET objects = jsonb_build_array(jsonb_build_object('type', 'spot', 'id', v_spot))
  WHERE id = v_blueprint;
  INSERT INTO public.forms(occasion, blueprint, title, link)
  VALUES (v_source, v_blueprint, 'Tickets', 'copy-form-' || gen_random_uuid()::text)
  RETURNING id INTO v_form;
  INSERT INTO public.form_fields(form, product_type, title, type)
  VALUES (v_form, v_product_type, 'Ticket', 'ticket');

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_actor::text, true);
  PERFORM assert_true(NOT public.get_is_editor_on_occasion(v_source),
    'unit manager is not automatically an occasion editor');
  v_result := public.duplicate_occasion_client_sync_v1(
    v_source, gen_random_uuid());
  v_copy := (v_result #>> '{data,occasionId}')::bigint;

  PERFORM assert_eq(v_result->>'status', 'applied', 'copy command applies');
  PERFORM assert_true(v_copy IS NOT NULL, 'copy is created');
  PERFORM assert_true(public.get_is_editor_on_occasion(v_copy),
    'copy creator can edit the new occasion');
  PERFORM assert_true(public.check_upload_permission(p_occasion_id => v_copy),
    'copy creator can upload occasion media');
  SELECT public.save_occasion_client_sync_v1(
    v_copy, gen_random_uuid(), 0,
    jsonb_build_object(
      'id', o.id, 'organization', o.organization, 'unit', o.unit,
      'title', o.title, 'link', o.link, 'start_time', o.start_time,
      'end_time', o.end_time, 'is_open', o.is_open,
      'is_hidden', o.is_hidden, 'is_promoted', o.is_promoted,
      'data', o.data, 'features', o.features))
  INTO v_saved FROM public.occasions o WHERE o.id = v_copy;
  PERFORM assert_eq(v_saved->>'status', 'applied',
    'copy creator can save media URLs on the new occasion');
  PERFORM assert_eq((SELECT data->>'client_sync_v1' FROM public.occasions
    WHERE id = v_copy), 'false', 'copy stays outside client sync v1');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM eshop.spots s
    JOIN eshop.blueprints b ON b.id = s.blueprint AND b.occasion = v_copy
    JOIN eshop.products p ON p.id = s.product AND p.occasion = v_copy
    JOIN eshop.product_types pt ON pt.id = p.product_type AND pt.occasion = v_copy
    WHERE s.occasion = v_copy AND s.id <> v_spot),
    'seat, blueprint, product, and type all point into the copy');
  PERFORM assert_true(EXISTS (
    SELECT 1 FROM public.forms f
    JOIN public.form_fields ff ON ff.form = f.id
    JOIN eshop.product_types pt ON pt.id = ff.product_type
      AND pt.occasion = v_copy
    WHERE f.occasion = v_copy AND f.blueprint <> v_blueprint),
    'copied form and field point into the copied ticket graph');
END $$;

ROLLBACK;
