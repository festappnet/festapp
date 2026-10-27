-- test-setup: database/functions/notification_center/daily_overview.sql
-- test-setup: database/functions/notification_center/order_selection.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; f bigint; oid bigint; tid bigint; first_order bigint; second_order bigint; other_oc bigint; foreign_order bigint;
 viewer uuid:=gen_random_uuid(); result jsonb; created jsonb; cancelled jsonb; ids jsonb; snap bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Legacy place totals fixture') RETURNING id INTO org;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Legacy totals',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(viewer); INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,'2026-09-01Z');
 INSERT INTO public.forms(occasion,title) VALUES(oc,'Multiple tickets') RETURNING id INTO f;
 INSERT INTO public.form_fields(form,type,data) VALUES(f,'ticket','{"max_tickets":20}');
 FOR i IN 1..2 LOOP
  INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
   VALUES(oc,f,'ordered',CASE WHEN i=1 THEN '1A2C3E4F5G' ELSE '2A3C4E5F6G' END,i,'{}') RETURNING id INTO oid;
  IF i=1 THEN first_order:=oid; ELSE second_order:=oid; END IF;
  FOR j IN 1..(i+1) LOOP
   INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO tid;
   INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
  END LOOP;
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','legacy-created:'||i,
   jsonb_build_object('orderId',oid)||CASE WHEN i=1 THEN '{"count":4,"formContext":{"allowsMultiple":true}}'::jsonb ELSE '{}'::jsonb END,
   NULL,'2026-10-24 12:00Z');
  PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','legacy-cancelled:'||i,
   jsonb_build_object('orderId',oid),NULL,'2026-10-24 13:00Z');
 END LOOP;
 -- Each order can have one ticket while its form still permits multiple.
 FOR i IN 3..4 LOOP
  INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
   VALUES(oc,f,'ordered',CASE WHEN i=3 THEN '3A4C5E6F7G' ELSE '4A5C6E7F8G' END,i,'{}') RETURNING id INTO oid;
  INSERT INTO eshop.tickets(occasion,state) VALUES(oc,'ordered') RETURNING id INTO tid;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','legacy-single-ticket:'||i,
   jsonb_build_object('orderId',oid,'count',1),NULL,'2026-10-22 12:00Z');
 END LOOP;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Unauthorized event',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(other_oc,'ordered','5A6C7E8F9G',1,'{}') RETURNING id INTO foreign_order;
 INSERT INTO eshop.tickets(occasion,state) VALUES(other_oc,'ordered') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(foreign_order,tid);
 -- Even a malformed historical reference must never hydrate another event.
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','unknown-count',
  jsonb_build_object('orderId',foreign_order,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,'2026-10-23 12:00Z');
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 SET LOCAL ROLE authenticated;
 result:=public.get_notification_center_daily_overview(org,oc,p_timezone=>'Europe/Prague',p_open=>true);
 RESET ROLE;
 snap:=(result->>'snapshot')::bigint;
 SELECT x INTO created FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_created' AND x->>'day'='2026-10-24';
 SELECT x INTO cancelled FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_cancelled';
 PERFORM assert_eq((created#>>'{data,placeCount}')::int,7,'captured historical count4 wins; legacy count3 is batch-hydrated');
 PERFORM assert_eq((cancelled#>>'{data,placeCount}')::int,5,'cancelled legacy group recovers all retained ticket identities');
 PERFORM assert_true((cancelled#>>'{data,allowsMultiple}')::boolean,'legacy multi-ticket form retains place-count applicability');
 PERFORM assert_eq((SELECT (x#>>'{data,placeCount}')::int FROM jsonb_array_elements(result->'items') x
  WHERE x->>'day'='2026-10-22'),2,'one ticket each still shows total2 when the form allows multiple');
 PERFORM assert_true((SELECT x#>'{data,placeCount}' IS NULL AND (x#>>'{data,allowsMultiple}')::boolean
  FROM jsonb_array_elements(result->'items') x WHERE x->>'day'='2026-10-23'),'unknown count is explicit, never invented as zero');
 SET LOCAL ROLE authenticated;
 ids:=public.notification_center_order_selection(oc,jsonb_build_object('id',created->>'id','organization',org,'snapshot',snap,'timezone','Europe/Prague'));
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(ids),2,'new-order click selects the complete group');
 PERFORM assert_true(ids @> jsonb_build_array(first_order,second_order),'selected IDs are exact order identities');
 SET LOCAL ROLE authenticated;
 ids:=public.notification_center_order_selection(oc,jsonb_build_object('id',cancelled->>'id','organization',org,'snapshot',snap,'timezone','Europe/Prague'));
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(ids),2,'cancelled-order click selects the complete group too');
 UPDATE eshop.tickets SET state='storno' WHERE occasion=oc;
 result:=public.get_notification_center_daily_overview(org,oc,snap,p_timezone=>'Europe/Prague');
 PERFORM assert_eq((SELECT (x#>>'{data,placeCount}')::int FROM jsonb_array_elements(result->'items') x
  WHERE x->>'kind'='order_cancelled'),5,'cancellation does not erase retained ticket totals');
END $$;
ROLLBACK;
