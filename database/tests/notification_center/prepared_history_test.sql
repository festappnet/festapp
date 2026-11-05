BEGIN;
DO $$
DECLARE org bigint;oc bigint;viewer uuid:=gen_random_uuid();oid bigint;v jsonb;before_read jsonb;scope jsonb;token uuid;row jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Prepared inherited read ranges') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Inherited history',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '60 days');
 FOR i IN 1..10 LOOP
  INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data) VALUES(oc,'ordered',public.generate_order_symbol(),i,jsonb_build_object('email','buyer'||i||'@example.invalid')) RETURNING id INTO oid;
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','range:'||i,jsonb_build_object('orderId',oid,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)));
 END LOOP;
 PERFORM public.project_notification_center(500);
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 SELECT org,viewer,'occasion-kind:'||oc||':order_created',sequence-1,sequence FROM public.notification_center_deliveries
  WHERE organization=org AND recipient=viewer AND sequence%2=0;
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 v:=public.get_notification_center_view(org,oc);
 FOR i IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 v:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(v->>'state','ready','gapped inherited receipts have a complete prepared catalog');
 SELECT value INTO row FROM jsonb_array_elements(v->'items') WHERE value->>'isRead'='false';
 PERFORM assert_eq((row#>>'{data,activityCount}')::int,5,'old unread holes remain exactly counted');
 scope:=jsonb_build_object('viewToken',v->>'viewToken','id',row->>'id','organization',org);
 PERFORM assert_eq(jsonb_array_length(public.notification_center_order_selection(oc,scope)),5,'selection includes captured holes and excludes captured read singletons');
 PERFORM assert_true(public.mark_notification_center_view_item_read(org,scope),'modern read seals all captured holes without changing older receipts');
 PERFORM assert_true(public.mark_notification_center_view_item_read(org,scope),'repeat read is idempotent');
 FOR i IN 1..30 LOOP PERFORM public.prepare_notification_center(100);PERFORM public.prepare_notification_center_views(100);END LOOP;
 before_read:=public.get_notification_center_view(org,oc,p_mode=>'refresh',p_view=>(v->>'viewToken')::uuid);
 SELECT value INTO row FROM jsonb_array_elements(before_read->'items') WHERE value->>'id'=scope->>'id';
 PERFORM assert_eq((row#>>'{data,activityCount}')::int,5,'frozen capture still contains exactly its original unread members');
 PERFORM assert_eq(row->>'isRead','true','all captured holes are read');
 PERFORM assert_eq(jsonb_array_length(public.notification_center_order_selection(oc,scope)),5,'frozen selection survives new read receipts');
END $$;
DO $$
DECLARE org bigint;oc bigint;viewer uuid:=gen_random_uuid();oid bigint;v jsonb;item jsonb;scope jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Own and legacy token selection') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Own activity',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization) VALUES(org);
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data) VALUES(oc,'storno',public.generate_order_symbol(),1,'{"name":"Jana","email":"jana@example.invalid"}') RETURNING id INTO oid;
 PERFORM public.notification_center_publish_internal(org,oc,'order_cancelled','own-cancelled',jsonb_build_object('orderId',oid,'count',1,'formContext',jsonb_build_object('allowsMultiple',true)),viewer);
 PERFORM public.project_notification_center(500);PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 v:=public.get_notification_center_view(org,oc);FOR i IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 v:=public.get_notification_center_view(org,oc);item:=v#>'{items,0}';
 PERFORM assert_true(item->>'id' LIKE '%:history:read','modern self ID remains opaque');
 scope:=jsonb_build_object('viewToken',v->>'viewToken','id',item->>'id','organization',org);
 PERFORM assert_eq(public.notification_center_order_selection(oc,scope),to_jsonb(ARRAY[oid]),'own cancelled selection uses server group key, not legacy ID parsing');
 -- A separately inherited global-read baseline uses the same server scope owner.
 PERFORM public.get_notification_center_view(org,oc,p_mode=>'close_all');
 UPDATE public.notification_center_events SET actor=NULL WHERE organization=org;
 UPDATE public.notification_center_user_state SET read_through_sequence=last_delivery_sequence WHERE organization=org AND recipient=viewer;
 DELETE FROM public.notification_center_projection_scopes WHERE organization=org AND recipient=viewer;
 v:=public.get_notification_center_view(org,oc);FOR i IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 v:=public.get_notification_center_view(org,oc);item:=v#>'{items,0}';
 PERFORM assert_true(item->>'id' LIKE '%:history:read','modern legacy-read ID remains opaque');
 scope:=jsonb_build_object('viewToken',v->>'viewToken','id',item->>'id','organization',org);
 PERFORM assert_eq(public.notification_center_order_selection(oc,scope),to_jsonb(ARRAY[oid]),'legacy-read token selection resolves the same canonical order');
END $$;
ROLLBACK;
