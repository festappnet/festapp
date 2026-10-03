-- Run inside a transaction with the organization Google setting migration.
DO $$
DECLARE
  org bigint; other_org bigint; actor uuid;
  denied boolean := false;
BEGIN
  INSERT INTO public.organizations(title,data)
  VALUES('Google setting fixture','{"IS_REGISTRATION_ENABLED":true,"IS_GOOGLE_LOGIN_ENABLED":false}') RETURNING id INTO org;
  INSERT INTO public.organizations(title,data)
  VALUES('Other Google fixture','{"IS_GOOGLE_LOGIN_ENABLED":true}') RETURNING id INTO other_org;
  actor := public.create_user_in_organization_with_data_pure(org, 'google-setting@test.invalid', 'google-setting@test.invalid', 'fixture-only-password', '{}'::jsonb);
  INSERT INTO public.organization_users("user",organization,is_admin) VALUES(actor,org,true);
  INSERT INTO public.external_login_clients(client_id,organization,platform,origin,redirect_uri,provisioned,enabled)
  VALUES('org-setting-web',org,'web','https://setting.invalid','https://setting.invalid/google-auth',true,false),
        ('org-setting-flutter',org,'flutter-web','https://setting.invalid','https://setting.invalid/app/google-auth',true,false),
        ('org-setting-native',org,'android','https://setting.invalid','https://setting.invalid/app/google-auth',false,false),
        ('org-setting-other',other_org,'web','https://other.invalid','https://other.invalid/google-auth',true,true);
  PERFORM set_config('request.jwt.claim.sub', actor::text, true);
  PERFORM public.update_organization_admin(org,NULL,'{"IS_GOOGLE_LOGIN_ENABLED":true,"IS_REGISTRATION_ENABLED":false}',NULL);
  IF (SELECT count(*) FROM public.external_login_clients WHERE organization=org AND enabled) <> 2
     OR (SELECT enabled FROM public.external_login_clients WHERE client_id='org-setting-native')
     OR (SELECT (data->>'IS_REGISTRATION_ENABLED')::boolean FROM public.organizations WHERE id=org) THEN
    RAISE EXCEPTION 'Google switch must enable only provisioned clients and preserve registration policy';
  END IF;
  BEGIN
    PERFORM public.update_organization_admin(org,NULL,'{"IS_GOOGLE_LOGIN_ENABLED":"true"}',NULL);
  EXCEPTION WHEN invalid_parameter_value THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Non-boolean Google setting accepted'; END IF;
  denied := false;
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  BEGIN
    PERFORM public.update_organization_admin(org,NULL,'{"IS_GOOGLE_LOGIN_ENABLED":false}',NULL);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%Access Denied%' THEN RAISE; END IF;
    denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Non-admin changed Google setting'; END IF;
  PERFORM set_config('request.jwt.claim.sub', actor::text, true);
  PERFORM public.update_organization_admin(org,NULL,'{"IS_GOOGLE_LOGIN_ENABLED":false}',NULL);
  IF EXISTS(SELECT 1 FROM public.external_login_clients WHERE organization=org AND enabled)
     OR NOT (SELECT enabled FROM public.external_login_clients WHERE client_id='org-setting-other')
     OR (SELECT (data->>'IS_GOOGLE_LOGIN_ENABLED')::boolean FROM public.organizations WHERE id=org) THEN
    RAISE EXCEPTION 'Google disable failed or affected another organization';
  END IF;
END $$;
