DO $$
DECLARE actor uuid; org bigint; n bigint; result jsonb;
BEGIN
 PERFORM create_user_for_test('abuse-unit','abuse-unit@example.invalid'); actor:=get_user_id('abuse-unit');
 INSERT INTO public.organizations(title,data) VALUES('Unit admission fixture','{"IS_UNIT_CREATION_ENABLED":true}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='unit.create.actor.day';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.create_unit_and_assign_manager('First admitted Unit');
 PERFORM assert_eq((result->>'code')::int,200,'legitimate manager onboarding remains available');
 result:=public.create_unit_and_assign_manager('Different title does not reset budget');
 PERFORM assert_eq((result->>'code')::int,429,'manual repeat receives the documented limited result');
 BEGIN
  PERFORM public.initialize_registration_unit_v1(actor,org,'abuse-unit@example.invalid','Direct bypass');
  RAISE EXCEPTION 'internal registration initializer is public';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.seed_org_with_admin('forbidden@example.invalid','FixturePassword123!');
  RAISE EXCEPTION 'organization bootstrap is public';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 BEGIN
  PERFORM public.initialize_registration_unit_v1(actor,org,'abuse-unit@example.invalid','Automatic alternate path');
  RAISE EXCEPTION 'automatic initializer reset manual Unit usage';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM public.units WHERE organization=org),1::bigint,'both paths share actor quota without partial Unit');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='unit.create.actor.day' AND scope_id=actor::text),1::numeric,'failed alternate creation preserves existing usage');
 UPDATE public.abuse_policy_rules SET base_limit=(SELECT coalesce(sum(amount),0)+1 FROM public.abuse_budget_usage WHERE rule_key='organization.create.global.day' AND scope_id='all') WHERE rule_key='organization.create.global.day';
 SELECT count(*) INTO n FROM public.organizations;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 EXECUTE 'SET LOCAL ROLE service_role';
 PERFORM public.seed_org_with_admin('seed-abuse@example.invalid','FixturePassword123!');
 BEGIN
  PERFORM public.seed_org_with_admin('seed-second@example.invalid','FixturePassword123!');
  RAISE EXCEPTION 'new organization reset global onboarding budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.user_info ui JOIN public.unit_users uu ON uu."user"=ui.id JOIN public.units u ON u.id=uu.unit WHERE ui.email_readonly='seed-abuse@example.invalid' AND uu.is_manager AND u.organization=ui.organization),'authorized bootstrap retains organization, Unit and manager');
 PERFORM assert_eq((SELECT count(*) FROM public.organizations),n+1,'global refusal creates no partial organization');
END $$;
