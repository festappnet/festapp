-- Organizer reproduction matrix. No invitations or outbound delivery requested.
DO $$
DECLARE actor uuid; recipient uuid; org bigint; unit_id bigint; occasion_id bigint;
 result jsonb; command_id uuid:=gen_random_uuid(); changes jsonb;
BEGIN
 PERFORM public.create_user_for_test('access-manager','access-manager@example.invalid');
 actor:=public.get_user_id('access-manager');
 INSERT INTO public.organizations(title) VALUES('Access contracts') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Access contracts',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit_id,actor,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Access contracts',org,unit_id,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occasion_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES(occasion_id,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 changes:=jsonb_build_object('kind','editor','is_editor',false,'is_editor_view',false,'is_manager',false,
  'data',jsonb_build_object('email','access-person@example.invalid','name','Jana'));
 SET LOCAL ROLE authenticated;
 result:=public.save_unit_user_client_sync_v1(unit_id,NULL,command_id,NULL,changes);
 ASSERT result->>'code'='200',format('unit creation rejected: %s',result);
 ASSERT public.save_unit_user_client_sync_v1(unit_id,NULL,command_id,NULL,changes)=result,'retry must replay';
 recipient:=(result#>>'{data,userId}')::uuid;
 result:=public.save_unit_user_client_sync_v1(unit_id,recipient,gen_random_uuid(),1,
  '{"kind":"roles","is_editor":true}');
 ASSERT result->>'code'='200',format('unit role edit rejected: %s',result);
 result:=public.delete_unit_user_client_sync_v1(recipient,unit_id,gen_random_uuid());
 ASSERT result->>'code'='200','unit removal rejected';
 result:=public.save_unit_user_client_sync_v1(unit_id,NULL,gen_random_uuid(),NULL,
  jsonb_set(changes,'{data,email}','"  ACCESS-PERSON@example.invalid  "'));
 ASSERT result->>'code'='200','existing identity re-add rejected';
 ASSERT result#>>'{data,userId}'=recipient::text,'re-add must retain identity';
 result:=public.create_occasion_user_client_sync_v1(occasion_id,gen_random_uuid(),
  jsonb_build_object('occasion',occasion_id,'data',jsonb_build_object('email','access-person@example.invalid')));
 ASSERT result->>'code'='200',format('occasion add rejected: %s',result);
 RESET ROLE;
 ASSERT NOT EXISTS(SELECT 1 FROM public.email_messages WHERE organization=org),'save must not send implicitly';
 ASSERT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occasion_id AND "user"=recipient),'occasion membership missing';
 -- Canonical identity lookup must not depend on raw auth email casing/whitespace.
 SET LOCAL ROLE authenticated;
 result:=public.save_unit_user_client_sync_v1(unit_id,NULL,gen_random_uuid(),NULL,
  jsonb_set(changes,'{data,email}','"  ACCESS-PERSON@example.invalid  "'));
 RESET ROLE;
 ASSERT result->>'status'='unchanged' AND result#>>'{data,reasonCode}'='already_member',format('normalized existing member rejected: %s',result);
 ASSERT result#>>'{data,userId}'=recipient::text,'existing member must return its identity';
 ASSERT (SELECT count(*) FROM public.user_info WHERE organization=org AND lower(btrim(email_readonly))='access-person@example.invalid')=1,'identity duplicated';
END $$;
