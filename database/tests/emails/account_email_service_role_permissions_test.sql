BEGIN;

-- Pause the disposable queue; no provider call or persistent account change.
UPDATE public.email_capacity SET paused = true, worker_url = NULL;

DO $$
DECLARE v_org bigint; v_user uuid;
BEGIN
  INSERT INTO public.organizations(title, data)
  VALUES ('Account producer fixture', '{"IS_REGISTRATION_ENABLED":true}')
  RETURNING id INTO v_org;
  PERFORM public.create_user_for_test('producer_account', 'account@example.invalid');
  v_user := public.get_user_id('producer_account');
  UPDATE public.user_info SET organization = v_org WHERE id = v_user;
  PERFORM set_config('festapp.account_fixture', jsonb_build_object(
    'organization', v_org, 'user', v_user, 'token', gen_random_uuid()
  )::text, true);
END;
$$;

-- Reproduce production ACLs. Definer account/prepared producers must still work.
REVOKE USAGE ON SCHEMA extensions FROM service_role;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $$
DECLARE
  v_fixture jsonb := current_setting('festapp.account_fixture')::jsonb;
  v_context jsonb := jsonb_build_object('organization', v_fixture->'organization');
  v_result jsonb;
  v_replay jsonb;
  v_kind text;
BEGIN
  v_result := public.enqueue_account_email(
    'reset_token', jsonb_build_object('user_id', v_fixture->'user', 'token', v_fixture->'token'),
    v_context, 'account@example.invalid', '{"sealed":"fixture"}', repeat('a', 64),
    'account-role-reset', 'RESET_PASSWORD', now() + interval '1 hour'
  );
  v_replay := public.enqueue_account_email(
    'reset_token', jsonb_build_object('user_id', v_fixture->'user', 'token', v_fixture->'token'),
    v_context, 'account@example.invalid', '{"sealed":"fixture"}', repeat('a', 64),
    'account-role-reset', 'RESET_PASSWORD', now() + interval '1 hour'
  );
  IF v_result->>'message_id' IS NULL OR v_result->>'message_id' <> v_replay->>'message_id'
    OR NOT EXISTS (SELECT 1 FROM public.user_reset_token
      WHERE "user" = (v_fixture->>'user')::uuid AND token = (v_fixture->>'token')::uuid) THEN
    RAISE EXCEPTION 'Reset email and proof must enqueue atomically under the runtime role';
  END IF;

  v_result := public.enqueue_account_email(
    'register', '{"password":"fixture-password","data":{"name":"Fixture","surname":"Account"},"unit_title":"Fixture unit"}',
    v_context, 'registration@example.invalid', '{"sealed":"fixture"}', repeat('b', 64),
    'account-role-register', 'SIGN_IN_CODE', now() + interval '1 hour'
  );
  IF v_result->>'message_id' IS NULL OR v_result#>>'{domain,code}' <> '200'
    OR NOT EXISTS (SELECT 1 FROM public.user_info
      WHERE id = (v_result#>>'{domain,id}')::uuid
        AND organization = (v_fixture->>'organization')::bigint) THEN
    RAISE EXCEPTION 'Registration and its email must enqueue atomically under the runtime role';
  END IF;

  v_result := public.enqueue_account_email(
    'register', '{"invitation_code":"012345","data":{"name":"Secure","surname":"Account"},"unit_title":"Fixture unit"}',
    v_context, 'secure-registration@example.invalid', '{"sealed":"fixture"}', repeat('d', 64),
    'account-role-register-v2', 'SIGN_IN_CODE', now() + interval '10 minutes'
  );
  IF v_result#>>'{domain,code}' <> '200' OR NOT EXISTS (
    SELECT 1 FROM public.sign_in_codes WHERE user_id=(v_result#>>'{domain,id}')::uuid
  ) THEN RAISE EXCEPTION 'V2 registration must store separate proof'; END IF;
  PERFORM set_config('festapp.v2_registered_user',v_result#>>'{domain,id}',true);

  FOREACH v_kind IN ARRAY ARRAY[
    'registration', 'sign_in', 'reset_password', 'app_links', 'deletion_confirm',
    'deletion_complete', 'google_mailbox', 'gotrue', 'custom'
  ] LOOP
    v_result := public.enqueue_prepared_email(
      v_kind, v_context, 'prepared@example.invalid', '{"sealed":"fixture"}',
      'prepared-role-' || v_kind, repeat('c', 64), '', now() + interval '1 hour'
    );
    v_replay := public.enqueue_prepared_email(
      v_kind, v_context, 'prepared@example.invalid', '{"sealed":"fixture"}',
      'prepared-role-' || v_kind, repeat('c', 64), '', now() + interval '1 hour'
    );
    IF v_result->>'message_id' IS NULL OR v_result->>'message_id' <> v_replay->>'message_id' THEN
      RAISE EXCEPTION 'Prepared producer % must enqueue once under the runtime role', v_kind;
    END IF;
  END LOOP;
END;
$$;

RESET ROLE;
DO $$
DECLARE u uuid := current_setting('festapp.v2_registered_user')::uuid; pw text;
BEGIN
 SELECT encrypted_password INTO pw FROM auth.users WHERE id=u;
 IF extensions.crypt('012345',pw)=pw THEN RAISE EXCEPTION 'One-time code became permanent password'; END IF;
 IF public.consume_sign_in_code_v1('secure-registration@example.invalid',
     (current_setting('festapp.account_fixture')::jsonb->>'organization')::bigint,'012345')->>'userId'
     IS DISTINCT FROM u::text THEN RAISE EXCEPTION 'V2 registration proof exchange failed'; END IF;
END $$;
ROLLBACK;
