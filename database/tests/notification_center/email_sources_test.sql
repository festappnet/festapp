BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; editor uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); kind text; msg jsonb; message_uuid uuid; old_id uuid; n bigint; result jsonb; paused_fact timestamptz; event_row public.notification_center_events; delivery_row public.notification_center_deliveries;
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
 PERFORM public.set_notification_center_activation(org,true);
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
 result:=public.open_notification_center(org);
 PERFORM assert_eq(jsonb_array_length(result->'groups'),2,'bulk mail compacts same cause into scoped groups');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'groups') g WHERE (g->>'count')::int=10),'occasion bulk group keeps exact per-message count');
 UPDATE public.user_info SET name='Jana',surname='Nováková' WHERE id=admin;
 UPDATE public.email_messages SET recipient_user=admin WHERE message_id=message_uuid;
 SELECT * INTO event_row FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid;
 SELECT * INTO delivery_row FROM public.notification_center_deliveries WHERE event_id=event_row.id AND recipient=admin LIMIT 1;
 result:=public.notification_center_dto(event_row,delivery_row);
 PERFORM assert_eq(result#>>'{data,recipient}','waitlist_offer@example.invalid','authorized email DTO identifies the actual recipient');
 PERFORM assert_eq(result#>>'{data,customerName}','Jana Nováková','available recipient name is hydrated');
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
 msg:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),'paused@example.invalid','{}','paused-fact');message_uuid:=(msg->>'message_id')::uuid;
 PERFORM public.set_notification_center_activation(org,false);
 paused_fact:=clock_timestamp();
 -- Model a delayed provider fact unavailable to the resume baseline.
 PERFORM public.set_notification_center_activation(org,true);
 UPDATE public.email_messages SET bounced_at=paused_fact WHERE message_id=message_uuid;
 PERFORM public.notification_center_email_internal(message_uuid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||message_uuid),0::bigint,'paused interval is not replayed after resume');
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
END $$;
ROLLBACK;
