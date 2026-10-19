BEGIN;
DO $$
DECLARE
  v_org bigint;
  v_result jsonb;
  v_unit bigint;
  v_occasion bigint;
  v_context jsonb;
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
    'TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER',
    'TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE','ORDER_OVERVIEW',
    'waitlist_confirmation','waitlist_offer','CUSTOM_NOTICE','TEAM_INVITATION',
    'TEAM_ACCESS_NOTIFICATION']) code;
  v_result := public.get_all_email_templates(jsonb_build_object('organization',v_org));
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('ACCOUNT_DELETION_CONFIRM','ACCOUNT_DELETION_COMPLETE','APP_LINKS','SIGN_IN_CODE','RESET_PASSWORD')),5,
    'full app keeps all five app-related templates');
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('CUSTOM_NOTICE','TEAM_INVITATION','TEAM_ACCESS_NOTIFICATION')),0,
    'unknown and internal team templates are never offered in the editor');
  UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":false}' WHERE id=v_org;
  v_result := public.get_all_email_templates(jsonb_build_object('organization',v_org));
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('ACCOUNT_DELETION_CONFIRM','ACCOUNT_DELETION_COMPLETE','APP_LINKS','SIGN_IN_CODE','RESET_PASSWORD')),0,
    'ticketing app hides account and app templates');
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' = 'TICKET_ORDER_CONFIRMATION'),1,
    'supported ticketing templates remain available');
  PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(v_result) x
    WHERE x->>'code' IN ('CUSTOM_NOTICE','TEAM_INVITATION','TEAM_ACCESS_NOTIFICATION')),0,
    'ticketing editor hides unknown and internal team templates');
  INSERT INTO public.units(title,organization) VALUES ('Visibility unit',v_org)
    RETURNING id INTO v_unit;
  INSERT INTO public.occasions(title,link,unit,organization,start_time,end_time)
    VALUES ('Visibility occasion',gen_random_uuid()::text,v_unit,v_org,now(),now()+interval '1 day')
    RETURNING id INTO v_occasion;
  -- Unknown defaults, inherited entries and local overrides must all be hidden.
  INSERT INTO public.email_templates(html,subject,code)
    VALUES ('Global team','Global team','TEAM_INVITATION');
  INSERT INTO public.email_templates(html,subject,code,unit,organization)
    VALUES ('Unit team','Unit team','TEAM_ACCESS_NOTIFICATION',v_unit,v_org);
  INSERT INTO public.email_templates(html,subject,code,occasion,unit,organization)
    VALUES ('Local custom','Local custom','FUTURE_TEMPLATE',v_occasion,v_unit,v_org),
           ('Saved order','Saved order','TICKET_ORDER_CONFIRMATION',v_occasion,v_unit,v_org);
  FOREACH v_context IN ARRAY ARRAY[
    jsonb_build_object('organization',v_org),
    jsonb_build_object('unit',v_unit),
    jsonb_build_object('occasion',v_occasion)
  ] LOOP
    v_result := public.get_all_email_templates(v_context);
    PERFORM assert_eq(jsonb_array_length(v_result),5,
      'ticketing contexts expose only the five supported order templates');
    UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":true}' WHERE id=v_org;
    v_result := public.get_all_email_templates(v_context);
    PERFORM assert_eq(jsonb_array_length(v_result),10,
      'full app contexts expose only the ten supported templates');
    UPDATE public.organizations SET data='{}' WHERE id=v_org;
    v_result := public.get_all_email_templates(v_context);
    PERFORM assert_eq(jsonb_array_length(v_result),5,
      'missing app support fails closed for app templates');
  END LOOP;
  v_result := public.get_entity_email_templates('occasion',v_occasion);
  SELECT value INTO v_template FROM jsonb_array_elements(v_result->'templates')
    WHERE value->>'code'='TICKET_ORDER_CONFIRMATION';
  PERFORM assert_eq(v_template->>'html','Saved order',
    'allowed templates retain their occasion override');
  PERFORM assert_eq((SELECT count(*)::int FROM public.email_templates WHERE organization=v_org),19,
    'visibility does not delete stored templates');
END $$;

ROLLBACK;
