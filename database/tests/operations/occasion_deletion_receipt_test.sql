DO $$
DECLARE actor uuid; other_actor uuid; org bigint; un bigint; oc bigint; cmd uuid:=gen_random_uuid(); result jsonb;
BEGIN
 PERFORM public.create_user_for_test('occasion-delete-receipt','occasion-delete-receipt@example.invalid');actor:=public.get_user_id('occasion-delete-receipt');
 PERFORM public.create_user_for_test('occasion-delete-other','occasion-delete-other@example.invalid');other_actor:=public.get_user_id('occasion-delete-other');
 INSERT INTO public.organizations(title) VALUES('Delete receipt') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id IN(actor,other_actor);
 INSERT INTO public.units(title,organization) VALUES('Delete receipt',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true),(un,other_actor,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,data) VALUES('Delete receipt',org,un,gen_random_uuid()::text,now(),now()+interval '1 day','{"client_sync_v1":false}') RETURNING id INTO oc;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.delete_occasion_client_sync_v1(oc,cmd);ASSERT result->>'status'='applied';
 ASSERT public.delete_occasion_client_sync_v1(oc,cmd)=result;
 BEGIN PERFORM public.delete_occasion_client_sync_v1(oc+1,cmd);RAISE EXCEPTION 'command rebound to different occasion';EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN NULL;END;
 EXECUTE 'RESET ROLE';
 ASSERT NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=oc);
 PERFORM set_config('request.jwt.claim.sub',other_actor::text,true);
 BEGIN PERFORM public.delete_occasion_client_sync_v1(oc,cmd);RAISE EXCEPTION 'receipt recovered by different actor';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 UPDATE public.unit_users SET is_manager=false WHERE unit=un AND "user"=actor;
 BEGIN PERFORM public.delete_occasion_client_sync_v1(oc,cmd);RAISE EXCEPTION 'receipt recovered after permission revocation';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE public.unit_users SET is_manager=true WHERE unit=un AND "user"=actor;
 UPDATE public.client_mutation_receipts SET status='expired',response=NULL,expired_at=clock_timestamp() WHERE command_id=cmd;
 ASSERT public.delete_occasion_client_sync_v1(oc,cmd)->>'code'='410';
 ASSERT NOT has_function_privilege('authenticated','public.shift_occasion_schedule_backward(bigint,integer)','EXECUTE');
 ASSERT NOT has_table_privilege('authenticated','public.occasions','UPDATE');
END $$;
