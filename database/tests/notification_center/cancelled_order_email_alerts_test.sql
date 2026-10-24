BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; other_oid bigint; actor uuid:=gen_random_uuid();
 msg jsonb; mid uuid; other_mid uuid; late_mid uuid; cancellation_mid uuid; revision bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Cancelled email recovery') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Email unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Email event',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 PERFORM public.set_notification_center_activation(org,true);
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered','{"email":"bad@example.invalid"}') RETURNING id INTO oid;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered','{"email":"other@example.invalid"}') RETURNING id INTO other_oid;
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc),'bad@example.invalid','{}','cancel-recovery');
 mid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',bounced_at=clock_timestamp() WHERE message_id=mid;
 PERFORM public.notification_center_email_internal(mid);
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc),'other@example.invalid','{}','other-recovery');
 other_mid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=other_oid,workflow_state='accepted',bounced_at=clock_timestamp() WHERE message_id=other_mid;
 PERFORM public.notification_center_email_internal(other_mid);
 PERFORM assert_true(jsonb_array_length(public.order_email_current_issues(oid))>0,'before cancellation the email warning is active');
 SELECT attention_revision INTO revision FROM public.notification_center_events WHERE source_key='email:'||mid;
 PERFORM public.cancel_order_domain_internal_v1(oid,false);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno'::text,'real cancellation transition completed');
 PERFORM assert_eq(public.order_email_current_issues(oid),'[]'::jsonb,'cancelled order has no actionable email warning');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||mid),'recovered'::text,'cancellation retires the existing notification atomically');
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||other_mid),'active'::text,'other order incident is unaffected');
 PERFORM assert_true((SELECT bounced_at IS NOT NULL FROM public.email_messages WHERE message_id=mid),'provider failure audit is retained');
 UPDATE public.email_messages SET complained_at=clock_timestamp() WHERE message_id=mid;
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||mid),'recovered'::text,'late provider fact must not reactivate the cancelled recovery');
 PERFORM assert_eq((SELECT attention_revision FROM public.notification_center_events WHERE source_key='email:'||mid),revision,'late fact creates no new attention');
 msg:=public.enqueue_email('order_tickets',jsonb_build_object('organization',org,'occasion',oc),'bad@example.invalid','{}','late-original');
 late_mid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',bounced_at=clock_timestamp() WHERE message_id=late_mid;
 PERFORM public.notification_center_email_internal(late_mid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE source_key='email:'||late_mid),0::bigint,'late original failure after cancellation creates no incident');
 msg:=public.enqueue_email('order_storno',jsonb_build_object('organization',org,'occasion',oc),'bad@example.invalid','{}','cancel-notice');
 cancellation_mid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',bounced_at=clock_timestamp() WHERE message_id=cancellation_mid;
 PERFORM public.notification_center_email_internal(cancellation_mid);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||cancellation_mid),'active'::text,'a new failed cancellation email remains a separate incident');
 PERFORM public.cancel_order_domain_internal_v1(oid,false);
 PERFORM assert_eq((SELECT status FROM public.notification_center_events WHERE source_key='email:'||mid),'recovered'::text,'cancellation replay leaves the original recovery resolved');
END $$;
ROLLBACK;
