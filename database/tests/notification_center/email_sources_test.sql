-- test-setup: database/tests/helpers/prepared_notification_view.sql
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
CREATE FUNCTION pg_temp.assert_prepared_families(p_org bigint,p_oc bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v jsonb; k text; expected bigint; actual bigint;
BEGIN
 PERFORM public.project_notification_center(500);
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 v:=public.get_notification_center_view(p_org,p_oc);
 FOR i IN 1..30 LOOP PERFORM public.prepare_notification_center(100);PERFORM public.prepare_notification_center_views(100);END LOOP;
 v:=public.get_notification_center_view(p_org,p_oc);
 PERFORM assert_eq(v->>'state','ready','actual producers reach prepared ready');
 FOR k IN SELECT DISTINCT kind FROM public.notification_center_events WHERE organization=p_org LOOP
  SELECT count(*) INTO expected FROM public.notification_center_events e
  WHERE e.organization=p_org AND e.kind=k AND e.kind<>'order_payment_received' AND public.notification_center_in_center_internal(e,clock_timestamp())
   AND public.notification_center_allowed(e,p_user) AND EXISTS(SELECT 1 FROM public.notification_center_deliveries d WHERE d.event_id=e.id AND d.recipient=p_user);
  SELECT coalesce(sum(coalesce((x#>>'{data,activityCount}')::bigint,(x#>>'{data,eventCount}')::bigint,1)),0) INTO actual
   FROM jsonb_array_elements(v->'items') x WHERE x->>'kind'=k AND x->>'state'='ready';
  PERFORM assert_eq(actual,expected,'prepared real producer count: '||k);
 END LOOP;
 PERFORM public.get_notification_center_view(p_org,p_oc,p_mode=>'close_all');
END $$;
DO $$
DECLARE target_order bigint; org bigint; un bigint; oc bigint; editor uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); kind text; msg jsonb; message_uuid uuid; old_id uuid; n bigint; result jsonb; paused_fact timestamptz; event_row public.notification_center_events; delivery_row public.notification_center_deliveries;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Email inbox ACL') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Email unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Email event',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(editor),(admin);
 INSERT INTO public.user_info(id,organization) VALUES(editor,org),(admin,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,editor,true);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,admin,true);
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'old@example.invalid','{}','preactivation');old_id:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET bounced_at=clock_timestamp()-interval '1 hour' WHERE message_id=old_id;
 PERFORM public.initialize_notification_center_internal(org);
 PERFORM public.notification_center_email_internal(old_id);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),0::bigint,'existing bounce baseline is silent');
 FOREACH kind IN ARRAY ARRAY['order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer'] LOOP
  msg:=public.enqueue_email(kind,jsonb_build_object('organization',org,'occasion',CASE WHEN kind IN ('registration','sign_in','reset_password','deletion_confirm','deletion_complete','google_mailbox','gotrue') THEN NULL ELSE oc END),kind||'@example.invalid','{}',kind);
  message_uuid:=(msg->>'message_id')::uuid;
  UPDATE public.email_messages SET workflow_state='accepted',accepted_at=clock_timestamp(),delivered_at=clock_timestamp(),bounced_at=clock_timestamp() WHERE message_id=message_uuid;
  PERFORM public.notification_center_email_internal(message_uuid);PERFORM public.notification_center_email_internal(message_uuid);
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org),17::bigint,'all message kinds generate a single problem');
 PERFORM public.project_notification_center(100);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org AND recipient=editor),10::bigint,'editor cannot read security messages');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_deliveries WHERE organization=org AND recipient=admin),17::bigint,'tenant admin receives all authorized kinds');
 PERFORM set_config('request.jwt.claim.sub',admin::text,true);
 result:=pg_temp.prepared_notification_view(org);
 PERFORM assert_eq(jsonb_array_length(result->'items'),17,'prepared incidents retain one actionable item per message');
 PERFORM assert_eq((SELECT count(*) FROM jsonb_array_elements(result->'items') g WHERE (g->>'occasionId')::bigint=oc),10::bigint,'occasion incidents retain exact message scope');
 UPDATE public.user_info SET name='Jana',surname='Nováková' WHERE id=admin;
 UPDATE public.email_messages SET recipient_user=admin WHERE message_id=message_uuid;
 SELECT * INTO event_row FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid;
 SELECT * INTO delivery_row FROM public.notification_center_deliveries WHERE event_id=event_row.id AND recipient=admin LIMIT 1;
 result:=public.notification_center_dto(event_row,delivery_row);
 PERFORM assert_eq(result#>>'{data,recipient}','waitlist_offer@example.invalid','authorized email DTO identifies the actual recipient');
 PERFORM assert_eq(result#>>'{data,customerName}','Jana Nováková','available recipient name is hydrated');
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"snapshot@example.invalid"}') RETURNING id INTO target_order;
 UPDATE public.email_messages m SET order_id=o.id FROM eshop.orders o WHERE m.message_id=message_uuid AND o.id=target_order;
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 result:=public.notification_center_dto(event_row,delivery_row);
 PERFORM assert_eq(result#>>'{data,orderId}',target_order::text,'authorized source exposes exact order target');
 PERFORM assert_eq(result#>>'{data,orderSymbol}',(SELECT order_symbol FROM eshop.orders WHERE id=target_order),'order symbol comes from the same join');
 PERFORM set_config('request.jwt.claim.sub',admin::text,true);

 event_row.data:=event_row.data||jsonb_build_object('messageId',(SELECT message_id FROM public.email_messages WHERE organization=org AND message_kind='registration'));
 result:=public.notification_center_dto(event_row,delivery_row);
 PERFORM assert_false((result->'data') ? 'recipient','message from a different occasion scope cannot leak its recipient');
 UPDATE public.email_messages SET complained_at=clock_timestamp() WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);PERFORM public.notification_center_email_internal(message_uuid);PERFORM public.project_notification_center(100);
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),2::bigint,'new complaint impact advances once');
 -- A late old provider fact is not a new incident.
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'late@example.invalid','{}','late');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET bounced_at=clock_timestamp()-interval '1 day' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'late preactivation webhook is excluded');
 -- Scheduled messages use due time, not creation time.
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'scheduled@example.invalid','{}','scheduled');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET target_time=clock_timestamp()+interval '1 day',created_at=clock_timestamp()-interval '2 days' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'future schedule not delayed');
 -- An incident after activation remains new even for a message created earlier.
 UPDATE public.email_messages SET complained_at=clock_timestamp() WHERE message_id=old_id;
 PERFORM public.notification_center_email_internal(old_id);
 PERFORM assert_eq((SELECT data->>'reason' FROM public.notification_center_events WHERE organization=org AND source_key='email:'||old_id),'complaint'::text,'old message new failure is included');
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'delayed@example.invalid','{}','delay');message_uuid:=(msg->>'message_id')::uuid;
 PERFORM public.notification_center_email_internal(message_uuid,clock_timestamp()+interval '10 minutes');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'brief pending is not an incident');
 PERFORM public.notification_center_email_internal(message_uuid,clock_timestamp()+interval '31 minutes');
 PERFORM assert_eq((SELECT data->>'reason' FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),'delayed'::text,'overdue threshold is from due time');
 UPDATE public.email_messages SET workflow_state='cancelled' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),1::bigint,'cancelled intent does not add attention');
 INSERT INTO public.email_suppressions(recipient,reason,created_at) VALUES('expected@example.invalid','hard_bounce',clock_timestamp()-interval '1 day');
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'expected@example.invalid','{}','expected-suppression');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='suppressed' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'known suppression is expected');
 -- Retry scheduling must not move the original attention deadline.
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'retry@example.invalid','{}','retry-due');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='retry_wait',target_time=clock_timestamp()+interval '2 hours' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid,clock_timestamp()+interval '31 minutes');
 PERFORM assert_eq((SELECT data->>'reason' FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),'delayed'::text,'retry scheduling preserves original due attention');
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'unexpected@example.invalid','{}','unexpected-suppression');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='suppressed' WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT data->>'reason' FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),'suppressed'::text,'unexpected suppression is included');
 -- Real shared reducer path: delivery followed by a late bounce, replay, then complaint.
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'reducer@example.invalid','{}','reducer-events');message_uuid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='accepted',provider_message_id='notification-'||message_uuid WHERE message_id=message_uuid;
 PERFORM public.record_email_event(jsonb_build_object('key','notification-delivery-'||message_uuid,'provider_id','notification-'||message_uuid,'recipient','reducer@example.invalid','type','delivery','time',clock_timestamp()));
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'delivery is not an incident');
 FOR i IN 1..2 LOOP
  PERFORM public.record_email_event(jsonb_build_object('key','notification-bounce-'||message_uuid,'provider_id','notification-'||message_uuid,'recipient','reducer@example.invalid','type','bounce','time',clock_timestamp(),'hard_bounce',true));
 END LOOP;
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),1::bigint,'late bounce goes through reducer once despite earlier delivery and replay');
 PERFORM public.record_email_event(jsonb_build_object('key','notification-complaint-'||message_uuid,'provider_id','notification-'||message_uuid,'recipient','reducer@example.invalid','type','complaint','time',clock_timestamp()));
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),2::bigint,'real reducer adds complaint impact to same message');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND (data ? 'recipient' OR data ? 'body' OR data ? 'token')),'projections contain no mail content or recipients');
 PERFORM pg_temp.assert_prepared_families(org,oc,admin);
END $$;
ROLLBACK;
