BEGIN;

DO $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_occasion bigint;
  v_unit_editor uuid;
  v_unrelated_user uuid;
  v_features jsonb := '[
    {"code":"form","is_enabled":true},
    {"code":"deposit","is_enabled":true,"deposit_mode":"real","deposit_deadline":"on_site"}
  ]'::jsonb;
  v_config jsonb;
BEGIN
  PERFORM create_user_for_test(
    'occasion_save_unit_editor',
    'occasion_save_unit_editor@test.local'
  );
  PERFORM create_user_for_test(
    'occasion_save_unrelated',
    'occasion_save_unrelated@test.local'
  );
  v_unit_editor := get_user_id('occasion_save_unit_editor');
  v_unrelated_user := get_user_id('occasion_save_unrelated');

  INSERT INTO public.organizations(title)
  VALUES ('Occasion save permission test')
  RETURNING id INTO v_organization;

  INSERT INTO public.units(title, organization)
  VALUES ('Occasion save permission unit', v_organization)
  RETURNING id INTO v_unit;

  INSERT INTO public.unit_users(unit, "user", is_editor)
  VALUES (v_unit, v_unit_editor, true);

  INSERT INTO public.occasions(
    organization,
    unit,
    title,
    link,
    start_time,
    end_time,
    is_open,
    is_hidden,
    is_promoted,
    data,
    services,
    features
  ) VALUES (
    v_organization,
    v_unit,
    'Before save',
    'occasion-save-' || gen_random_uuid()::text,
    now(),
    now() + interval '1 day',
    true,
    false,
    false,
    '{}'::jsonb,
    '{}'::jsonb,
    '[{"code":"form","is_enabled":true}]'::jsonb
  ) RETURNING id INTO v_occasion;

  SELECT jsonb_build_object(
    'id', o.id,
    'organization', o.organization,
    'unit', o.unit,
    'title', 'After save',
    'link', o.link,
    'start_time', o.start_time,
    'end_time', o.end_time,
    'is_open', o.is_open,
    'is_hidden', o.is_hidden,
    'is_promoted', o.is_promoted,
    'data', o.data,
    'services', o.services,
    'features', v_features
  )
  INTO v_config
  FROM public.occasions o
  WHERE o.id = v_occasion;

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', v_unit_editor::text, true);

  -- This is the exact compatibility RPC used by older deployed clients.
  PERFORM public.update_occasion_203(v_config);

  PERFORM assert_eq(
    (SELECT title FROM public.occasions WHERE id = v_occasion),
    'After save',
    'a unit editor can save the occasion aggregate through the compatibility RPC'
  );
  PERFORM assert_eq(
    (SELECT features FROM public.occasions WHERE id = v_occasion),
    v_features,
    'occasion save persists enabled features and deposit configuration'
  );

  PERFORM set_config('request.jwt.claim.sub', v_unrelated_user::text, true);
  v_config := jsonb_set(v_config, '{title}', '"Unauthorized save"'::jsonb);
  BEGIN
    PERFORM public.update_occasion_203(v_config);
    PERFORM assert_fail('an unrelated user must not save occasion configuration');
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM assert_eq(
    (SELECT title FROM public.occasions WHERE id = v_occasion),
    'After save',
    'a rejected save leaves occasion configuration unchanged'
  );
END $$;

ROLLBACK;
