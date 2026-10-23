BEGIN;
DO $$
DECLARE org bigint; oc bigint; oc2 bigint; actor uuid:=gen_random_uuid(); late_user uuid:=gen_random_uuid();
 first_event uuid; old_event uuid; issue uuid; page jsonb; cursor jsonb; snap bigint;
BEGIN
 -- Drain previously committed concurrency fixtures inside this rolled-back test.
 PERFORM public.project_notification_center(500);
 INSERT INTO public.organizations(title) VALUES('Projection lifecycle') RETURNING id INTO org;
 INSERT INTO public.occasions(title,organization,link,start_time,end_time) VALUES('Current',org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,link,start_time,end_time) VALUES('Other',org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc2;
 INSERT INTO auth.users(id) VALUES(actor),(late_user);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org),(late_user,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,actor,true),(oc2,actor,true);
 INSERT INTO public.notification_center_activation(organization,enabled,activated_at) VALUES(org,true,clock_timestamp()-interval '3 days');
 first_event:=public.notification_center_publish_internal(org,oc,'order_created','first','{}',NULL,clock_timestamp()-interval '1 day');
 old_event:=public.notification_center_publish_internal(org,oc,'order_created','second');
 PERFORM public.notification_center_publish_internal(org,oc2,'order_created','other');
 issue:=public.notification_center_publish_internal(org,oc,'capacity_full','capacity-episode');
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,late_user,true);
 PERFORM public.project_notification_center(1);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org),1::bigint,'projection batch bounds recipients');
 FOR i IN 1..5 LOOP PERFORM public.project_notification_center(1); END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org),4::bigint,'bounded fanout eventually catches up');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org AND recipient=late_user),0::bigint,'new rights do not gain historical recipient snapshot');
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 page:=public.open_notification_center(org,oc,1);snap:=(page->>'snapshot')::bigint;
 PERFORM assert_eq(page#>>'{groups,0,occasionId}',oc::text,'current event has priority over newer other events');
 cursor:=page->'nextCursor';
 PERFORM assert_true(cursor<>'null'::jsonb,'page exposes a stable cursor');
 page:=public.get_notification_center_page(org,oc,10,snap,cursor);
 PERFORM assert_eq(jsonb_array_length(page->'groups'),3,'remaining groups page without duplicates');
 PERFORM assert_eq((SELECT count(DISTINCT group_key) FROM public.notification_center_deliveries WHERE organization=org),4::bigint,'days and kinds separate groups');
 -- Removing a real configured limit recovers the old episode without adding attention.
 PERFORM public.notification_center_capacity_transition_internal(org,oc,'form:remove-limit','{"limit":10,"remainingPublic":1}');
 PERFORM public.notification_center_capacity_transition_internal(org,oc,'form:remove-limit','{"limit":10,"remainingPublic":0}');
 PERFORM public.notification_center_capacity_transition_internal(org,oc,'form:remove-limit','{"limit":null,"remainingPublic":null}');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE organization=org AND source_key='form:remove-limit:episode:1'),'recovered'::text,'removed limit recovers capacity episode');
 -- Personal read covers groups/pages never expanded by this device.
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'open acknowledged every delivered page');
 UPDATE public.notification_center_events SET occurred_at=clock_timestamp()-interval '100 days' WHERE id IN(first_event,issue);
 UPDATE public.notification_center_deliveries SET delivered_at=clock_timestamp()-interval '100 days' WHERE event_id IN(first_event,issue);
 PERFORM public.maintain_notification_center(100);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=first_event),'old ordinary projection is cleaned');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=issue),'active problem survives retention');
 UPDATE public.notification_center_events SET status='recovered' WHERE id=issue;
 PERFORM public.maintain_notification_center(100);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=issue),'recovered old problem can be cleaned');
END $$;
ROLLBACK;
