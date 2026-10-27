-- test-setup: database/functions/notification_center/daily_overview.sql
BEGIN;
DO $$
DECLARE f bigint; oid bigint; org bigint; oc bigint; other_oc bigint; viewer uuid:=gen_random_uuid(); result jsonb; page jsonb; cursor jsonb;
 at timestamptz:='2026-10-27 20:00Z'; snap bigint; before_read bigint; n int:=0; ids text[]:='{}'; summary text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Daily overview fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Same title',gen_random_uuid()::text,at,at+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Same title',gen_random_uuid()::text,at,at+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true),(other_oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,at-interval '60 days');
 INSERT INTO public.forms(occasion,title) VALUES(oc,'Daily orders') RETURNING id INTO f;
 INSERT INTO public.form_fields(form,type,data) VALUES(f,'ticket','{"max_tickets":20}');
 FOR i IN 1..35 LOOP
  INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
   VALUES(oc,f,'ordered','9X8Y7W'||((i-1)/9+1)::text||'F'||((i-1)%9+1)::text||'G',i,
    jsonb_build_object('name','Jméno '||i,'surname','Zákazník')) RETURNING id INTO oid;
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:'||i,
   jsonb_build_object('orderId',oid,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,'2026-10-25 01:00Z'::timestamptz+make_interval(mins=>i));
 END LOOP;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:today1','{"count":3,"formContext":{"allowsMultiple":true}}',NULL,'2026-10-27 10:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:today2','{"count":5,"formContext":{"allowsMultiple":true}}',NULL,'2026-10-27 11:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:unknown1','{"count":2,"formContext":{"allowsMultiple":true}}',NULL,'2026-10-26 10:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:unknown2','{}',NULL,'2026-10-26 11:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','daily:cancel','{"count":2,"formContext":{"allowsMultiple":false}}',NULL,'2026-10-27 12:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'form_closed','daily:form','{}',NULL,'2026-10-25 14:00Z');
 PERFORM public.notification_center_publish_internal(org,oc,'form_closed','daily:old-form','{}',NULL,'2026-10-19 14:00Z');
 FOR i IN 1..2 LOOP
  PERFORM public.notification_center_publish_internal(org,other_oc,'order_created','daily:single:'||i,
   '{"count":1,"formContext":{"allowsMultiple":false}}',NULL,'2026-10-27 10:00Z'::timestamptz+make_interval(mins=>i));
 END LOOP;
 PERFORM public.notification_center_publish_internal(org,oc,'offer_accepted','daily:midnight-before','{"count":1}',NULL,'2026-10-26 22:59Z');
 PERFORM public.notification_center_publish_internal(org,oc,'offer_accepted','daily:midnight-after','{"count":1}',NULL,'2026-10-26 23:00Z');
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=public.get_notification_center_daily_overview(org,oc,p_timezone=>'Europe/Prague',p_open=>true);
 PERFORM assert_true((result->>'dailySupported')::boolean,'one-call open returns daily data and acknowledges atomically');
 PERFORM assert_eq(jsonb_array_length(result->'occasions'),2,'one-call open includes per-occasion preferences');
 snap:=(result->>'snapshot')::bigint;
 before_read:=(SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer);
 SET LOCAL ROLE authenticated;
 page:=public.get_notification_center_daily_overview(org,oc,snap,at,'Europe/Prague');
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(page->'items'),9,'daily summaries preserve kind, date and occasion identities');
 SELECT x->>'id' INTO summary FROM jsonb_array_elements(page->'items') x WHERE (x#>>'{data,activityCount}')::int=35;
 PERFORM assert_true(summary IS NOT NULL,'complete daily count is independent of page size');
 PERFORM assert_eq((SELECT (x#>>'{data,placeCount}')::int FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),70,'captured historical places sum across the complete day');
 PERFORM assert_eq((SELECT x->>'day' FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'2026-10-25','DST day retains its local date');
 PERFORM assert_eq((SELECT (x#>>'{data,placeCount}')::int FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='order_created' AND x->>'day'='2026-10-27' AND (x->>'occasionId')::bigint=oc),8,'today is independent of older orders');
 PERFORM assert_true((SELECT NOT (x->'data' ? 'placeCount') FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='order_created' AND x->>'day'='2026-10-26'),'missing counts never become a partial place total');
 PERFORM assert_true((SELECT NOT (x->'data' ? 'placeCount') FROM jsonb_array_elements(page->'items') x WHERE (x->>'occasionId')::bigint=other_oc),'one-order-one-application summary has no redundant place total');
 PERFORM assert_eq((SELECT count(DISTINCT x->>'day') FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='offer_accepted'),2::bigint,'local midnight separates two instants in the same UTC day');
 PERFORM assert_true((SELECT (x#>>'{data,relatedOrders}')::boolean AND NOT (x->'data' ? 'orderId') FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'summary navigates directly to common orders page');
 PERFORM assert_true((SELECT jsonb_array_length(x#>'{data,previewContacts}')<=3 FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'contact preview is bounded');
 PERFORM assert_eq((SELECT x#>>'{data,previewContacts,0,name}' FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'Jméno 35','latest contact leads the preview');
 PERFORM assert_eq((SELECT x#>>'{data,previewContacts,1,name}' FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'Jméno 34','second most recent authorized contact is included');
 PERFORM assert_eq((SELECT x#>>'{data,previewContacts,2,name}' FROM jsonb_array_elements(page->'items') x WHERE x->>'id'=summary),'Jméno 33','third contact is available for wider layouts');
 PERFORM assert_eq((SELECT (x#>>'{data,count}')::int FROM jsonb_array_elements(page->'items') x WHERE x->>'kind'='order_cancelled'),2,'singleton retains captured places despite changed single-place configuration');
 cursor:=NULL;
 LOOP
  PERFORM set_config('TimeZone',CASE WHEN n%2=0 THEN 'UTC' ELSE 'America/New_York' END,true);
  page:=public.get_notification_center_daily_overview(org,oc,snap,at,'Europe/Prague',cursor,1);
  n:=n+jsonb_array_length(page->'items');
  SELECT ids||coalesce(array_agg(x->>'id'),'{}') INTO ids FROM jsonb_array_elements(page->'items') x;
  cursor:=page->'nextCursor';EXIT WHEN cursor='null'::jsonb;
 END LOOP;
 PERFORM assert_eq(n,9,'pagination counts daily summary rows');
 PERFORM assert_eq((SELECT count(DISTINCT x) FROM unnest(ids) x),9::bigint,'no gap or repeated summary across pages');
 page:=public.get_notification_center_daily_overview(org,oc,snap,at,'Europe/Prague',NULL,1);
 BEGIN
  PERFORM public.get_notification_center_daily_overview(org,other_oc,snap,at,'Europe/Prague',page->'nextCursor',1);
  RAISE EXCEPTION 'Cross-context cursor accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.get_notification_center_daily_overview(org,oc,snap,at,'invalid/timezone');
  RAISE EXCEPTION 'Unknown timezone accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','daily:late','{"count":9}',NULL,'2026-10-25 01:00Z');
 PERFORM public.project_notification_center(500);
 page:=public.get_notification_center_daily_overview(org,oc,snap,at,'Europe/Prague',NULL,200,ARRAY[summary]);
 PERFORM assert_eq((page#>>'{items,0,data,activityCount}')::int,35,'late arrivals do not alter frozen daily count');
 PERFORM assert_eq((page#>>'{items,0,data,placeCount}')::int,70,'late arrivals do not alter frozen place total');
 PERFORM assert_eq(jsonb_array_length(page->'items'),1,'known-ID hydration does not insert another day');
 PERFORM assert_eq((SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=viewer),before_read,'daily reads never acknowledge');
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=viewer;
 page:=public.get_notification_center_daily_overview(org,NULL,snap,at,'Europe/Prague',NULL,200,ARRAY[summary]);
 PERFORM assert_eq(jsonb_array_length(page->'items'),0,'revoked summary and contacts disappear together');
 PERFORM assert_false(has_function_privilege('anon','public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean)','execute'),'no anonymous private overview');
END $$;
ROLLBACK;
