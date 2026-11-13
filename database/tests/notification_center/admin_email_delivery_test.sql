BEGIN;
DO $$
DECLARE org1 bigint; org2 bigint; oc bigint; oid bigint; form bigint; u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid();
 dispatch uuid; first_due timestamptz; result jsonb; context jsonb; message uuid; facts jsonb; event public.notification_center_events;
 recipient_count integer; attempt uuid; token uuid; before_usage bigint; duplicate_rejected boolean; explain jsonb; sql_body text; violated text;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Pořadatel A','{"DEFAULT_URL":"https://a.example.test"}') RETURNING id INTO org1;
 INSERT INTO public.organizations(title,data) VALUES('Pořadatel B','{"DEFAULT_URL":"https://b.example.test"}') RETURNING id INTO org2;
 INSERT INTO auth.users(id) VALUES(u),(v);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(u,org1,'shared@example.test'),(v,org1,'shared@example.test');
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org1,now()-interval '1 day'),(org2,now()-interval '1 day');
 UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000;
 PERFORM public.activate_notification_center_emails(org1); PERFORM public.activate_notification_center_emails(org2);
 FOR j IN 1..3 LOOP
  INSERT INTO public.occasions(organization,title,link,start_time,end_time)
   VALUES(CASE WHEN j=3 THEN org2 ELSE org1 END,'Ples '||j,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,u,true),(oc,v,true);
 END LOOP;
 PERFORM assert_eq(extract(epoch FROM public.notification_center_email_window_internal())::integer,300,'single product policy defines the fixed window');
 -- Explicit self settings create the only email profile; no implicit enrollment.
 FOREACH dispatch IN ARRAY ARRAY[u,v] LOOP
  PERFORM set_config('request.jwt.claim.sub',dispatch::text,true);
  PERFORM public.save_notification_center_email_settings(org1,NULL,0,false,'cs','{"order_created":true,"order_payment_received":true}');
  PERFORM public.save_notification_center_email_settings(org2,NULL,1,false,'cs','{"order_created":true,"order_payment_received":true}');
 END LOOP;
 PERFORM assert_eq((public.notification_center_email_settings_internal(org1)->>'windowSeconds')::integer,300,'settings UI receives the same server policy');
 FOR oc IN SELECT id FROM public.occasions WHERE organization IN (org1,org2) LOOP
  INSERT INTO public.forms(occasion,title) VALUES(oc,'Vstupenky') RETURNING id INTO form;
  FOR j IN 1..10 LOOP
   INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data) VALUES(oc,form,'ordered',public.generate_order_symbol(),j,'{}') RETURNING id INTO oid;
   PERFORM public.notification_center_order_internal(oid,'order_created',j::text,NULL);
  END LOOP;
 END LOOP;
 PERFORM public.project_notification_center(500);
 PERFORM assert_eq(public.collect_notification_center_emails(100),2,'two recipient identities are processed independently');
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_email_items WHERE recipient=u),30,'all three occasions included');
 SELECT id,due_at INTO dispatch,first_due FROM public.notification_center_email_dispatches WHERE recipient=u;
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),0,'no send before 300 seconds');
 PERFORM assert_eq(public.collect_notification_center_emails(100),0,'cursor replay is idle');
 PERFORM assert_eq((SELECT due_at FROM public.notification_center_email_dispatches WHERE id=dispatch),first_due,'deadline never extends');
 context:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM assert_eq(jsonb_array_length(context->'items'),30,'context works without opening the UI');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE recipient=u),'email does not create UI backfill');
 -- Captured facts win even if ticket access would throw. UI and mail share them.
 SELECT * INTO event FROM public.notification_center_events WHERE organization=org1 AND kind='order_created' LIMIT 1;
 event.data:=event.data||'{"count":7,"formContext":{"allowsMultiple":true}}';
 facts:=public.notification_center_event_facts_internal(event);
 PERFORM assert_eq((facts->>'count')::int,7,'captured count is authoritative');
 -- Both consumers still work when the ticket relation cannot be resolved.
 -- Captured facts must never execute the legacy COUNT branch.
 ALTER TABLE eshop.order_product_ticket RENAME TO notification_reuse_ticket_probe;
 EXECUTE 'DISCARD PLANS';
 PERFORM assert_eq((public.notification_center_event_facts_internal(event)->>'count')::int,7,'captured facts do not require ticket lookup');
 PERFORM public.notification_center_dto(event,(SELECT d FROM public.notification_center_deliveries d WHERE d.event_id=event.id AND d.recipient=u LIMIT 1));
 PERFORM assert_eq(jsonb_array_length(public.notification_center_email_context_internal(dispatch,u)->'items'),30,'email preparation never reconstructs ticket counts');
 SELECT p.prosrc INTO sql_body FROM pg_proc p WHERE p.oid='public.notification_center_email_context_internal(uuid,uuid)'::regprocedure;
 sql_body:=replace(replace(sql_body,'p_dispatch','$1'),'p_recipient','$2');
 EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) '||sql_body INTO explain USING dispatch,u;
 PERFORM assert_true(explain::text LIKE '%CTE scopes%' AND explain::text LIKE '%CTE metadata%' AND explain::text LIKE '%CTE facts%','setwise distinct scopes, metadata and facts are materialized in the actual context plan');
 ALTER TABLE eshop.notification_reuse_ticket_probe RENAME TO order_product_ticket;
 -- A source cursor gap does not invent work or stall the next scan.
 UPDATE public.notification_center_user_state SET last_delivery_sequence=last_delivery_sequence+3 WHERE recipient=u;
 PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.notification_center_user_state WHERE recipient=u AND email_scanned_sequence<>last_delivery_sequence),'cursor crosses only empty gaps');
 UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE recipient IN(u,v);
 PERFORM assert_eq(public.enqueue_notification_center_emails(100),2,'one queue message per recipient across tenants');
 SELECT message_id INTO message FROM public.notification_center_email_dispatches WHERE id=dispatch;
 PERFORM assert_eq((SELECT count(*)::int FROM public.email_messages WHERE recipient_user=u),1,'one message across three events');
 PERFORM assert_true((SELECT organization IS NULL AND admission_class='notification' AND tracking_policy='disabled' FROM public.email_messages WHERE message_id=message),'private scope and bounded notification class');
 result:=public.enqueue_email('admin_notification_digest',jsonb_build_object('recipient_user',u),'shared@example.test',jsonb_build_object('dispatchId',dispatch,'templateVersion',1),'notification:'||dispatch,'ADMIN_NOTIFICATION_DIGEST');
 PERFORM assert_true((result->>'replayed')::boolean AND (result->>'message_id')::uuid=message,'lost enqueue response replays same message');
 BEGIN
  PERFORM public.enqueue_email('admin_notification_digest',jsonb_build_object('recipient_user',u),'shared@example.test',jsonb_build_object('dispatchId',dispatch,'templateVersion',2),'notification:'||dispatch,'ADMIN_NOTIFICATION_DIGEST');
  RAISE EXCEPTION 'expected hash conflict';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_dedupe_conflict' THEN RAISE; END IF; END;
 -- Revocation removes tenant A in the same owner used at preparation and permit.
 DELETE FROM public.occasion_users WHERE "user"=u AND occasion IN(SELECT id FROM public.occasions WHERE organization=org1);
 result:=public.notification_center_email_context_internal(dispatch,u);
 PERFORM assert_eq(jsonb_array_length(result->'items'),10,'revoked tenant is removed, other tenant survives');
 PERFORM assert_true(result->>'fingerprint'<>context->>'fingerprint','privacy changes invalidate prepared content');
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 BEGIN PERFORM public.get_email_delivery_detail(message); RAISE EXCEPTION 'expected private report rejection';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_read_denied' THEN RAISE; END IF; END;
 -- Every independent uniqueness/scope constraint is exercised by a direct write.
 BEGIN INSERT INTO public.notification_center_email_dispatches(recipient,opened_at,due_at) VALUES(u,now(),now()+interval '300 seconds'),(u,now(),now()+interval '300 seconds'); RAISE EXCEPTION 'expected collecting unique'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO public.notification_center_email_items SELECT * FROM public.notification_center_email_items WHERE recipient=u LIMIT 1; RAISE EXCEPTION 'expected item PK'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO public.notification_center_email_item_sources SELECT * FROM public.notification_center_email_item_sources WHERE recipient=u LIMIT 1; RAISE EXCEPTION 'expected source PK'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN UPDATE public.notification_center_email_items SET dispatch_id=dispatch WHERE recipient=v; RAISE EXCEPTION 'expected recipient FK'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE public.notification_center_email_item_sources SET organization=org2 WHERE recipient=u AND organization=org1; RAISE EXCEPTION 'expected source scope FK'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE public.email_messages SET organization=NULL WHERE message_kind<>'admin_notification_digest';
  INSERT INTO public.email_messages(target_time,code,data,organization,message_kind,dedupe_key,input_hash) VALUES(now(),'x','{}',NULL,'custom','bad','bad'); RAISE EXCEPTION 'expected scope CHECK'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM assert_false(EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notification_center_email_subscriptions' AND column_name='occasion'),'subscription storage has no occasion override');
 BEGIN UPDATE public.notification_center_user_state SET email_scanned_sequence=last_delivery_sequence+1 WHERE recipient=u; RAISE EXCEPTION 'expected cursor CHECK'; EXCEPTION WHEN check_violation THEN NULL; END;

 BEGIN INSERT INTO public.notification_center_email_subscriptions(recipient,organization,kinds) VALUES(u,org1,'{}'); RAISE EXCEPTION 'expected subscription unique'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN UPDATE public.notification_center_email_dispatches SET due_at=due_at+interval '1 second' WHERE id=dispatch; RAISE EXCEPTION 'expected fixed deadline'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE public.notification_center_email_dispatches SET message_id=message WHERE recipient=v; RAISE EXCEPTION 'expected unique queue link'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN UPDATE public.notification_center_email_item_sources SET first_sequence=first_sequence+10000 WHERE recipient=u; RAISE EXCEPTION 'expected delivery FK'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  INSERT INTO public.email_messages(target_time,code,data,message_kind,dedupe_key,input_hash,recipient_user,notification_dispatch_id,workflow_state)
   SELECT now(),code,data,message_kind,dedupe_key,input_hash,recipient_user,notification_dispatch_id,'accepted' FROM public.email_messages WHERE message_id=message;
  RAISE EXCEPTION 'expected recipient dedupe';
 EXCEPTION WHEN unique_violation THEN GET STACKED DIAGNOSTICS violated=CONSTRAINT_NAME; PERFORM assert_eq(violated,'email_notification_dedupe','recipient replay has an exact DB dedupe index'); END;
 BEGIN
  INSERT INTO public.email_messages(target_time,code,data,message_kind,dedupe_key,input_hash,recipient_user,notification_dispatch_id,workflow_state)
   SELECT now(),code,data,message_kind,'new-attempt-identity',input_hash,recipient_user,notification_dispatch_id,'pending' FROM public.email_messages WHERE message_id=message;
  RAISE EXCEPTION 'expected active recipient unique';
 EXCEPTION WHEN unique_violation THEN GET STACKED DIAGNOSTICS violated=CONSTRAINT_NAME; PERFORM assert_eq(violated,'email_notification_active','one active recipient intent is enforced by the DB'); END;
 BEGIN
  INSERT INTO public.email_messages(target_time,code,data,message_kind,dedupe_key,input_hash,recipient_user,notification_dispatch_id,workflow_state)
   SELECT now(),code,data,message_kind,'wrong-recipient',input_hash,v,notification_dispatch_id,'accepted' FROM public.email_messages WHERE message_id=message;
  RAISE EXCEPTION 'expected queue dispatch recipient FK';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;

 UPDATE public.notification_center_organizations SET initialized_at=now()-interval '3 days',email_collection_started_at=now()-interval '3 days' WHERE organization=org2;
 UPDATE public.notification_center_email_subscriptions SET enabled_from=now()-interval '3 days',kinds=jsonb_set(kinds,'{order_created,enabledFrom}',to_jsonb((now()-interval '3 days')::text)) WHERE recipient=u AND organization=org2;
 PERFORM public.notification_center_publish_internal(org2,(SELECT id FROM public.occasions WHERE organization=org2 LIMIT 1),'order_created','expired-catch-up','{"count":1,"formContext":{"allowsMultiple":false}}',NULL,now()-interval '25 hours');
 PERFORM public.project_notification_center(500);PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_eq((SELECT count(*)::int FROM public.notification_center_email_items WHERE recipient=u),30,'ordinary catch-up over 24 hours is skipped');
 PERFORM public.collect_notification_center_emails(100);
 PERFORM assert_true((SELECT last_deferred>0 FROM public.notification_center_maintenance WHERE name='email-collection'),'expired catch-up is visible as a metric');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.collect_notification_center_emails(integer)','EXECUTE'),'collect service only');
 PERFORM assert_true(NOT has_table_privilege('authenticated','public.notification_center_email_dispatches','SELECT'),'private envelope has no client grant');
END $$;
ROLLBACK;
