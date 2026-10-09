DO $$
DECLARE org bigint;other_org bigint;usr uuid;google_usr uuid;old_usr uuid;other_usr uuid;mfa_usr uuid;token text:=repeat('test-capability-',3);v integer;
BEGIN
  PERFORM set_config('festapp.email_wake','scheduled',true);
  INSERT INTO public.organizations(title,data) VALUES('First login fixture','{"APP_NAME":"Fixture"}') RETURNING id INTO org;
  INSERT INTO public.organizations(title) VALUES('Other tenant fixture') RETURNING id INTO other_org;
  usr:=public.create_user_in_organization_with_data_pure(org,'new@example.invalid','fixture-password','{"name":"New"}');
  google_usr:=public.create_user_in_organization_with_data_pure(org,'google@example.invalid','fixture-password','{"name":"Google"}');
  old_usr:=public.create_user_in_organization_with_data_pure(org,'old@example.invalid','fixture-password','{}');
  other_usr:=public.create_user_in_organization_with_data_pure(other_org,'other@example.invalid','fixture-password','{}');
  mfa_usr:=public.create_user_in_organization_with_data_pure(org,'mfa@example.invalid','fixture-password','{}');
  INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at,secret) VALUES(gen_random_uuid(),mfa_usr,'totp','verified',now(),now(),'fixture');
  UPDATE auth.users SET last_sign_in_at=now()-interval '1 day' WHERE id=old_usr;
  PERFORM public.configure_first_login_notifications_v1(org,'owner@example.invalid',true);
  IF public.enqueue_first_login_notifications_v1()<>0 THEN RAISE EXCEPTION 'unconfirmed account notified'; END IF;
  UPDATE auth.users SET last_sign_in_at=now() WHERE id IN (usr,google_usr,other_usr,old_usr,mfa_usr);
  IF public.enqueue_first_login_notifications_v1()<>0 THEN RAISE EXCEPTION 'sessionless account notified'; END IF;
  INSERT INTO auth.sessions(id,user_id,created_at,updated_at,aal) SELECT gen_random_uuid(),id,now(),now(),'aal1' FROM auth.users WHERE id IN (usr,google_usr,other_usr,old_usr,mfa_usr);
  v:=public.enqueue_first_login_notifications_v1();
  IF v<>2 THEN RAISE EXCEPTION 'expected password and Google first logins, got %',v; END IF;
  IF EXISTS(SELECT 1 FROM public.first_login_notifications WHERE user_id=mfa_usr) THEN RAISE EXCEPTION 'unfinished MFA notified'; END IF;
  UPDATE auth.sessions SET aal='aal2' WHERE user_id=mfa_usr;
  IF public.enqueue_first_login_notifications_v1()<>1 THEN RAISE EXCEPTION 'completed MFA not notified'; END IF;
  IF public.enqueue_first_login_notifications_v1()<>0 THEN RAISE EXCEPTION 'repeated login duplicated'; END IF;
  IF (SELECT count(*) FROM public.email_messages WHERE organization=org AND code='NEW_USER_FIRST_LOGIN' AND recipient='owner@example.invalid' AND tracking_policy='disabled')<>3 THEN RAISE EXCEPTION 'owner mail contract failed'; END IF;
  IF EXISTS(SELECT 1 FROM public.email_messages WHERE organization=other_org AND code='NEW_USER_FIRST_LOGIN') THEN RAISE EXCEPTION 'other tenant notified'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.first_login_notifications WHERE user_id=old_usr AND baseline) THEN RAISE EXCEPTION 'historical login not baselined'; END IF;
  INSERT INTO public.festapp_monitoring_credentials(token_hash,expires_at) VALUES(encode(extensions.digest(token,'sha256'),'hex'),now()+interval '1 day');
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  BEGIN
    PERFORM public.configure_first_login_notifications_v1(org,'attacker@example.invalid',true);
    RAISE EXCEPTION 'anon configured recipient';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.get_festapp_monitoring_health_v1(repeat('wrong',9));
    RAISE EXCEPTION 'invalid health capability accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.get_festapp_monitoring_health_v1(token);
  IF has_table_privilege('anon','public.first_login_notifications','SELECT') OR has_table_privilege('anon','public.festapp_monitoring_credentials','SELECT') THEN RAISE EXCEPTION 'private tables exposed'; END IF;
  PERFORM set_config('request.jwt.claims','',true);
END $$;

SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM public.configure_first_login_notifications_v1(1,'attacker@example.invalid',true);
    RAISE EXCEPTION 'anon has configuration permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.get_festapp_monitoring_health_v1(repeat('wrong',9));
    RAISE EXCEPTION 'invalid public capability accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.get_festapp_monitoring_health_v1(repeat('test-capability-',3));
END $$;
RESET ROLE;
