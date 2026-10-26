DO $$
DECLARE p record; u uuid; response jsonb; org bigint;
BEGIN
 FOR p IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace
 AND proname IN ('set_user_password','create_user','create_user_with_data','create_user_in_organization_with_data') LOOP
   RAISE EXCEPTION 'retired overload remains: %',p.signature;
 END LOOP;
 FOR p IN SELECT oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('create_user_from_registration','create_user_in_organization_with_data_ws','create_user_in_organization_with_data_pure') LOOP
   IF has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') THEN
     RAISE EXCEPTION 'internal Auth writer exposed';
   END IF;
 END LOOP;
 INSERT INTO public.organizations(title,data) VALUES('Disabled registration','{}') RETURNING id INTO org;
 response:=public.create_user_from_registration(org,'disabled@test.local','12345678','{}');
 PERFORM assert_eq((response->>'code')::int,403,'NULL policy denies registration');
 UPDATE public.organizations SET data='{"IS_REGISTRATION_ENABLED":false}' WHERE id=org;
 response:=public.create_user_from_registration(org,'disabled@test.local','12345678','{}');
 PERFORM assert_eq((response->>'code')::int,403,'false policy denies registration');
 response:=public.create_user_from_registration(-9223372036854775807,'missing@test.local','12345678','{}');
 PERFORM assert_eq((response->>'code')::int,403,'missing organization denies registration');
 UPDATE public.organizations SET data='{"IS_REGISTRATION_ENABLED":true}' WHERE id=org;
 response:=public.create_user_from_registration(org,'enabled@test.local','12345678','{"name":"Enabled"}');
 PERFORM assert_eq((response->>'code')::int,200,'enabled registration preserves internal owner');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.unit_users WHERE "user"=(response->>'id')::uuid),'registration initializes unit');
END $$;

DO $$
DECLARE manager uuid; org bigint; target_unit bigint; target_o bigint; response jsonb;
BEGIN
 PERFORM create_user_for_test('ds_manager','ds_manager@test.local'); manager:=get_user_id('ds_manager');
 INSERT INTO public.organizations(title,data) VALUES('Manager target','{"IS_REGISTRATION_ENABLED":false}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Manager target unit',org) RETURNING id INTO target_unit;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Manager target event',org,target_unit,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO target_o;
 INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES(target_o,manager,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 response:=public.create_occasion_user_client_sync_v1(p_occasion=>target_o,p_command_id=>gen_random_uuid(),p_profile=>jsonb_build_object('occasion',target_o,'data',jsonb_build_object('email','managed@test.local','name','Managed')));
 IF (response->>'code')::int NOT IN (200,201) THEN RAISE EXCEPTION 'scoped manager creation failed: %',response; END IF;
 RESET ROLE;
 -- A manager role does not override a disabled public registration policy.
 response:=public.create_user_from_registration(org,'not-public@test.local','12345678','{}');
 PERFORM assert_eq((response->>'code')::int,403,'manager cannot reopen public registration');
 SET LOCAL ROLE authenticated;
 response:=public.update_unit_user(jsonb_build_object('unit',target_unit,'data',jsonb_build_object('email','foreign@test.local')));
 IF response->>'code'<>'403' THEN RAISE EXCEPTION 'occasion manager acquired unit-wide creation'; END IF;
 BEGIN PERFORM public.create_user_in_organization_with_data_ws(org,'bypass@test.local','12345678','{}');
 RAISE EXCEPTION 'internal writer callable'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;
