-- test-setup: database/tests/helpers/prepared_notification_view.sql
-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/prepared_projection.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; viewer uuid:=gen_random_uuid(); first_member uuid:=gen_random_uuid();
 last_member uuid:=gen_random_uuid(); result jsonb; item jsonb; snapshot bigint; anchor timestamptz;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Current notification participants','{"IS_APP_SUPPORTED":true}') RETURNING id INTO org;
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
 result:=pg_temp.prepared_notification_view(org,oc);
 item:=result->'items'->0;
 PERFORM assert_eq((item#>>'{data,eventCount}')::int,2,'both current participants contribute to the group');
 PERFORM assert_true((pg_temp.prepared_notification_badge(org)->>'unread')::boolean,'current joins create a badge');
 snapshot:=(result->>'snapshot')::bigint; anchor:=(result->>'snapshotAt')::timestamptz;
 -- Ticketing-only applications must show neither participant rows nor their badge.
 UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":false}' WHERE id=org;
 PERFORM public.notification_center_prepared_invalidate(id) FROM public.notification_center_events WHERE organization=org;
 result:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(result->'items'),0,'unsupported app hides unread participant groups');
 PERFORM assert_false((pg_temp.prepared_notification_badge(org)->>'unread')::boolean,'unsupported participant groups create no badge');
 PERFORM assert_true((SELECT public.notification_center_in_center_internal(e,clock_timestamp())
  FROM jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object(
   'organization',org,'occasion',oc,'kind','order_created','occurred_at',clock_timestamp(),'data','{}'::jsonb)) e),
  'order notifications remain eligible without app support');
 UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":true}' WHERE id=org;
 PERFORM public.notification_center_prepared_invalidate(id) FROM public.notification_center_events WHERE organization=org;
 result:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq((result#>>'{items,0,data,eventCount}')::int,2,'app-supported participant groups remain available');
 -- The latest participant leaves: a frozen panel must remove their name and count.
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=last_member;
 PERFORM public.notification_center_prepared_invalidate(id) FROM public.notification_center_events WHERE organization=org;
 result:=pg_temp.prepared_notification_view(org,oc);
 item:=result->'items'->0;
 PERFORM assert_eq((item#>>'{data,eventCount}')::int,1,'removed participant is excluded from the frozen group count');
 PERFORM assert_eq(item#>>'{data,customerName}','Removed participant','preview switches to the remaining member');
 -- Previously read history must follow the same live membership rule.
 UPDATE public.notification_center_user_state SET read_through_sequence=snapshot
 WHERE organization=org AND recipient=viewer;
 UPDATE public.notification_center_projection_scopes SET phase='clear_members' WHERE organization=org AND recipient=viewer;
 result:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_true((result->'items'->0->>'isRead')::boolean,'remaining membership is read history');
 UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":false}' WHERE id=org;
 PERFORM public.notification_center_prepared_invalidate(id) FROM public.notification_center_events WHERE organization=org;
 result:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(result->'items'),0,'unsupported app also hides read participant history');
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=first_member;
 PERFORM public.notification_center_prepared_invalidate(id) FROM public.notification_center_events WHERE organization=org;
 result:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(result->'items'),0,'empty participant group disappears from read history');
 UPDATE public.notification_center_user_state SET read_through_sequence=0,seen_through_sequence=0
 WHERE organization=org AND recipient=viewer;
 PERFORM assert_false((pg_temp.prepared_notification_badge(org)->>'unread')::boolean,'removed participants leave no phantom badge');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),2::bigint,'filtering preserves historical event records');
END $$;
ROLLBACK;
