BEGIN;
DO $$
DECLARE org bigint; oc bigint; other_oc bigint; viewer uuid:=gen_random_uuid(); result jsonb; page jsonb; cursor jsonb; bucket jsonb;
 at timestamptz:='2026-10-26 12:00Z'; periods jsonb; n integer; ids text[]; read_before bigint; snap bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Temporal notification fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Same title',gen_random_uuid()::text,at,at+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Same title',gen_random_uuid()::text,at,at+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true),(other_oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,at-interval '30 days');
 FOR i IN 1..35 LOOP
  PERFORM public.notification_center_publish_internal(org,oc,
   CASE i%3 WHEN 0 THEN 'order_cancelled' WHEN 1 THEN 'order_created' ELSE 'waitlist_registered' END,
   'temporal:'||i,'{}',NULL,'2026-10-25 01:00Z'::timestamptz+make_interval(mins=>i));
 END LOOP;
 PERFORM public.notification_center_publish_internal(org,oc,'form_closed','separate-form','{}',NULL,'2026-10-25 00:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','recent','{}',NULL,at-interval '1 hour');
 PERFORM public.notification_center_publish_internal(org,oc,'offer_declined','week1','{}',NULL,'2026-10-21 12:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','week2','{}',NULL,'2026-10-21 13:00Z');
 PERFORM public.notification_center_publish_internal(org,other_oc,'order_created','other-occasion','{}',NULL,'2026-10-25 01:00Z');
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.open_notification_center(org,oc);
 PERFORM assert_true((result->>'timelineSupported')::boolean,'additive timeline capability');
 PERFORM assert_true(result->>'oldestOrderAt' IS NOT NULL,'oldest snapshot order anchors device calendar');
 snap:=(result->>'snapshot')::bigint;
 read_before:=(SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer);
 periods:='[{"unit":"day","startAt":"2026-10-24T22:00Z","endAt":"2026-10-25T12:00Z","firstDay":"2026-10-25","lastDay":"2026-10-25"},
 {"unit":"day","startAt":"2026-10-23T22:00Z","endAt":"2026-10-24T22:00Z","firstDay":"2026-10-24","lastDay":"2026-10-24"},
 {"unit":"week","startAt":"2026-10-19T22:00Z","endAt":"2026-10-23T22:00Z","firstDay":"2026-10-20","lastDay":"2026-10-23"}]';
 page:=public.get_notification_center_timeline(org,oc,snap,at,periods,NULL,100);
 PERFORM assert_eq(jsonb_array_length(page->'items'),5,'recent order, form and three per-occasion periods');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='order_activity_group'),3::bigint,'only order actions aggregate');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='form_closed'),1::bigint,'old form close remains a standalone row');
 SELECT x INTO bucket FROM jsonb_array_elements(page->'items') x WHERE (x#>>'{data,count}')::int=35;
 PERFORM assert_eq((bucket->>'occasionId')::bigint,oc,'same-name occasions are separate');
 -- Counts cover the complete authorized snapshot, regardless of row/child page limits.
 cursor:=NULL;n:=0;
 LOOP
  page:=public.get_notification_center_timeline(org,oc,snap,at,periods,cursor,1);
  n:=n+jsonb_array_length(page->'items');cursor:=page->'nextCursor';EXIT WHEN cursor='null'::jsonb;
 END LOOP;
 PERFORM assert_eq(n,5,'summary pagination never splits or repeats a bucket');
 cursor:=NULL;n:=0;ids:='{}';
 LOOP
  page:=public.get_notification_center_timeline_group(org,oc,snap,at,oc,bucket#>'{data,period}',cursor,7);
  n:=n+jsonb_array_length(page->'items');
  SELECT ids||coalesce(array_agg(x->>'id'),'{}') INTO ids FROM jsonb_array_elements(page->'items') x;
  cursor:=page->'nextCursor';EXIT WHEN cursor='null'::jsonb;
 END LOOP;
 PERFORM assert_eq(n,35,'all mixed order actions expand, beyond the first 30');
 PERFORM assert_eq((SELECT count(DISTINCT x) FROM unnest(ids) x),35::bigint,'child keyset pagination is gap/duplicate free');
 PERFORM assert_eq((SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer),read_before,'summary, expansion and pagination never acknowledge');
 page:=public.get_notification_center_timeline(org,oc,snap,at,periods,NULL,1);
 BEGIN
  PERFORM public.get_notification_center_timeline(org,other_oc,snap,at,periods,page->'nextCursor',1);
  RAISE EXCEPTION 'Cross-context cursor accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.get_notification_center_timeline(org,oc,snap,at,'[]');
  RAISE EXCEPTION 'Incomplete calendar accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.get_notification_center_timeline(org,oc,snap,at,jsonb_build_array(periods->0,periods->0));
  RAISE EXCEPTION 'Overlapping intervals accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','late-old-order','{}',NULL,'2026-10-25 01:00Z');
 PERFORM public.project_notification_center(500);
 page:=public.get_notification_center_timeline_group_updates(org,oc,snap,at,
  jsonb_build_array(jsonb_build_object('id',bucket->>'id','occasionId',oc,'period',bucket#>'{data,period}')));
 PERFORM assert_eq((page#>>'{groups,0,count}')::int,35,'late arrivals do not alter frozen bucket counts');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=viewer;
 page:=public.get_notification_center_timeline_group_updates(org,NULL,snap,at,
  jsonb_build_array(jsonb_build_object('id',bucket->>'id','occasionId',oc,'period',bucket#>'{data,period}')));
 PERFORM assert_eq((page#>>'{groups,0,count}')::int,0,'revocation clears collapsed counts');
 PERFORM assert_eq(jsonb_array_length(public.get_notification_center_timeline_group(org,NULL,snap,at,oc,bucket#>'{data,period}')->'items'),0,'revocation hides expanded contacts too');
 PERFORM assert_false(has_function_privilege('anon','public.get_notification_center_timeline(bigint,bigint,bigint,timestamptz,jsonb,jsonb,integer)','execute'),'no anonymous summaries');
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_order_activity_internal(text)','execute'),'classification helper stays private');
END $$;
ROLLBACK;
