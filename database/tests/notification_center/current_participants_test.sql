-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/daily_overview.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; viewer uuid:=gen_random_uuid(); first_member uuid:=gen_random_uuid();
 last_member uuid:=gen_random_uuid(); result jsonb; item jsonb; snapshot bigint; anchor timestamptz;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Current notification participants') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer),(first_member),(last_member);
 INSERT INTO public.user_info(id,organization,name)
 VALUES(viewer,org,'Editor'),(first_member,org,'Removed participant'),(last_member,org,'Remaining participant');
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Participants',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor)
 VALUES(oc,viewer,true),(oc,first_member,false),(oc,last_member,false);
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM public.notification_center_publish_internal(org,oc,'occasion_joined','members:first',
  jsonb_build_object('userId',first_member),NULL,clock_timestamp());
 PERFORM public.notification_center_publish_internal(org,oc,'occasion_joined','members:last',
  jsonb_build_object('userId',last_member),NULL,clock_timestamp());
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.get_notification_center_daily_overview(org,oc);
 item:=result->'items'->0;
 PERFORM assert_eq((item#>>'{data,eventCount}')::int,2,'both current participants contribute to the group');
 PERFORM assert_true((public.get_notification_center_badge(org)->>'unread')::boolean,'current joins create a badge');
 snapshot:=(result->>'snapshot')::bigint; anchor:=(result->>'snapshotAt')::timestamptz;
 -- The latest participant leaves: a frozen panel must remove their name and count.
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=last_member;
 result:=public.get_notification_center_daily_overview(org,oc,snapshot,anchor);
 item:=result->'items'->0;
 PERFORM assert_eq((item#>>'{data,eventCount}')::int,1,'removed participant is excluded from the frozen group count');
 PERFORM assert_eq(item#>>'{data,customerName}','Removed participant','preview switches to the remaining member');
 -- Previously read history must follow the same live membership rule.
 UPDATE public.notification_center_user_state SET read_through_sequence=snapshot
 WHERE organization=org AND recipient=viewer;
 result:=public.get_notification_center_daily_overview(org,oc,snapshot,anchor);
 PERFORM assert_true((result->'items'->0->>'isRead')::boolean,'remaining membership is read history');
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=first_member;
 result:=public.get_notification_center_daily_overview(org,oc,snapshot,anchor);
 PERFORM assert_eq(jsonb_array_length(result->'items'),0,'empty participant group disappears from read history');
 UPDATE public.notification_center_user_state SET read_through_sequence=0,seen_through_sequence=0
 WHERE organization=org AND recipient=viewer;
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'removed participants leave no phantom badge');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),2::bigint,'filtering preserves historical event records');
END $$;
ROLLBACK;
