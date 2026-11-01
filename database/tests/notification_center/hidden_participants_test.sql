-- test-setup: database/functions/notification_center/core.sql
-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/daily_overview.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; viewer uuid:=gen_random_uuid(); member uuid:=gen_random_uuid();
 hidden_member uuid:=gen_random_uuid(); result jsonb; legacy public.notification_center_events; snapshot bigint; anchor timestamptz;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Hidden notification participants') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer),(member),(hidden_member);
 INSERT INTO public.user_info(id,organization,name) VALUES(viewer,org,'Editor'),(member,org,'Visible participant'),(hidden_member,org,'Hidden admin');
 INSERT INTO public.organization_users(organization,"user",is_hidden,is_admin) VALUES(org,hidden_member,true,true);
 INSERT INTO public.occasions(organization,title,link,is_open,start_time,end_time)
 VALUES(org,'Hidden participants',gen_random_uuid()::text,true,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor) VALUES(oc,viewer,true),(oc,member,false);
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM set_config('request.jwt.claim.sub',hidden_member::text,true);
 PERFORM public.add_user_to_occasion_internal_v1(oc,hidden_member);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),0::bigint,'hidden admin enrollment produces no notification');
 PERFORM public.notification_center_publish_internal(org,oc,'occasion_joined','visible:join',jsonb_build_object('userId',member));
 -- Simulate an already delivered historical notification from before the fix.
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,occurred_at,data)
 VALUES(org,oc,'occasion_joined','hidden:legacy',now(),jsonb_build_object('userId',hidden_member)) RETURNING * INTO legacy;
 UPDATE public.organization_users SET is_hidden=false WHERE organization=org AND "user"=hidden_member;
 PERFORM public.notification_center_capture_recipients_internal(legacy.id,NULL);
 PERFORM public.project_notification_center(500);
 UPDATE public.organization_users SET is_hidden=true WHERE organization=org AND "user"=hidden_member;
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_deliveries WHERE event_id=legacy.id AND recipient=viewer),'fixture has a previously delivered hidden notification');
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 PERFORM assert_false(public.notification_center_allowed(legacy,viewer),'hidden historical identity is denied at item authorization');
 result:=public.get_notification_center_daily_overview(org,oc);
 PERFORM assert_eq((result#>>'{items,0,data,eventCount}')::int,1,'hidden history contributes neither name nor count');
 PERFORM assert_eq(result#>>'{items,0,data,customerName}','Visible participant','only visible participant name is rendered');
 snapshot:=(result->>'snapshot')::bigint; anchor:=(result->>'snapshotAt')::timestamptz;
 INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,member,true);
 result:=public.get_notification_center_daily_overview(org,oc,snapshot,anchor);
 PERFORM assert_eq(jsonb_array_length(result->'items'),0,'newly hidden participant disappears from frozen panel');
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'hidden participants leave no unread badge');
END $$;
ROLLBACK;
