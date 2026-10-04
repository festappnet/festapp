BEGIN;

SELECT assert_false(
  has_table_privilege('authenticated',
    'public.organization_notification_secrets', 'SELECT'),
  'authenticated must not read notification secrets directly'
);
SELECT assert_false(
  has_table_privilege('service_role',
    'public.organization_notification_secrets', 'SELECT'),
  'service role must use the audited delivery-config RPC'
);

DO $$
DECLARE
  v_org bigint;
  v_config jsonb;
BEGIN
  INSERT INTO public.organizations(title, data)
  VALUES ('Notification secret test', jsonb_build_object(
    'ONESIGNAL_APP_ID', 'test-app',
    'DEFAULT_URL', 'https://example.test'
  ))
  RETURNING id INTO v_org;

  INSERT INTO public.organization_notification_secrets(
    organization,
    onesignal_rest_api_key
  ) VALUES (v_org, 'server-only-test-value');

  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  SET LOCAL ROLE service_role;
  v_config := public.get_organization_notification_delivery_config(v_org);
  PERFORM assert_eq(v_config->>'onesignal_app_id', 'test-app',
    'service role should receive the OneSignal app id');
  PERFORM assert_eq(v_config->>'onesignal_rest_api_key',
    'server-only-test-value',
    'service role should receive the server-only credential');
  RESET ROLE;

  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  BEGIN
    -- JWT claims alone do not impersonate a caller on the postgres maintenance
    -- connection. Exercise the RPC's actual database execution privilege too.
    SET LOCAL ROLE authenticated;
    PERFORM public.get_organization_notification_delivery_config(v_org);
    PERFORM assert_fail('authenticated callers must not receive delivery credentials');
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$$;

ROLLBACK;
