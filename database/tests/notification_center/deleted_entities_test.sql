-- test-setup: database/functions/notification_center/deleted_entities.sql
-- test-setup: database/functions/groups/remove_occasion_user_domain.sql
-- test-setup: database/functions/eshop_orders/delete_order.sql
BEGIN;
DO $$
DECLARE org bigint; other_org bigint; unit_id bigint; oc bigint; other_oc bigint;
 actor uuid; member uuid:=gen_random_uuid(); remaining uuid:=gen_random_uuid();
 ord bigint; other_ord bigint; message uuid; other_message uuid; v_kind text; result jsonb; removed integer;
BEGIN
 PERFORM create_user_for_test('notification-delete-owner','notification-delete-owner@example.invalid');
 actor:=get_user_id('notification-delete-owner');
 INSERT INTO public.organizations(title) VALUES('Notification deletion') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Untouched notification tenant') RETURNING id INTO other_org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO auth.users(id) VALUES(member),(remaining);
 INSERT INTO public.user_info(id,organization) VALUES(member,org),(remaining,org);
 INSERT INTO public.units(title,organization) VALUES('Deletion unit',org) RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit_id,actor,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Deletion occasion',org,unit_id,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Other occasion',org,unit_id,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order_view,is_manager)
 VALUES(oc,actor,true,true,true),(other_oc,actor,true,true,true),(oc,member,false,false,false),(other_oc,member,false,false,false),(oc,remaining,false,false,false);
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM public.notification_center_publish_internal(org,oc,'occasion_joined','delete:member',jsonb_build_object('userId',member));
 PERFORM public.notification_center_publish_internal(org,other_oc,'occasion_joined','delete:other-occasion',jsonb_build_object('userId',member));
 PERFORM public.notification_center_publish_internal(org,oc,'occasion_joined','delete:remaining-member',jsonb_build_object('userId',remaining));
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered',public.generate_order_symbol(),public.next_order_sequence(oc),'{}') RETURNING id INTO ord;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'storno',public.generate_order_symbol(),public.next_order_sequence(oc),'{}') RETURNING id INTO other_ord;
 FOREACH v_kind IN ARRAY ARRAY['order_created','order_cancelled','waitlist_registered','offer_accepted'] LOOP
  PERFORM public.notification_center_publish_internal(org,oc,v_kind,'delete:'||v_kind,jsonb_build_object('orderId',ord,'count',1));
  PERFORM public.notification_center_publish_internal(org,oc,v_kind,'keep:'||v_kind,jsonb_build_object('orderId',other_ord,'count',1));
 END LOOP;
 message:=(public.enqueue_email('order_reminder',jsonb_build_object('organization',org,'unit',unit_id,'occasion',oc),
  'deleted-notification@example.invalid','{}','notification-delete',p_order:=ord)->>'message_id')::uuid;
 other_message:=(public.enqueue_email('order_reminder',jsonb_build_object('organization',org,'unit',unit_id,'occasion',oc),
  'remaining-notification@example.invalid','{}','notification-keep',p_order:=other_ord)->>'message_id')::uuid;
 PERFORM public.notification_center_publish_internal(org,oc,'email_problem','email:'||message,jsonb_build_object('messageId',message));
 PERFORM public.notification_center_publish_internal(org,oc,'email_problem','email:'||other_message,jsonb_build_object('messageId',other_message));
 INSERT INTO public.notification_center_source_state(organization,source_key,state) VALUES(org,'email:'||message,'{}') ON CONFLICT DO NOTHING;
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 result:=public.delete_occasion_user_client_sync_v1(oc,member,gen_random_uuid(),0);
 PERFORM assert_eq((result->>'code')::int,200,'real participant deletion succeeds');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND occasion=oc AND kind='occasion_joined' AND data->>'userId'=member::text),'deleted application has no notification');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='occasion_joined'),2::bigint,'another member and same member in other occasion remain');
 result:=public.get_notification_center_daily_overview(org,oc,p_timezone=>'Europe/Prague');
 PERFORM assert_eq((SELECT (i#>>'{data,eventCount}')::int FROM jsonb_array_elements(result->'items') i
  WHERE i->>'kind'='occasion_joined' AND (i->>'occasionId')::bigint=oc),1,'rendered participant group recounts after deletion');
 result:=public.delete_order_client_sync_v1(ord,gen_random_uuid());
 PERFORM assert_eq((result->>'code')::int,200,'real order deletion succeeds');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND (data->>'orderId'=ord::text OR data->>'messageId'=message::text)),'all deleted order activity and email notifications disappear');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_source_state WHERE organization=org AND source_key='email:'||message),'deleted email observation is removed');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND data->>'orderId'=other_ord::text),4::bigint,'a cancelled but existing order retains its own history');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND data->>'messageId'=other_message::text),'other order email notification remains');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_deliveries d LEFT JOIN public.notification_center_events e ON e.id=d.event_id WHERE e.id IS NULL),'deliveries cascade with deleted notifications');
 -- Historical orphan repair stays explicitly tenant-scoped and idempotent.
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,occurred_at,data)
 VALUES(org,oc,'occasion_joined','orphan:member',now(),jsonb_build_object('userId',member)),
 (org,oc,'order_created','orphan:order',now(),jsonb_build_object('orderId',ord)),
 (org,oc,'email_problem','orphan:email',now(),jsonb_build_object('messageId',message)),
 (other_org,NULL,'order_created','orphan:other-tenant',now(),jsonb_build_object('orderId',ord));
 removed:=public.notification_center_purge_deleted_internal(org);
 PERFORM assert_eq(removed,3,'backfill removes only the three orphan entity notifications');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=other_org AND source_key='orphan:other-tenant'),'backfill preserves another tenant');
 PERFORM assert_eq(public.notification_center_purge_deleted_internal(org),0,'backfill can be repeated safely');
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_purge_deleted_internal(bigint)','EXECUTE'),'user cannot invoke historical cleanup');
 PERFORM assert_false(has_function_privilege('anon','public.notification_center_purge_deleted_internal(bigint)','EXECUTE'),'anonymous cannot invoke historical cleanup');
END $$;
ROLLBACK;
