-- test-setup: database/functions/notification_center/subject_visibility.sql
-- test-setup: database/functions/notification_center/center_policy.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; oid bigint; viewer uuid:=gen_random_uuid(); hidden uuid:=gen_random_uuid();
 profile_started timestamptz:=clock_timestamp(); projector_started timestamptz; projection_rounds int; occasions bigint[]; orders bigint[]; result jsonb; warm jsonb; started timestamptz; elapsed_ms numeric;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Notification latency fixture') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer),(hidden);
 INSERT INTO public.user_info(id,organization,email_readonly) VALUES(viewer,org,'viewer@example.invalid'),(hidden,org,'hidden@example.invalid');
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(org,'Notification latency',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '60 days');
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered',public.generate_order_symbol(),1,'{"name":"Jana","email":"buyer@example.invalid"}') RETURNING id INTO oid;
 occasions:=ARRAY[oc];orders:=ARRAY[oid];
 -- Enough distinct occasion groups to keep a full page after history compaction.
 FOR i IN 2..31 LOOP
  INSERT INTO public.occasions(organization,title,link,start_time,end_time)
  VALUES(org,'Latency '||i,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
  INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
  VALUES(oc,'ordered',public.generate_order_symbol(),1,'{"name":"Jana","email":"buyer@example.invalid"}') RETURNING id INTO oid;
  occasions:=array_append(occasions,oc);orders:=array_append(orders,oid);
 END LOOP;
 oc:=occasions[1];
 -- Seed delivered facts in bulk: producer/fanout contracts exercise publication
 -- separately. This gate measures the real prepared read at production cardinality,
 -- not 2000 repeated permission/fanout calls during fixture construction.
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,occurred_at,data,projected_revision)
 SELECT org,occasions[1+(i%31)],'order_created','latency:'||i,
  now()-interval '1 day'+i*interval '1 millisecond',
  jsonb_build_object('orderId',orders[1+(i%31)],'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),1
 FROM generate_series(1,2000) i;
 INSERT INTO public.notification_center_recipients(event_id,recipient,processed_revision,eligible_revision,retry_revision)
 SELECT id,viewer,1,1,1 FROM public.notification_center_events WHERE organization=org;
 INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
 SELECT id,viewer,org,1,row_number() OVER(ORDER BY occurred_at,id),
  occasion||':order_created:'||(occurred_at AT TIME ZONE 'Europe/Prague')::date::text
 FROM public.notification_center_events WHERE organization=org;
 INSERT INTO public.notification_center_user_state(organization,recipient,last_delivery_sequence)
 VALUES(org,viewer,2000);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org),2000::bigint,'latency fixture retains every delivered event');
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 SELECT org,viewer,'occasion-kind:'||e.occasion||':order_created',d.sequence-1,d.sequence
 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=org AND recipient=viewer AND d.sequence%2=0;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_read_batches WHERE organization=org),1000::bigint,'latency fixture retains sealed personal read batches');
 RAISE NOTICE 'TEST_TIMING %',jsonb_build_object('phase','fixture','serverSeconds',extract(epoch FROM clock_timestamp()-profile_started),'events',2000,'readBatches',1000);
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 FOR i IN 1..2 LOOP
  IF i=2 THEN
   INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,hidden,true);
  END IF;
  -- Legacy arbitrary-time readers remain at their explicit installed-client
  -- boundary. The maintained path's latency gate now measures prepared reads.
  warm:=public.get_notification_center_view(org,oc,p_timezone=>'Europe/Prague');
  projector_started:=clock_timestamp(); projection_rounds:=0;
  FOR pass IN 1..200 LOOP
   projection_rounds:=pass;
   PERFORM public.prepare_notification_center(100);
   EXIT WHEN (SELECT phase='ready' AND pending_events=0 AND pending_groups=0 AND NOT privacy_pending
    AND privacy=public.notification_center_prepared_privacy(org) FROM public.notification_center_projection_scopes WHERE organization=org AND recipient=viewer);
  END LOOP;
  RAISE NOTICE 'TEST_TIMING %',jsonb_build_object('phase','projection','serverSeconds',extract(epoch FROM clock_timestamp()-projector_started),'iterations',projection_rounds);
  started:=clock_timestamp();
  result:=public.get_notification_center_view(org,oc,p_timezone=>'Europe/Prague');
  elapsed_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
  RAISE NOTICE 'TEST_TIMING %',jsonb_build_object('phase','asserted-read','serverSeconds',elapsed_ms/1000);
  RAISE NOTICE 'notification open (hidden members: %): % ms',i=2,round(elapsed_ms,1);
  PERFORM assert_eq(jsonb_array_length(result->'items'),30,'open hydrates a full page');
  PERFORM assert_eq((result->>'snapshot')::bigint,2000::bigint,'open includes all delivered activity');
  PERFORM assert_eq(result->>'state','ready','latency gate requires a ready nonempty catalog');
  PERFORM assert_true(elapsed_ms<750,'prepared notification open exceeds 750ms: '||round(elapsed_ms,1)||'ms');
  PERFORM public.get_notification_center_view(org,oc,p_mode=>'close',p_view=>(result->>'viewToken')::uuid,p_timezone=>'Europe/Prague');
 END LOOP;
END $$;
ROLLBACK;
