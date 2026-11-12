CREATE OR REPLACE FUNCTION pg_temp.admin_email_fixture()
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; other_org bigint; oc bigint; user_id uuid:=gen_random_uuid(); dispatch uuid; message uuid;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Souhrny A','{"DEFAULT_URL":"https://a.example.test"}') RETURNING id INTO org;
 INSERT INTO public.organizations(title,data) VALUES('Souhrny B','{"DEFAULT_URL":"https://b.example.test"}') RETURNING id INTO other_org;
 INSERT INTO auth.users(id) VALUES(user_id);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(user_id,org,user_id||'@example.test');
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day'),(other_org,now()-interval '1 day');
 UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000;
 PERFORM public.activate_notification_center_emails(org);PERFORM public.activate_notification_center_emails(other_org);
 PERFORM set_config('request.jwt.claim.sub',user_id::text,true);
 FOR i IN 1..2 LOOP
  INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(CASE WHEN i=1 THEN org ELSE other_org END,'Ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,user_id,true);
  PERFORM public.save_notification_center_email_settings(CASE WHEN i=1 THEN org ELSE other_org END,NULL,i-1,false,'cs','{"order_created":true}');
  PERFORM public.notification_center_publish_internal(CASE WHEN i=1 THEN org ELSE other_org END,oc,'order_created','test:'||i,'{"count":3,"formContext":{"allowsMultiple":true}}');
 END LOOP;
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 SELECT id INTO dispatch FROM public.notification_center_email_dispatches WHERE recipient=user_id AND state='collecting';
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE id=dispatch;
 PERFORM public.enqueue_notification_center_emails(100);
 SELECT message_id INTO message FROM public.notification_center_email_dispatches WHERE id=dispatch;
 RETURN jsonb_build_object('user',user_id,'organization',org,'otherOrganization',other_org,'dispatch',dispatch,'message',message);
END $$;
