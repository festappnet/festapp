BEGIN;
DO $$
DECLARE org bigint;oc bigint;viewer uuid:=gen_random_uuid();oid bigint;v jsonb;row jsonb;
 history jsonb;frozen jsonb;scope jsonb;receipts jsonb;frozen_token uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Historie pořadatele') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Ples pořadatele',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '30 days');
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 FOR i IN 1..3 LOOP
  INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
  VALUES(oc,'ordered',public.generate_order_symbol(),i,jsonb_build_object('name','Host '||i,'email','host'||i||'@example.invalid')) RETURNING id INTO oid;
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','history:'||i,
   jsonb_build_object('orderId',oid,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,now()-make_interval(days=>4-i));
  PERFORM public.project_notification_center(500);
  v:=public.get_notification_center_view(org,oc);
  FOR pass IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
  v:=public.get_notification_center_view(org,oc);
  SELECT value INTO row FROM jsonb_array_elements(v->'items') WHERE value->>'isRead'='false';
  scope:=jsonb_build_object('viewToken',v->>'viewToken','id',row->>'id','organization',org);
  PERFORM assert_true(public.mark_notification_center_view_item_read(org,scope),'read each distinct delivered batch');
  PERFORM public.get_notification_center_view(org,oc,p_mode=>'close_all');
  FOR pass IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 END LOOP;
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO receipts FROM public.notification_center_read_batches b WHERE organization=org;
 PERFORM assert_eq(jsonb_array_length(receipts),3,'canonical read receipts remain distinct');
 v:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(v->'items'),1,'read batches across days occupy one history row');
 history:=v#>'{items,0}';frozen_token:=(v->>'viewToken')::uuid;
 PERFORM assert_eq((history#>>'{data,activityCount}')::int,3,'history has the complete order count');
 scope:=jsonb_build_object('viewToken',v->>'viewToken','id',history->>'id','organization',org);
 PERFORM assert_eq(jsonb_array_length(public.notification_center_order_selection(oc,scope)),3,'history detail selects every captured read order');
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered',public.generate_order_symbol(),4,'{"name":"Nový host","email":"novy@example.invalid"}') RETURNING id INTO oid;
 PERFORM public.notification_center_publish_internal(org,oc,'order_created','history:4',
  jsonb_build_object('orderId',oid,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)));
 PERFORM public.project_notification_center(500);
 FOR pass IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 v:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(v->'items'),2,'new unread activity stays separate from history');
 SELECT value INTO row FROM jsonb_array_elements(v->'items') WHERE value->>'isRead'='false';
 PERFORM assert_eq((row#>>'{data,activityCount}')::int,1,'new unread count excludes history');
 scope:=jsonb_build_object('viewToken',v->>'viewToken','id',row->>'id','organization',org);
 PERFORM public.mark_notification_center_view_item_read(org,scope);
 FOR pass IN 1..30 LOOP PERFORM public.prepare_notification_center(100);PERFORM public.prepare_notification_center_views(100);END LOOP;
 frozen:=public.get_notification_center_view(org,oc,p_mode=>'refresh',p_view=>frozen_token);
 PERFORM assert_eq((frozen#>>'{items,0,data,activityCount}')::int,3,'existing history snapshot does not absorb later reads');
 scope:=jsonb_build_object('viewToken',frozen_token,'id',history->>'id','organization',org);
 PERFORM assert_eq(jsonb_array_length(public.notification_center_order_selection(oc,scope)),3,'frozen history detail excludes later reads too');
 v:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(jsonb_array_length(v->'items'),1,'newly read activity joins existing history');
 PERFORM assert_eq((v#>>'{items,0,data,activityCount}')::int,4,'compacted history retains every order');
 PERFORM assert_eq(v#>>'{items,0,id}',history->>'id','history identity survives later read batches');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(receipts) r WHERE NOT EXISTS(
  SELECT 1 FROM public.notification_center_read_batches b WHERE to_jsonb(b)=r)),'compaction never rewrites canonical read receipts');
END $$;
ROLLBACK;
