DO $$
DECLARE actor uuid; recipient uuid; outsider uuid; org bigint; other_org bigint; un bigint;
 command_id uuid:=gen_random_uuid(); result jsonb; commit_count bigint;
BEGIN
 PERFORM public.create_user_for_test('unit-membership-manager','unit-manager@example.invalid');
 actor:=public.get_user_id('unit-membership-manager');
 INSERT INTO public.organizations(title) VALUES('Membership contracts') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other membership contracts') RETURNING id INTO other_org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 recipient:=public.create_user_in_organization_with_data_pure(org,'member@example.invalid','test-password','{}');
 outsider:=public.create_user_in_organization_with_data_pure(other_org,'other@example.invalid','test-password','{}');
 INSERT INTO public.units(title,organization) VALUES('Membership contracts',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 result:=public.add_user_to_unit_client_sync_v1(un,recipient,command_id);
 ASSERT result->>'status'='applied','new membership must apply';
 ASSERT public.add_user_to_unit_client_sync_v1(un,recipient,command_id)=result,'retry must replay immutable receipt';
 ASSERT public.add_user_to_unit_client_sync_v1(un,recipient,gen_random_uuid())#>>'{data,reasonCode}'='already_member','existing member must return typed unchanged result';
 ASSERT public.add_user_to_unit(un,recipient)->>'code'='200','old adapter must work';
 BEGIN
  PERFORM public.add_user_to_unit_client_sync_v1(un,outsider,command_id);
  RAISE EXCEPTION 'payload conflict accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 BEGIN
  PERFORM public.add_user_to_unit_client_sync_v1(un,outsider,gen_random_uuid());
  RAISE EXCEPTION 'cross tenant identity accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RESET ROLE;
 ASSERT NOT EXISTS(SELECT 1 FROM public.unit_users WHERE unit=un AND "user"=recipient
   AND (is_editor OR is_editor_view OR is_manager)),'adding membership must not grant roles';
 SELECT count(*) INTO commit_count FROM public.client_commits WHERE unit=un;
 ASSERT commit_count=1,'retry/already member must not make another commit';
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_messages WHERE organization=org),'membership must not send';
 UPDATE public.unit_users SET is_manager=false WHERE unit=un AND "user"=actor;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.add_user_to_unit_client_sync_v1(un,recipient,command_id);
  RAISE EXCEPTION 'unauthorized replay accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 BEGIN
  PERFORM public.add_user_to_unit(un,recipient);
  RAISE EXCEPTION 'bare service role bypass accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RESET ROLE;
 ASSERT NOT has_function_privilege('authenticated','public.ensure_unit_membership_internal_v1(bigint,uuid)','EXECUTE'),'primitive must stay private';
END $$;
