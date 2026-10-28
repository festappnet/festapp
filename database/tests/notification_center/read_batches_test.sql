BEGIN;
DO $$
DECLARE org bigint; oc bigint; link text:=gen_random_uuid()::text;
 viewer uuid:=gen_random_uuid(); colleague uuid:=gen_random_uuid(); order_ids bigint[]:='{}'; oid bigint;
 result jsonb; item jsonb; scope jsonb; selected jsonb; snap bigint; latest bigint; count_unread int;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Personal batch fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer),(colleague);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org),(colleague,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Batches',link,clock_timestamp(),clock_timestamp()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true),(oc,colleague,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,clock_timestamp()-interval '1 day');
 FOR i IN 1..5 LOOP
  INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
  VALUES(oc,'ordered',i||'A2C3E4F5G',i,'{}') RETURNING id INTO oid;
  order_ids:=array_append(order_ids,oid);
 END LOOP;
 PERFORM public.notification_center_order_internal(order_ids[1],'order_created','batch:1',NULL,
  '{"count":2,"formContext":{"allowsMultiple":true}}');
 PERFORM public.project_notification_center(500);
 PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 SET LOCAL ROLE authenticated;
 result:=public.get_notification_center_daily_overview(org,oc,p_open=>true);
 RESET ROLE;
 item:=result#>'{items,0}';snap:=(result->>'snapshot')::bigint;
 PERFORM assert_false((item->>'isRead')::boolean,'opening sees but does not read the new batch');
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'opening acknowledges the bell snapshot');
 scope:=jsonb_build_object('id',item->>'id','organization',org,'snapshot',snap,'snapshotAt',result->>'snapshotAt',
  'timezone','Europe/Prague','afterSequence',item#>'{data,afterSequence}','throughSequence',item->'sequence','markRead',true);
 SET LOCAL ROLE authenticated;
 result:=public.get_orders_tab_data(link,scope);
 RESET ROLE;
 PERFORM assert_eq(result->'notification_order_ids',jsonb_build_array(order_ids[1]),'one existing orders RPC selects exactly the displayed batch');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_read_batches WHERE organization=org AND recipient=viewer),1::bigint,'orders RPC reads the batch without another client RPC');
 result:=public.get_notification_center_daily_overview(org,oc,snap,(scope->>'snapshotAt')::timestamptz,'Europe/Prague',NULL,30,ARRAY[scope->>'id']);
 PERFORM assert_eq(result#>>'{items,0,id}',scope->>'id','refresh retains a just-read pending row under the captured alias');
 PERFORM assert_true((result#>>'{items,0,isRead}')::boolean,'refresh returns the new personal read state');
 PERFORM public.notification_center_order_internal(order_ids[4],'order_created','batch:self',viewer,'{"count":5,"formContext":{"allowsMultiple":true}}');
 PERFORM public.project_notification_center(500);
 PERFORM assert_false((public.get_notification_center_badge(org)->>'unread')::boolean,'own order alone does not light the bell');
 PERFORM public.notification_center_order_internal(order_ids[2],'order_created','batch:2',NULL,'{"count":3,"formContext":{"allowsMultiple":true}}');
 PERFORM public.notification_center_order_internal(order_ids[3],'order_created','batch:3',NULL,'{"count":4,"formContext":{"allowsMultiple":true}}');
 PERFORM public.project_notification_center(500);
 result:=public.get_notification_center_daily_overview(org,oc);
 PERFORM assert_eq(jsonb_array_length(result->'items'),3,'old read batch, new batch, and own read history are separate');
 SELECT x INTO item FROM jsonb_array_elements(result->'items') x WHERE NOT (x->>'isRead')::boolean;
 PERFORM assert_eq((item#>>'{data,activityCount}')::int,2,'new batch contains only the two external arrivals');
 PERFORM assert_eq((item#>>'{data,placeCount}')::int,7,'place total belongs to the same new batch');
 PERFORM assert_true((SELECT (x->>'isRead')::boolean FROM jsonb_array_elements(result->'items') x WHERE x->>'id' LIKE '%:self'),'own activity is already read even with only order-view rights');
 scope:=jsonb_build_object('id',item->>'id','organization',org,'snapshot',result->'snapshot','snapshotAt',result->>'snapshotAt',
  'timezone','Europe/Prague','afterSequence',item#>'{data,afterSequence}','throughSequence',item->'sequence','markRead',true);
 -- Another tab reads only the earlier portion of our captured batch.
 PERFORM public.mark_notification_center_item_read(org,scope||jsonb_build_object('throughSequence',(item->>'sequence')::bigint-1));
 UPDATE eshop.orders SET state='storno' WHERE id=order_ids[2];
 PERFORM public.notification_center_order_internal(order_ids[2],'order_cancelled','batch:self-cancel',viewer);
 -- A later arrival must not be read by an already captured click.
 PERFORM public.notification_center_order_internal(order_ids[5],'order_created','batch:late',NULL,'{"count":1}');
 PERFORM public.project_notification_center(500);
 SET LOCAL ROLE authenticated;
 result:=public.get_orders_tab_data(link,scope);
 RESET ROLE;
 PERFORM assert_eq(result->'notification_order_ids',jsonb_build_array(order_ids[3]),'cancelled and own orders are excluded from captured new selection');
 selected:=public.notification_center_order_selection(oc,scope||jsonb_build_object('markRead',false));
 PERFORM assert_eq(selected,jsonb_build_array(order_ids[3]),'reopening read history never adds the actor own activity from the same sequence range');
 PERFORM assert_false(has_table_privilege('authenticated','public.notification_center_read_batches','select'),'read receipts remain private');
 PERFORM assert_false(has_function_privilege('anon','public.mark_notification_center_item_read(bigint,jsonb)','execute'),'anonymous users cannot mark personal items');
 result:=public.get_notification_center_daily_overview(org,oc);
 SELECT x INTO item FROM jsonb_array_elements(result->'items') x WHERE NOT (x->>'isRead')::boolean;
 PERFORM assert_eq((item#>>'{data,activityCount}')::int,1,'late arrival remains a new unread batch');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(result->'items') x WHERE NOT (x->>'isRead')::boolean),1::bigint,'own cancellation never becomes an unread notification');
 -- Colleague state remains independent; our own changes are new for them.
 PERFORM set_config('request.jwt.claim.sub',colleague::text,true);
 result:=public.get_notification_center_daily_overview(org,oc);
 PERFORM assert_eq((SELECT (x#>>'{data,activityCount}')::int FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_created'),4,'other recipient still has all eligible new orders');
 PERFORM assert_eq((SELECT (x->>'isRead')::boolean FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_cancelled'),false,'own cancellation is new for the colleague');
 SELECT last_delivery_sequence INTO latest FROM public.notification_center_user_state WHERE organization=org AND recipient=colleague;
 UPDATE public.notification_center_user_state SET read_through_sequence=latest WHERE organization=org AND recipient=colleague;
 result:=public.get_notification_center_daily_overview(org,oc,p_open=>true);
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'items') x WHERE NOT (x->>'isRead')::boolean),'legacy read baseline never re-alerts the whole retained history');
END $$;
ROLLBACK;
