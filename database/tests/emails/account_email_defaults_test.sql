BEGIN;

DO $$
DECLARE v_org bigint; v_code text; v_template jsonb; v_health jsonb; v_wrapper bigint; v_resolved jsonb;
BEGIN
  INSERT INTO public.organizations(title,data)
  VALUES ('Default account template fixture','{"APP_NAME":"Fixture","DEFAULT_URL":"https://account-fixture.invalid"}')
  RETURNING id INTO v_org;
  INSERT INTO public.email_wrappers(organization,title,html)
  VALUES (v_org,'Organization wrapper fixture','<section>{{content}}</section>')
  RETURNING id INTO v_wrapper;
  FOREACH v_code IN ARRAY ARRAY['ACCOUNT_DELETION_CONFIRM','ACCOUNT_DELETION_COMPLETE','APP_LINKS'] LOOP
    v_resolved := public.get_email_template_and_wrapper(v_code,jsonb_build_object('organization',v_org));
    v_template := v_resolved->'template';
    IF (v_resolved#>>'{wrapper,id}')::bigint IS DISTINCT FROM v_wrapper THEN
      RAISE EXCEPTION 'Generic % must use its recipient organization wrapper',v_code;
    END IF;
    IF jsonb_typeof(v_template) IS DISTINCT FROM 'object'
      OR v_template->>'organization' IS NOT NULL
      OR coalesce(length(v_template->>'html'),0)=0
      OR coalesce(length(v_template->>'subject'),0)=0 THEN
      RAISE EXCEPTION 'Missing generic fallback for %',v_code;
    END IF;
    IF (SELECT count(*) FROM public.email_templates WHERE code=v_code
        AND organization IS NULL AND unit IS NULL AND occasion IS NULL)<>1 THEN
      RAISE EXCEPTION 'Default % must be idempotent',v_code;
    END IF;
  END LOOP;
  INSERT INTO public.email_templates(code,organization,title,subject,html)
  VALUES ('ACCOUNT_DELETION_CONFIRM',v_org,'Tenant fixture','Custom subject','<p>Custom {{confirmationUrl}}</p>');
  v_template := public.get_email_template_and_wrapper('ACCOUNT_DELETION_CONFIRM',jsonb_build_object('organization',v_org))->'template';
  IF v_template->>'subject'<>'Custom subject' THEN
    RAISE EXCEPTION 'Tenant override must retain precedence';
  END IF;

  -- Failures before enqueue must be visible, even with no failed queue message.
  DELETE FROM public.email_templates WHERE code='ACCOUNT_DELETION_COMPLETE';
  v_health := public.get_email_delivery_health();
  IF NOT (v_health->'alerts' ? 'account_templates_missing')
    OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_health->'missing_account_templates') missing
      WHERE missing->>'organization'=v_org::text AND missing->>'code'='ACCOUNT_DELETION_COMPLETE') THEN
    RAISE EXCEPTION 'Health must identify the organization and missing template';
  END IF;
END;
$$;

ROLLBACK;
