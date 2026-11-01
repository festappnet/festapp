-- test-setup: database/functions/notification_center/purge_hidden_history.sql
BEGIN;
DO $$
DECLARE org bigint; other_org bigint; oc bigint; viewer uuid:=gen_random_uuid(); hidden_user uuid:=gen_random_uuid();
 hidden_event uuid; visible_event uuid; other_event uuid; batch uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Purge hidden notifications') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Untouched organization') RETURNING id INTO other_org;
 INSERT INTO auth.users(id) VALUES(viewer),(hidden_user);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org),(hidden_user,org);
 INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,hidden_user,true);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Purge',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user") VALUES(oc,hidden_user);
 -- Legacy persisted projections must be removed, not merely filtered.
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,data,occurred_at)
 VALUES(org,oc,'occasion_joined','purge:hidden',jsonb_build_object('userId',hidden_user),now()) RETURNING id INTO hidden_event;
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,data,actor,occurred_at)
 VALUES(org,oc,'form_opened','purge:operational','{}',hidden_user,now()) RETURNING id INTO visible_event;
 INSERT INTO public.notification_center_events(organization,kind,source_key,data,occurred_at)
 VALUES(other_org,'occasion_joined','purge:other-org',jsonb_build_object('userId',hidden_user),now()) RETURNING id INTO other_event;
 INSERT INTO public.notification_center_recipients(event_id,recipient) VALUES(hidden_event,viewer),(visible_event,viewer);
 INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
 VALUES(hidden_event,viewer,org,1,1,'hidden'),(visible_event,viewer,org,1,2,'visible');
 INSERT INTO public.notification_center_user_state(organization,recipient,last_delivery_sequence,read_through_sequence,seen_through_sequence) VALUES(org,viewer,2,1,1);
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 VALUES(org,viewer,'event:'||hidden_event,0,1),(org,viewer,'occasion-kind:'||oc||':occasion_joined',0,1);
 INSERT INTO public.notification_center_source_state(organization,source_key,state)
 VALUES(org,'purge:source',jsonb_build_object('eventId',hidden_event,'notificationId',hidden_event,'reason','bounce'));
 PERFORM assert_eq(public.purge_hidden_notification_history_internal(org),1::bigint,'one personal hidden event is physically deleted');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=hidden_event),'hidden event no longer exists');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_recipients WHERE event_id=hidden_event),'hidden recipient eligibility no longer exists');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=hidden_event),'hidden delivery no longer exists');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_read_batches WHERE group_key='event:'||hidden_event),'event-specific read receipt removed');
 PERFORM assert_eq((SELECT state FROM public.notification_center_source_state WHERE organization=org AND source_key='purge:source'),'{"reason":"bounce"}'::jsonb,'source retains only business facts');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=visible_event),'hidden operator business event survives');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=other_event),'another organization is untouched');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=oc AND "user"=hidden_user),'actual membership is preserved');
 PERFORM assert_eq((SELECT last_delivery_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer),2::bigint,'shared sequence watermark is preserved');
 PERFORM assert_eq(public.purge_hidden_notification_history_internal(org),0::bigint,'cleanup is idempotent');
END $$;
ROLLBACK;
