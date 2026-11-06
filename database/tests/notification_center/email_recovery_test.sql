-- test-setup: database/functions/notification_center/email.sql
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; actor uuid:=gen_random_uuid();
 original uuid; tickets uuid; independent uuid; msg jsonb; result jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Email recovery') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Email unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,un,'Email recovery',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 PERFORM public.initialize_notification_center_internal(org);
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'paid','{"email":"fixed@example.invalid"}') RETURNING id INTO oid;
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc),'typo@example.invalid','{}','original');
 original:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',bounced_at=clock_timestamp() WHERE message_id=original;
 PERFORM public.notification_center_email_internal(original);
 msg:=public.enqueue_email('order_update',jsonb_build_object('organization',org,'occasion',oc),'fixed@example.invalid','{}','independent');
 independent:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='dead' WHERE message_id=independent;
 PERFORM public.notification_center_email_internal(independent);
 msg:=public.enqueue_email('order_tickets',jsonb_build_object('organization',org,'occasion',oc),'typo@example.invalid','{}','tickets');
 tickets:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=oid),
  workflow_state='accepted',accepted_at=clock_timestamp(),delivered_at=clock_timestamp() WHERE message_id=tickets;
 PERFORM public.notification_center_email_internal(tickets);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||original),'active'::text,'delivery to stale contact cannot resolve');
 UPDATE public.email_messages SET recipient='fixed@example.invalid',delivered_at=NULL,opened_at=clock_timestamp() WHERE message_id=tickets;
 PERFORM public.notification_center_email_internal(tickets);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||original),'active'::text,'acceptance and open tracking cannot resolve');
 PERFORM public.project_notification_center(100);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 result:=public.get_notification_center_view(org,oc);
 FOR i IN 1..30 LOOP PERFORM public.prepare_notification_center(100);PERFORM public.prepare_notification_center_views(100);END LOOP;
 result:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(result->>'state','ready','original incident is prepared before delivery');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'items') x WHERE x->>'id'=(SELECT id::text FROM public.notification_center_events WHERE source_key='email:'||original)),'original incident is initially visible');
 PERFORM public.get_notification_center_view(org,oc,p_mode=>'close_all');
 UPDATE public.email_messages SET provider_message_id='recovered:'||tickets WHERE message_id=tickets;
 PERFORM public.record_email_event(jsonb_build_object('key','delivery:'||tickets,'provider_id','recovered:'||tickets,
  'recipient','fixed@example.invalid','type','delivery','time',clock_timestamp()));
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||original),'recovered'::text,'delivered current tickets retire obsolete confirmation alert');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||independent),'active'::text,'independent failure remains actionable');
 PERFORM assert_true((SELECT pending_events>0 FROM public.notification_center_projection_scopes WHERE organization=org AND recipient=actor),'recovery invalidates the prepared projection');
 PERFORM public.notification_center_email_internal(original);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||original),'recovered'::text,'old callback cannot restore resolved alert');
 PERFORM assert_true((SELECT bounced_at IS NOT NULL FROM public.email_messages WHERE message_id=original),'original failure remains in audit');
 PERFORM public.project_notification_center(100);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 result:=public.get_notification_center_view(org,oc);
 FOR i IN 1..30 LOOP PERFORM public.prepare_notification_center(100);PERFORM public.prepare_notification_center_views(100);END LOOP;
 result:=public.get_notification_center_view(org,oc);
 PERFORM assert_eq(result->>'state','ready','recovered projection is ready');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'items') x WHERE x->>'id'=(SELECT id::text FROM public.notification_center_events WHERE source_key='email:'||original)),'resolved alert is absent from center');
END $$;
ROLLBACK;
