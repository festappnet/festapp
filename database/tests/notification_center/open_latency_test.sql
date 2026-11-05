-- test-setup: database/functions/notification_center/subject_visibility.sql
-- test-setup: database/functions/notification_center/center_policy.sql
BEGIN;
DO $$
DECLARE org bigint; oc bigint; oid bigint; viewer uuid:=gen_random_uuid(); hidden uuid:=gen_random_uuid();
 result jsonb; warm jsonb; started timestamptz; elapsed_ms numeric;
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
 -- Real publication and delivery, including 1000 sealed personal read batches.
 FOR i IN 1..2000 LOOP
  PERFORM public.notification_center_publish_internal(org,oc,'order_created','latency:'||i,
   jsonb_build_object('orderId',oid,'count',2,'formContext',jsonb_build_object('allowsMultiple',true)),NULL,now()-interval '1 day'+i*interval '1 millisecond');
 END LOOP;
 FOR i IN 1..40 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND projected_revision<attention_revision);
  PERFORM public.project_notification_center(500);
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org),2000::bigint,'latency fixture delivers every event');
 INSERT INTO public.notification_center_read_batches(organization,recipient,group_key,after_sequence,through_sequence)
 SELECT org,viewer,'occasion-kind:'||oc||':order_created',sequence-1,sequence
 FROM public.notification_center_deliveries WHERE organization=org AND recipient=viewer AND sequence%2=0;
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 FOR i IN 1..2 LOOP
  IF i=2 THEN
   INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,hidden,true);
  END IF;
  -- Legacy arbitrary-time readers remain at their explicit installed-client
  -- boundary. The maintained path's latency gate now measures prepared reads.
  warm:=public.get_notification_center_view(org,oc,p_timezone=>'Europe/Prague');
  FOR pass IN 1..200 LOOP
   PERFORM public.prepare_notification_center(100);
   EXIT WHEN (SELECT phase='ready' AND pending_events=0 AND pending_groups=0 AND NOT privacy_pending
    AND privacy=public.notification_center_prepared_privacy(org) FROM public.notification_center_projection_scopes WHERE organization=org AND recipient=viewer);
  END LOOP;
  started:=clock_timestamp();
  result:=public.get_notification_center_view(org,oc,p_timezone=>'Europe/Prague');
  elapsed_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
  RAISE NOTICE 'notification open (hidden members: %): % ms',i=2,round(elapsed_ms,1);
  PERFORM assert_eq(jsonb_array_length(result->'items'),30,'open hydrates a full page');
  PERFORM assert_eq((result->>'snapshot')::bigint,2000::bigint,'open includes all delivered activity');
  PERFORM assert_eq(result->>'state','ready','latency gate requires a ready nonempty catalog');
  PERFORM assert_true(elapsed_ms<750,'prepared notification open exceeds 750ms: '||round(elapsed_ms,1)||'ms');
  PERFORM public.get_notification_center_view(org,oc,p_mode=>'close',p_view=>(result->>'viewToken')::uuid,p_timezone=>'Europe/Prague');
 END LOOP;
END $$;
ROLLBACK;
