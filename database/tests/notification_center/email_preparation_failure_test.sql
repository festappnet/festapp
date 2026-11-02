BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; actor uuid:=gen_random_uuid(); mid uuid; msg jsonb;
 attempt uuid:=gen_random_uuid(); token uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.organizations(title) VALUES('Email preparation alert') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Email unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Email event',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,actor,true);
 PERFORM public.initialize_notification_center_internal(org);
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc),'test@example.invalid','{}',gen_random_uuid()::text);
 mid:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET workflow_state='preparing',lease_token=token,lease_until=now()+interval '1 minute' WHERE message_id=mid;
 INSERT INTO public.email_attempts(attempt_id,message_id,lease_token,state) VALUES(attempt,mid,token,'preparing');
 PERFORM public.finish_email_attempt(attempt,token,'preparation_failed',NULL,'preparation_failed');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid AND kind='email_problem' AND data->>'reason'='rendering_failure' AND status='active'),'preparation failure alerts immediately while retry is pending');
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid),1::bigint,'same failure does not duplicate alerts');
 UPDATE public.email_messages SET workflow_state='accepted',last_error=NULL,accepted_at=clock_timestamp() WHERE message_id=mid;
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid AND status='recovered'),'successful retry recovers alert');
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc),'test@example.invalid','{}',gen_random_uuid()::text);
 mid:=(msg->>'message_id')::uuid;
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid),'newly queued email is not an incident');
 UPDATE public.email_messages SET workflow_state='retry_wait',last_error='throttled' WHERE message_id=mid;
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid),'brief provider throttling retains grace period');
 UPDATE public.email_messages SET last_error='provider_unavailable' WHERE message_id=mid;
 PERFORM public.notification_center_email_internal(mid);
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND source_key='email:'||mid AND data->>'reason'='delayed'),'actual send failure alerts before retry');
END $$;
ROLLBACK;
