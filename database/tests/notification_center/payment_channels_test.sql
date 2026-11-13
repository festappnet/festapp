-- test-setup: database/tests/helpers/prepared_notification_view.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; viewer uuid:=gen_random_uuid(); payment uuid; v jsonb; dispatch uuid; email_count bigint;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Platby pořadatele','{"DEFAULT_URL":"https://ples.example.test"}') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(viewer,org,'poradatel@example.test');
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Společenský ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day');
 UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000;
 PERFORM public.activate_notification_center_emails(org);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 PERFORM assert_true((public.notification_center_email_settings_internal(org)->>'stopped')::boolean,'optional email defaults to off without a profile');
 PERFORM public.notification_center_email_ensure_profile_internal(viewer);
 PERFORM assert_true((public.notification_center_email_settings_internal(org)->>'stopped')::boolean,'implicit profile creation keeps optional email off');
 payment:=public.notification_center_publish_internal(org,oc,'order_payment_received','payment:default','{"amount":500,"currency":"CZK"}');
 PERFORM public.project_notification_center(500);
 v:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(v->'items'),0,'received payment does not appear in the app');
 PERFORM assert_false((public.get_notification_center_prepared_badge(org)->>'unread')::boolean,'received payment alone does not light the bell');
 PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=viewer),0::bigint,'default-off email cannot collect received payments');

 PERFORM public.notification_center_publish_internal(org,oc,'order_created','order:new','{"count":1,"formContext":{"allowsMultiple":false}}');
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','order:cancelled','{"count":1,"formContext":{"allowsMultiple":false}}');
 PERFORM public.project_notification_center(500);
 v:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(v->'items'),2,'new orders and cancellations remain visible');
 PERFORM assert_true((public.get_notification_center_prepared_badge(org)->>'unread')::boolean,'order activity still lights the bell');

 PERFORM public.save_notification_center_email_settings(org,0,false,'cs','{"order_payment_received":true}');
 payment:=public.notification_center_publish_internal(org,oc,'order_payment_received','payment:opted-in','{"amount":600,"currency":"CZK"}');
 PERFORM public.project_notification_center(500);
 PERFORM public.collect_notification_center_emails(100);
 SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=viewer AND state='collecting';
 PERFORM assert_true(dispatch IS NOT NULL,'explicit payment email opt-in still collects payment activity');
 v:=public.notification_center_email_context_internal(dispatch,viewer);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') x WHERE x->>'kind'='order_payment_received'),'received payment remains in the authorized email payload');
 v:=pg_temp.prepared_notification_view(org,oc);
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') x WHERE x->>'kind'='order_payment_received'),'email opt-in does not enable payment notices in the app');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=payment),'payment facts remain retained');
 SELECT count(*) INTO email_count FROM public.notification_center_email_items WHERE recipient=viewer;
 PERFORM public.save_notification_center_email_settings(org,1,true,'cs','{"order_payment_received":true}');
 PERFORM public.notification_center_publish_internal(org,oc,'order_payment_received','payment:stopped','{"amount":700,"currency":"CZK"}');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_items WHERE recipient=viewer),email_count,'stopping email retains the opt-out for later payments');
END $$;
ROLLBACK;
