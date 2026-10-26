-- Canonical invitation status comes only from accepted SIGN_IN_CODE evidence.
DO $$
DECLARE
  v_occasion bigint;
  v_template bigint;
  v_status jsonb;
  v_recipient uuid;
  v_projected_user jsonb;
BEGIN
  PERFORM create_user_for_test('invite_status_editor', 'invite-status-editor@test.local');
  PERFORM create_user_for_test('invite_status_recipient', 'invite-status-recipient@test.local');
  v_recipient := get_user_id('invite_status_recipient');

  INSERT INTO public.occasions (title, link, start_time, end_time, is_open)
  VALUES (
    'Invitation status test',
    'invitation-status-' || gen_random_uuid(),
    now(), now() + interval '1 day', true
  ) RETURNING id INTO v_occasion;

  INSERT INTO public.occasion_users
    (occasion, "user", is_editor, is_editor_view, data)
  VALUES
    (v_occasion, get_user_id('invite_status_editor'), true, true, '{}'::jsonb),
    (v_occasion, v_recipient, false, false, '{}'::jsonb);

  INSERT INTO public.email_templates
    (organization, occasion, code, subject, html)
  SELECT organization, v_occasion, 'SIGN_IN_CODE', 'Code', '<p>Code</p>'
  FROM public.occasions WHERE id = v_occasion
  RETURNING id INTO v_template;

  INSERT INTO public.log_emails
    ("to", template, organization, occasion, recipient_user, created_at)
  SELECT
    'invite-status-recipient@test.local', v_template::text,
    organization, v_occasion, v_recipient,
    timestamptz '2026-08-08 08:00:00+00'
  FROM public.occasions WHERE id = v_occasion;

  INSERT INTO public.log_emails
    ("to", template, organization, occasion, recipient_user, created_at)
  SELECT
    'invite-status-recipient@test.local', v_template::text,
    organization, v_occasion, v_recipient,
    timestamptz '2026-08-08 09:00:00+00'
  FROM public.occasions WHERE id = v_occasion;

  PERFORM set_config(
    'request.jwt.claim.sub',
    get_user_id('invite_status_editor')::text,
    true
  );
  v_status := public.get_occasion_sign_in_email_statuses(v_occasion);

  PERFORM assert_eq(jsonb_array_length(v_status), 1,
    'one recipient status is returned');
  PERFORM assert_eq(v_status #>> '{0,user}', v_recipient::text,
    'status is linked by user id');
  PERFORM assert_eq(v_status #>> '{0,send_count}', '2',
    'all accepted sends are counted');
  PERFORM assert_eq(v_status #>> '{0,first_sent_at}',
    '2026-08-08T08:00:00+00:00', 'first send is retained');
  PERFORM assert_eq(v_status #>> '{0,last_sent_at}',
    '2026-08-08T09:00:00+00:00', 'last send is retained');

  SELECT item INTO v_projected_user
  FROM jsonb_array_elements(
    public.get_occasion_users_for_edit(v_occasion)::jsonb
      #> '{data,occasion_users}'
  ) item
  WHERE item->>'user' = v_recipient::text;
  PERFORM assert_eq(
    v_projected_user #>> '{data,is_invited}',
    'true',
    'legacy editor response projects invitation truth from accepted evidence'
  );

  PERFORM set_config('request.jwt.claim.sub', v_recipient::text, true);
  BEGIN
    PERFORM public.get_occasion_sign_in_email_statuses(v_occasion);
    RAISE EXCEPTION 'expected invitation status authorization failure';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;
