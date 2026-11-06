-- test-setup: database/tests/helpers/prepared_notification_view.sql
-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/order_selection.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; viewer uuid:=gen_random_uuid(); anchor timestamptz:=clock_timestamp();
 active_order bigint; cancelled_order bigint; result jsonb; selected jsonb; scope jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Cancelled new orders fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Orders',gen_random_uuid()::text,anchor,anchor+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,anchor-interval '1 day');
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered','1A2C3E4F5G',1,'{}') RETURNING id INTO active_order;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered','2A3C4E5F6G',2,'{}') RETURNING id INTO cancelled_order;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','cancel:new:active',
  jsonb_build_object('orderId',active_order,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor);
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','cancel:new:cancelled',
  jsonb_build_object('orderId',cancelled_order,'count',5,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor);
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 result:=pg_temp.prepared_notification_view(org,oc,p_keep_view=>true);
 scope:=jsonb_build_object('id',result#>>'{items,0,id}','organization',org,'viewToken',result->>'viewToken');
 -- Cancel after the panel snapshot, deliberately leaving the old event projection unchanged.
 UPDATE eshop.orders SET state='storno' WHERE id=cancelled_order;
 PERFORM public.notification_center_order_state_internal(cancelled_order);
 result:=pg_temp.prepared_notification_view(org,oc,p_mode=>'refresh',p_view=>(scope->>'viewToken')::uuid,p_keep_view=>true);
 SET LOCAL ROLE authenticated;
 selected:=public.notification_center_order_selection(oc,scope);
 result:=pg_temp.prepared_notification_view(org,oc);
 RESET ROLE;
 PERFORM assert_eq(selected,jsonb_build_array(active_order),'a previously opened new-order group excludes a now cancelled order');
 PERFORM assert_eq((result#>>'{items,0,data,activityCount}')::int,1,'cancelled orders do not count as new orders');
 PERFORM assert_eq((result#>>'{items,0,data,placeCount}')::int,2,'cancelled places do not count in new-order totals');
 PERFORM assert_eq(jsonb_array_length(result#>'{items,0,data,previewContacts}'),1,'cancelled buyers are omitted from the preview');
 UPDATE eshop.orders SET state='storno' WHERE id=active_order;
 PERFORM public.notification_center_order_state_internal(active_order);
 PERFORM assert_false((pg_temp.prepared_notification_badge(org)->>'unread')::boolean,'cancelled new-order activity cannot leave a phantom unread badge');
 UPDATE eshop.orders SET state='ordered' WHERE id=active_order;
 PERFORM public.notification_center_order_state_internal(active_order);
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','cancel:cancelled',
  jsonb_build_object('orderId',cancelled_order,'count',5,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,anchor);
 PERFORM public.project_notification_center(500);
 result:=pg_temp.prepared_notification_view(org,oc,p_keep_view=>true);
 SELECT jsonb_build_object('id',x->>'id','organization',org,'viewToken',result->>'viewToken') INTO scope FROM jsonb_array_elements(result->'items') x WHERE x->>'kind'='order_cancelled';
 SET LOCAL ROLE authenticated;
 selected:=public.notification_center_order_selection(oc,scope);
 result:=pg_temp.prepared_notification_view(org,oc);
 RESET ROLE;
 PERFORM assert_eq(selected,jsonb_build_array(cancelled_order),'cancelled-order groups retain their own selection');
 PERFORM assert_eq(jsonb_array_length(result->'items'),2,'new and cancelled categories remain separate');
 UPDATE eshop.orders SET state='storno' WHERE id=active_order;
 PERFORM public.notification_center_order_state_internal(active_order);
 result:=pg_temp.prepared_notification_view(org,oc,p_keep_view=>true);
 PERFORM assert_eq(jsonb_array_length(result->'items'),1,'an empty new-order category disappears');
 PERFORM assert_eq(result#>>'{items,0,kind}','order_cancelled','cancelled notifications remain available');
END $$;
ROLLBACK;
