-- test-setup: database/functions/notification_center/overview.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; other_oc bigint; viewer uuid:=gen_random_uuid(); result jsonb; page jsonb; cursor jsonb;
 snap bigint; before_read bigint; n int:=0; ids text[]:='{}'; summary text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Compact overview fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Same title',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Same title',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true),(other_oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '60 days');
 FOR i IN 1..35 LOOP
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','overview:'||i,'{}',NULL,
   now()-make_interval(days=>i));
 END LOOP;
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','overview:cancel','{"count":2,"formContext":{"allowsMultiple":true}}',NULL,now());
 PERFORM public.notification_center_publish_internal(org,oc,'form_closed','overview:form','{}',NULL,now());
 PERFORM public.notification_center_publish_internal(org,other_oc,'order_created','overview:other','{}',NULL,now());
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.open_notification_center(org,oc);
 snap:=(result->>'snapshot')::bigint;
 before_read:=(SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer);
 SET LOCAL ROLE authenticated;
 page:=public.get_notification_center_overview(org,oc,snap);
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(page->'items'),4,'same kind combines recent and historical orders, other kinds/occasions remain distinct');
 SELECT x->>'id' INTO summary FROM jsonb_array_elements(page->'items') x WHERE (x#>>'{data,activityCount}')::int=35;
 PERFORM assert_true(summary IS NOT NULL,'full count is independent of page size');
 PERFORM assert_true((SELECT (x#>>'{data,relatedOrders}')::boolean AND NOT (x->'data' ? 'orderId')
  FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'summary uses shared orders destination, never a representative order detail');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='form_closed'),1::bigint,'information stays standalone');
 PERFORM assert_eq((SELECT (x#>>'{data,count}')::int FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='order_cancelled'),2,'singleton preserves historical seat count');
 cursor:=NULL;
 LOOP
  page:=public.get_notification_center_overview(org,oc,snap,cursor,1);
  n:=n+jsonb_array_length(page->'items');
  SELECT ids||coalesce(array_agg(x->>'id'),'{}') INTO ids FROM jsonb_array_elements(page->'items') x;
  cursor:=page->'nextCursor';EXIT WHEN cursor='null'::jsonb;
 END LOOP;
 PERFORM assert_eq(n,4,'pagination counts summary rows');
 PERFORM assert_eq((SELECT count(DISTINCT x) FROM unnest(ids) x),4::bigint,'summary pagination has no gaps or duplicates');
 page:=public.get_notification_center_overview(org,oc,snap,NULL,1);
 BEGIN
  PERFORM public.get_notification_center_overview(org,other_oc,snap,page->'nextCursor',1);
  RAISE EXCEPTION 'Cross-context cursor accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.get_notification_center_overview(org,oc,snap,NULL,200,array_fill('id'::text,ARRAY[201]));
  RAISE EXCEPTION 'Unbounded hydration accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','overview:late','{}',NULL,now());
 PERFORM public.project_notification_center(500);
 page:=public.get_notification_center_overview(org,oc,snap,NULL,200,ARRAY[summary]);
 PERFORM assert_eq((page#>>'{items,0,data,activityCount}')::int,35,'known-ID hydration excludes late arrivals');
 PERFORM assert_eq(jsonb_array_length(page->'items'),1,'hydration returns only requested identities');
 PERFORM assert_eq((SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer),before_read,'overview and hydration never acknowledge');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=viewer;
 page:=public.get_notification_center_overview(org,NULL,snap,NULL,200,ARRAY[summary]);
 PERFORM assert_eq(jsonb_array_length(page->'items'),0,'revoked summaries and their contacts disappear');
 PERFORM assert_false(has_function_privilege('anon','public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[])','execute'),'anonymous callers cannot read private overview');
END $$;
ROLLBACK;
