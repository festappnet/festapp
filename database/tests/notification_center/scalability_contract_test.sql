-- Wave 0: executable contract proof against the real released SQL owners.
-- test-setup: database/functions/notification_center/subject_visibility.sql
-- test-setup: database/functions/notification_center/center_policy.sql
-- test-setup: database/functions/notification_center/daily_overview.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid();
 hidden uuid:=gen_random_uuid(); order_ids bigint[]:='{}'; oid bigint; v jsonb; old_view jsonb;
 scope jsonb; selected jsonb; anchor timestamptz; revision_event uuid; snap bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Scalability contract') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(a),(b),(hidden);
 INSERT INTO public.user_info(id,organization,email_readonly) VALUES(a,org,'a@example.invalid'),(b,org,'b@example.invalid'),(hidden,org,'buyer1@example.invalid');
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Contract',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,a,true),(oc,b,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '60 days');
 FOR i IN 1..3 LOOP
  INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
  VALUES(oc,'ordered',public.generate_order_symbol(),i,jsonb_build_object('name','Buyer '||i,'email','buyer'||i||'@example.invalid')) RETURNING id INTO oid;
  order_ids:=array_append(order_ids,oid);
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','proof:'||i,
   jsonb_build_object('orderId',oid,'count',CASE WHEN i=3 THEN NULL ELSE i END,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,now()-interval '1 day');
 END LOOP;
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 old_view:=public.get_notification_center_daily_overview(org,oc,p_open=>true);
 anchor:=(old_view->>'snapshotAt')::timestamptz; snap:=(old_view->>'snapshot')::bigint;
 PERFORM assert_eq(snap,3::bigint,'two recipients have independent sequences');
 PERFORM assert_eq((old_view#>>'{items,0,data,activityCount}')::int,3,'all distinct orders aggregate');
 PERFORM assert_true(old_view#>'{items,0,data,placeCount}' IS NULL,'unknown count suppresses exact total');
 PERFORM assert_eq((SELECT read_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=a),0::bigint,'open only sees');
 scope:=jsonb_build_object('id',old_view#>>'{items,0,id}','organization',org,'snapshot',snap,'snapshotAt',anchor,'timezone','UTC','throughSequence',2);
 PERFORM assert_true(public.mark_notification_center_item_read(org,scope),'another tab seals captured prefix');
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','late',jsonb_build_object('orderId',order_ids[2],'count',2),NULL,now()-interval '2 days');
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq(jsonb_array_length(public.notification_center_order_selection(oc,scope)),2,'partial selection stays within captured prefix');
 scope:=scope||jsonb_build_object('throughSequence',snap);
 PERFORM assert_true(public.mark_notification_center_item_read(org,scope),'original tab reads remaining captured suffix');
 PERFORM assert_true(public.mark_notification_center_item_read(org,scope||jsonb_build_object('throughSequence',2)),'reverse retry remains idempotent');
 v:=public.get_notification_center_daily_overview(org,oc,p_open=>true);
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') r WHERE r->>'isRead'='false' AND (r->>'sequence')::bigint=4),'late old arrival stays unread');
 INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,hidden,true);
 selected:=public.notification_center_order_selection(oc,scope);
 PERFORM assert_false(selected @> to_jsonb(ARRAY[order_ids[1]]),'old snapshot applies current hidden-email matching');
 UPDATE public.organization_users SET is_hidden=false WHERE organization=org AND "user"=hidden;
 PERFORM assert_true(public.notification_center_order_selection(oc,scope) @> to_jsonb(ARRAY[order_ids[1]]),'unhide restores eligible captured membership');
 UPDATE eshop.orders SET state='storno' WHERE id=order_ids[1];
 PERFORM public.notification_center_order_state_internal(order_ids[1]);
 PERFORM assert_false(public.notification_center_order_selection(oc,scope) @> to_jsonb(ARRAY[order_ids[1]]),'storno retracts old snapshot membership');
 -- A current membership row alone cannot answer a pinned older delivery bound.
 revision_event:=public.notification_center_publish_internal(org,oc,'capacity_warning','revision-proof');
 PERFORM public.project_notification_center(500);
 SELECT last_delivery_sequence INTO snap FROM public.notification_center_user_state WHERE organization=org AND recipient=a;
 UPDATE public.notification_center_events SET attention_revision=2,kind='capacity_full' WHERE id=revision_event;
 PERFORM public.notification_center_capture_recipients_internal(revision_event,NULL);
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_visible_internal(org,snap,oc) x WHERE (x.event).id=revision_event),1::bigint,'old bound still locates earlier delivery after escalation');
 PERFORM assert_eq((SELECT (x.delivery).attention_revision FROM public.notification_center_visible_internal(org,snap,oc) x WHERE (x.event).id=revision_event),1::bigint,'delivery revision is pinned while current event kind stays live');
 UPDATE public.notification_center_events SET status='recovered' WHERE id=revision_event;
 PERFORM assert_false(public.notification_center_in_center_internal((SELECT e FROM public.notification_center_events e WHERE id=revision_event),anchor+interval '31 days'),'ordinary activity expires at fresh anchor');
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 PERFORM assert_eq((SELECT seen_through_sequence FROM public.notification_center_user_state WHERE organization=org AND recipient=b),0::bigint,'other recipient was never acknowledged');
 PERFORM assert_true((public.get_notification_center_badge(org)->>'unread')::boolean,'other recipient stays unread');
END $$;
ROLLBACK;
