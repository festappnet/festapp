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
END $$;
