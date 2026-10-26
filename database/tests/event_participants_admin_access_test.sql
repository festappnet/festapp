BEGIN;

DO $$
DECLARE
  v_org bigint;
  v_unit bigint;
  v_occasion bigint;
  v_event bigint;
  v_admin uuid;
  v_editor_view uuid;
  v_editor uuid;
  v_manager uuid;
  v_approver uuid;
  v_participant uuid;
  v_result jsonb;
BEGIN
  PERFORM create_user_for_test('event_list_admin', 'event_list_admin@test.local');
  PERFORM create_user_for_test('event_list_view', 'event_list_view@test.local');
  PERFORM create_user_for_test('event_list_editor', 'event_list_editor@test.local');
  PERFORM create_user_for_test('event_list_manager', 'event_list_manager@test.local');
  PERFORM create_user_for_test('event_list_approver', 'event_list_approver@test.local');
  PERFORM create_user_for_test('event_list_participant', 'event_list_participant@test.local');
  v_admin := get_user_id('event_list_admin');
  v_editor_view := get_user_id('event_list_view');
  v_editor := get_user_id('event_list_editor');
  v_manager := get_user_id('event_list_manager');
  v_approver := get_user_id('event_list_approver');
  v_participant := get_user_id('event_list_participant');

  INSERT INTO public.organizations (title)
  VALUES (gen_random_uuid()::text)
  RETURNING id INTO v_org;
  INSERT INTO public.organization_users (organization, "user", is_admin)
  VALUES (v_org, v_admin, true);
  INSERT INTO public.units (title, organization)
  VALUES (gen_random_uuid()::text, v_org)
  RETURNING id INTO v_unit;
  INSERT INTO public.occasions (
    title, link, unit, organization, start_time, end_time
  )
  VALUES (
    gen_random_uuid()::text,
    gen_random_uuid()::text,
    v_unit,
    v_org,
    now(),
    now() + interval '1 day'
  )
  RETURNING id INTO v_occasion;

  INSERT INTO public.occasion_users (
    occasion, "user", is_editor_view, is_editor, is_manager, is_approver
  )
  VALUES
    (v_occasion, v_editor_view, true, false, false, false),
    (v_occasion, v_editor, false, true, false, false),
    (v_occasion, v_manager, false, false, true, false),
    (v_occasion, v_approver, false, false, false, true),
    (v_occasion, v_participant, false, false, false, false);
  INSERT INTO public.events (occasion, title, start_time, end_time)
  VALUES (
    v_occasion,
    gen_random_uuid()::text,
    now(),
    now() + interval '1 hour'
  )
  RETURNING id INTO v_event;
  INSERT INTO public.event_users (event, "user")
  VALUES (v_event, v_participant);

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(v_result->>'code', '200', 'admin can load participants');
  PERFORM assert_eq(
    v_result->'data'->0->>'id',
    v_participant::text,
    'admin receives the event participant'
  );

  PERFORM set_config('request.jwt.claim.sub', v_editor_view::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(
    v_result->>'code',
    '200',
    'editor-view can load participants'
  );
  PERFORM assert_true(
    NOT (v_result->'data'->0 ? 'email_readonly')
    AND NOT (v_result->'data'->0 ? 'phone')
    AND NOT (v_result->'data'->0 ? 'birth_date')
    AND NOT (v_result->'data'->0 ? 'data'),
    'participant list does not disclose unrelated profile fields'
  );
  v_result := public.sign_user_out_of_event(v_event, v_participant);
  PERFORM assert_eq(
    v_result->>'code',
    '403',
    'editor-view cannot remove a participant'
  );

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  v_result := public.sign_user_out_of_event(v_event, v_participant);
  PERFORM assert_eq(
    v_result->>'code',
    '403',
    'admin without editor rights cannot remove a participant'
  );

  PERFORM set_config('request.jwt.claim.sub', v_editor::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(v_result->>'code', '200', 'editor can load participants');
  v_result := public.sign_user_out_of_event(v_event, v_participant);
  PERFORM assert_eq(
    v_result->>'code',
    '200',
    'editor can remove a participant'
  );

  PERFORM set_config('request.jwt.claim.sub', v_manager::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(v_result->>'code', '403', 'manager cannot load participants');

  PERFORM set_config('request.jwt.claim.sub', v_approver::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(v_result->>'code', '403', 'approver cannot load participants');

  PERFORM set_config('request.jwt.claim.sub', v_participant::text, true);
  v_result := public.get_event_participants_for_edit(v_event);
  PERFORM assert_eq(v_result->>'code', '403', 'participant cannot load participants');
END;
$$;

ROLLBACK;
