BEGIN;
DO $$
DECLARE
  v_org bigint;
  v_result jsonb;
  v_template jsonb;
BEGIN
  INSERT INTO public.organizations(title, data)
  VALUES ('Email template contract org', '{"IS_APP_SUPPORTED":true}'::jsonb)
  RETURNING id INTO v_org;

  INSERT INTO public.email_templates(
    html, subject, organization, code, title
  ) VALUES (
    '<p>{{confirmationUrl}}</p>',
    'Confirm deletion',
    v_org,
    'ACCOUNT_DELETION_CONFIRM',
    'Account deletion confirmation'
  );

  v_result := public.get_all_email_templates(
    jsonb_build_object('organization', v_org)
  );
  SELECT value INTO v_template FROM jsonb_array_elements(v_result)
  WHERE value->>'code' = 'ACCOUNT_DELETION_CONFIRM';

  PERFORM assert_eq(
    v_template->>'code',
    'ACCOUNT_DELETION_CONFIRM',
    'system template is returned by code'
  );
  PERFORM assert_eq(
    v_template->>'title',
    'Account deletion confirmation',
    'template title survives the RPC contract'
  );
  INSERT INTO public.email_templates(html,subject,organization,code)
  SELECT '<p>Test</p>', 'Test', v_org, code FROM unnest(ARRAY[
    'ACCOUNT_DELETION_COMPLETE','APP_LINKS','SIGN_IN_CODE','RESET_PASSWORD',
    'TICKET_ORDER_CONFIRMATION','CUSTOM_NOTICE']) code;
  v_result := public.get_all_email_templates(jsonb_build_object('organization',v_org));
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('ACCOUNT_DELETION_CONFIRM','ACCOUNT_DELETION_COMPLETE','APP_LINKS','SIGN_IN_CODE','RESET_PASSWORD')),5,
    'full app keeps all five app-related templates');
  UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":false}' WHERE id=v_org;
  v_result := public.get_all_email_templates(jsonb_build_object('organization',v_org));
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('ACCOUNT_DELETION_CONFIRM','ACCOUNT_DELETION_COMPLETE','APP_LINKS','SIGN_IN_CODE','RESET_PASSWORD')),0,
    'ticketing app hides account and app templates');
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('TICKET_ORDER_CONFIRMATION','CUSTOM_NOTICE')),2,
    'ticketing and custom templates remain available');
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_templates WHERE organization=v_org),7,
    'visibility does not delete stored templates');
END $$;

ROLLBACK;
