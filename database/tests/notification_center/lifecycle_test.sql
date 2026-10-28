-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/daily_overview.sql
-- test-setup: database/functions/notification_center/order_selection.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; extra_oc bigint; viewer uuid:=gen_random_uuid(); anchor timestamptz:=clock_timestamp();
 old_order bigint; border_order bigint; fresh_order bigint; snap bigint; old_snap bigint; result jsonb; page jsonb;
 selected jsonb; cursor jsonb; n int:=0; rounds int:=0; ids text[]:='{}'; scope jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Center lifecycle fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Lifecycle',gen_random_uuid()::text,anchor,anchor+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,anchor-interval '120 days');
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered','1A2C3E4F5G',1,'{}') RETURNING id INTO old_order;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered','2A3C4E5F6G',2,'{}') RETURNING id INTO border_order;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered','3A4C5E6F7G',3,'{}') RETURNING id INTO fresh_order;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','life:old',
  jsonb_build_object('orderId',old_order,'count',4,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor-interval '31 days');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','life:border',
  jsonb_build_object('orderId',border_order,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor-interval '29 days');
 PERFORM public.project_notification_center(500);
 SELECT last_delivery_sequence INTO old_snap FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer;
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 scope:=jsonb_build_object('id','occasion-kind:'||oc||':order_created','organization',org,'snapshot',old_snap,'timezone','Europe/Prague','snapshotAt',anchor-interval '2 days');
 SET LOCAL ROLE authenticated;
 selected:=public.notification_center_order_selection(oc,scope);
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(selected),2,'selection preserves the exact cutoff from an older open panel');
 scope:=scope||jsonb_build_object('snapshotAt',anchor);
 SET LOCAL ROLE authenticated;
 selected:=public.notification_center_order_selection(oc,scope);
 RESET ROLE;
 PERFORM assert_eq(selected,jsonb_build_array(border_order),'expired order is excluded from the current scope');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','life:fresh',
  jsonb_build_object('orderId',fresh_order,'count',3,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor-interval '1 hour');
 PERFORM public.notification_center_publish_internal(org,oc,'email_problem','life:active-error','{}',NULL,anchor-interval '100 days');
 PERFORM public.notification_center_publish_internal(org,oc,'email_problem','life:solved-error','{}',NULL,anchor-interval '1 hour');
 UPDATE public.notification_center_events SET status='recovered' WHERE organization=org AND source_key='life:solved-error';
 PERFORM public.project_notification_center(500);
 SET LOCAL ROLE authenticated;
 result:=public.get_notification_center_daily_overview(org,oc,p_timezone=>'Europe/Prague',p_open=>true);
 RESET ROLE;
 snap:=(result->>'snapshot')::bigint;
 PERFORM assert_eq(jsonb_array_length(result->'items'),2,'only recent activity and the unresolved incident remain');
 PERFORM assert_eq((SELECT (x#>>'{data,activityCount}')::int FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_created'),2,'window count includes exactly the two recent orders');
 PERFORM assert_eq((SELECT (x#>>'{data,placeCount}')::int FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_created'),5,'place total uses the same window as order count');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='email_problem'),1::bigint,'old active error survives while the recovered error disappears');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE organization=org AND source_key='life:active-error'),'active','opening marks read, never resolves the underlying incident');
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'successful open clears the global new-activity badge');
 scope:=scope||jsonb_build_object('snapshot',snap,'snapshotAt',result->>'snapshotAt');
 SET LOCAL ROLE authenticated;
 selected:=public.notification_center_order_selection(oc,scope);
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(selected),2,'displayed category and selected set have identical membership');
 PERFORM assert_false(selected @> jsonb_build_array(old_order),'expired order is not silently checked');
 -- Expired activity/recovered incidents must not leave an invisible badge.
 UPDATE public.notification_center_events SET status='recovered' WHERE organization=org AND kind='email_problem';
 UPDATE public.notification_center_events SET occurred_at=anchor-interval '31 days' WHERE organization=org AND kind='order_created';
 UPDATE public.notification_center_user_state SET read_through_sequence=0 WHERE organization=org AND recipient=viewer;
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'expired and resolved events do not create a phantom badge');
 -- Bound the center, not the counts inside each category or the audit records.
 FOR i IN 1..120 LOOP
  INSERT INTO public.occasions(organization,title,link,start_time,end_time)
  VALUES(org,'Category '||i,gen_random_uuid()::text,anchor,anchor+interval '1 day') RETURNING id INTO extra_oc;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(extra_oc,viewer,true);
  PERFORM public.notification_center_publish_internal(org,extra_oc,'form_closed','life:cap:'||i,'{}',NULL,anchor-make_interval(secs=>i));
 END LOOP;
 PERFORM public.project_notification_center(500);
 result:=public.get_notification_center_daily_overview(org,NULL,p_timezone=>'Europe/Prague',p_open=>true);
 PERFORM assert_true((result->>'truncated')::boolean,'large histories disclose the finite center limit');
 snap:=(result->>'snapshot')::bigint;
 LOOP
  page:=public.get_notification_center_daily_overview(org,NULL,snap,(result->>'snapshotAt')::timestamptz,'Europe/Prague',cursor,30);
  n:=n+jsonb_array_length(page->'items'); rounds:=rounds+1;
  SELECT ids||coalesce(array_agg(x->>'id'),'{}') INTO ids FROM jsonb_array_elements(page->'items') x;
  cursor:=page->'nextCursor'; EXIT WHEN cursor='null'::jsonb;
  IF rounds>4 THEN RAISE EXCEPTION 'Unbounded center pagination'; END IF;
 END LOOP;
 PERFORM assert_eq(n,100,'pagination has a real end after100 center items');
 PERFORM assert_eq((SELECT count(DISTINCT x) FROM unnest(ids) x),100::bigint,'bounded pages have no duplicate items');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key LIKE 'life:cap:%'),120::bigint,'presentation limit deletes no audit events');
END $$;
ROLLBACK;
