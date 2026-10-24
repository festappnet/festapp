BEGIN;
DO $$
DECLARE org bigint; oc bigint; editor uuid:=gen_random_uuid(); orders_only uuid:=gen_random_uuid(); member uuid:=gen_random_uuid();
 outsider uuid:=gen_random_uuid(); tenant_admin uuid:=gen_random_uuid(); ev bigint; response jsonb; notification uuid; snapshot bigint; n integer; usr uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('App administration notifications') RETURNING id INTO org;
 INSERT INTO public.occasions(organization,title,link,is_open,is_hidden,features,start_time,end_time)
 VALUES(org,'Public festival',gen_random_uuid()::text,true,false,'[{"code":"schedule","is_enabled":true}]',now(),now()+interval '2 days') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(editor),(orders_only),(member),(outsider),(tenant_admin);
 INSERT INTO public.user_info(id,organization,name) VALUES(editor,org,'Editor'),(orders_only,org,'Orders'),(member,org,'Participant'),(outsider,org,'Visitor'),(tenant_admin,org,'Admin');
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order_view)
 VALUES(oc,editor,true,false),(oc,orders_only,false,true);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,tenant_admin,true);
 INSERT INTO public.events(occasion,title,start_time,end_time,max_participants) VALUES(oc,'Limited workshop',now()+interval '1 day',now()+interval '1 day 1 hour',1) RETURNING id INTO ev;
 PERFORM public.set_notification_center_activation(org,true);
 PERFORM set_config('request.jwt.claim.sub',member::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 response:=public.add_user_to_occasion_client_sync_v1(oc,member,gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,200,'self join succeeds');
 PERFORM public.add_user_to_occasion_client_sync_v1(oc,member,gen_random_uuid());
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='occasion_joined'),1::bigint,'repeat join does not duplicate attention');
 response:=public.set_event_attendance_client_sync_v1(ev,member,'sign_in',gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,200,'real attendance command fills event');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='event_capacity_full'),1::bigint,'full boundary produces one event');
 PERFORM public.set_event_attendance_client_sync_v1(ev,member,'sign_in',gen_random_uuid());
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='event_capacity_full'),1::bigint,'duplicate attendance cannot spam');
 -- 100 real enrollments must become one day/occasion group with bounded initial hydration.
 FOR n IN 1..99 LOOP
  usr:=gen_random_uuid();
  INSERT INTO auth.users(id) VALUES(usr);
  INSERT INTO public.user_info(id,organization,name) VALUES(usr,org,'Bulk participant');
  PERFORM set_config('request.jwt.claim.sub',usr::text,true);
  PERFORM public.add_user_to_occasion_client_sync_v1(oc,usr,gen_random_uuid());
 END LOOP;
 FOR n IN 1..5 LOOP PERFORM public.project_notification_center(500); END LOOP;
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 response:=public.open_notification_center(org,oc);
 PERFORM assert_eq(jsonb_array_length(response->'groups'),2,'100 joins and full workshop use two groups');
 PERFORM assert_eq((SELECT (g->>'count')::int FROM jsonb_array_elements(response->'groups') g WHERE g->>'kind'='occasion_joined'),100,'membership group has full count');
 PERFORM assert_eq((SELECT jsonb_array_length(g->'items') FROM jsonb_array_elements(response->'groups') g WHERE g->>'kind'='occasion_joined'),5,'first response hydrates at most five members');
 snapshot:=(response->>'snapshot')::bigint;
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_group(org,(SELECT g->>'key' FROM jsonb_array_elements(response->'groups') g WHERE g->>'kind'='occasion_joined'),snapshot,NULL,20)->'items'),20,'expanded group is paginated');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id WHERE e.organization=org AND d.recipient=orders_only),0::bigint,'order-only viewer gets no app participant data');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id WHERE e.organization=org AND d.recipient=tenant_admin),101::bigint,'tenant administrator receives app events without occasion membership');
 PERFORM public.set_notification_center_muted(org,oc,true);
 PERFORM set_config('request.jwt.claim.sub',member::text,true);
 PERFORM public.set_event_attendance_client_sync_v1(ev,member,'sign_out',gen_random_uuid());
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE organization=org AND kind='event_capacity_full'),'recovered','cancellation reopens event without new unread item');
 PERFORM public.set_event_attendance_client_sync_v1(ev,member,'sign_in',gen_random_uuid());
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='event_capacity_full'),1::bigint,'full/reopen oscillation reuses one daily event');
 PERFORM assert_eq((SELECT last_delivery_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=editor),101::bigint,'same-day full oscillation does not allocate another delivery');
 DELETE FROM public.occasion_users WHERE occasion=oc AND "user"=member;
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 SELECT public.notification_center_dto(e,d) INTO response FROM public.notification_center_events e JOIN public.notification_center_deliveries d ON d.event_id=e.id
 WHERE e.organization=org AND e.kind='occasion_joined' AND e.data->>'userId'=member::text AND d.recipient=editor;
 PERFORM assert_eq(response#>>'{data,state}','membership_left','departed participant DTO reflects current membership');
 PERFORM set_config('request.jwt.claim.sub',member::text,true);
 PERFORM public.add_user_to_occasion_client_sync_v1(oc,member,gen_random_uuid());
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='occasion_joined'),100::bigint,'same-day leave/rejoin cannot inflate membership group');
 -- Split capacities enforce independent male/female buckets, as attendance does.
 UPDATE public.user_info SET sex='male' WHERE id=member;
 UPDATE public.user_info SET sex='female' WHERE id=outsider;
 INSERT INTO public.events(occasion,title,start_time,end_time,max_participants,split_for_men_women)
 VALUES(oc,'Split workshop',now()+interval '1 day 2 hours',now()+interval '1 day 3 hours',2,true) RETURNING id INTO ev;
 PERFORM set_config('request.jwt.claim.sub',member::text,true);
 response:=public.set_event_attendance_client_sync_v1(ev,member,'sign_in',gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,200,'first gender bucket signup succeeds');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND data->>'eventId'=ev::text),0::bigint,'one full gender bucket leaves other bucket available');
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 response:=public.set_event_attendance_client_sync_v1(ev,outsider,'sign_in',gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,200,'attendance can join occasion and event together');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND kind='event_capacity_full' AND data->>'eventId'=ev::text),1::bigint,'both gender buckets full produce one event');
 INSERT INTO public.events(occasion,title,start_time,end_time)
 VALUES(oc,'Unlimited workshop',now()+interval '1 day 4 hours',now()+interval '1 day 5 hours') RETURNING id INTO ev;
 PERFORM public.set_event_attendance_client_sync_v1(ev,outsider,'sign_in',gen_random_uuid());
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND data->>'eventId'=ev::text),0::bigint,'unlimited events never become full');
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 UPDATE public.occasion_users SET is_editor=false WHERE occasion=oc AND "user"=editor;
 BEGIN PERFORM public.open_notification_center(org,oc); RAISE EXCEPTION 'revoked app editor retained access'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
