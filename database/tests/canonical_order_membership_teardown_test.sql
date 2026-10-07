-- The runner rolls this fixture back. Both published order entrypoints survive contraction.
DROP FUNCTION IF EXISTS public.delete_occasion_user_ws(uuid,bigint);
DO $$
DECLARE actor uuid; member uuid; remaining uuid; org bigint; u bigint; oc bigint;
 ord bigint; ticket bigint; group_id bigint; activity uuid; command uuid; response jsonb;
 case_id int; gv bigint; av bigint; head bigint;
BEGIN
 PERFORM create_user_for_test('order_teardown_manager','order-teardown-manager@test.local');
 PERFORM create_user_for_test('order_teardown_member','order-teardown-member@test.local');
 PERFORM create_user_for_test('order_teardown_remaining','order-teardown-remaining@test.local');
 actor:=get_user_id('order_teardown_manager');member:=get_user_id('order_teardown_member');remaining:=get_user_id('order_teardown_remaining');
 INSERT INTO public.organizations(title) VALUES('Order teardown fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Order teardown',org) RETURNING id INTO u;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(u,actor,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Order teardown',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_approved) VALUES(oc,actor,true,true,true,true),(oc,remaining,false,false,false,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 FOR case_id IN 1..2 LOOP
  INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{}',100,'CZK') RETURNING id INTO ord;
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(oc,'ordered',gen_random_uuid()::text) RETURNING id INTO ticket;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(ord,ticket);
  INSERT INTO public.occasion_users(occasion,"user",ticket,is_approved) VALUES(oc,member,ticket,true);
  INSERT INTO public.user_group_info(occasion,title) VALUES(oc,'Ticket group '||case_id) RETURNING id INTO group_id;
  INSERT INTO public.user_groups("group","user",is_admin) VALUES(group_id,member,false),(group_id,remaining,false);
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('user_group','occasion',oc,group_id::text,4);
  activity:=gen_random_uuid();
  INSERT INTO public.activities(id,occasion,title,is_hidden,"order") VALUES(activity,oc,'Ticket task',false,0);
  INSERT INTO public.activity_assignments(id,activity_id,"user",start_time,end_time) VALUES(gen_random_uuid(),activity,member,now(),now()+interval '1 hour'),(gen_random_uuid(),activity,remaining,now(),now()+interval '1 hour');
  PERFORM public.lock_activity_aggregate_internal_v1(oc);
  SELECT version INTO av FROM public.client_aggregate_versions WHERE aggregate_type='activities' AND scope_id=oc;
  SELECT COALESCE(max(source_revision),0) INTO head FROM public.client_sync_private_scopes WHERE occasion=oc AND user_id=remaining AND component='private_activity';
  UPDATE public.unit_users SET is_manager=false WHERE unit=u AND "user"=actor;
  BEGIN
   PERFORM public.delete_order_221(ord);
   RAISE EXCEPTION 'unauthorized deletion succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=oc AND "user"=member),'denied teardown retains member');
  UPDATE public.unit_users SET is_manager=true WHERE unit=u AND "user"=actor;
  BEGIN
   PERFORM public.delete_order_221(ord);
   RAISE EXCEPTION 'rollback-teardown-fixture';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'rollback-teardown-fixture' THEN RAISE; END IF; END;
  PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders WHERE id=ord),'teardown rollback retains order');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=group_id AND "user"=member),'teardown rollback retains group membership');
  command:=gen_random_uuid();
  IF case_id=1 THEN response:=public.delete_order_client_sync_v1(ord,command);
  ELSE PERFORM public.delete_order_221(ord); END IF;
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=ord),'order deleted after legacy RPC removal');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=oc AND "user"=member),'ticket membership removed');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.activity_assignments WHERE activity_id=activity AND "user"=member),'removed assignments deleted');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.activity_assignments WHERE activity_id=activity AND "user"=remaining),'other assignment retained');
  PERFORM assert_eq((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_id=oc AND aggregate_id=group_id::text),5::bigint,'group clock advances');
  PERFORM assert_eq((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='activities' AND scope_id=oc),av+1,'activity clock advances');
  PERFORM assert_eq((SELECT source_revision FROM public.client_sync_private_scopes WHERE occasion=oc AND user_id=remaining AND component='private_activity'),head+1,'remaining activity projection invalidated once');
 END LOOP;
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.delete_order_internal_v1(bigint)','EXECUTE'),'order domain helper remains private');
END $$;
