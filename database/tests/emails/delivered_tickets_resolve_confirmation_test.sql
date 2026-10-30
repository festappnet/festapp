BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; oid bigint; failed uuid; tickets uuid; msg jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Delivered ticket recovery') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Recovery',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Recovery',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'sent','{"email":"fixed@example.invalid"}') RETURNING id INTO oid;
 msg:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'occasion',oc,'unit',un),'wrong@example.invalid','{}','failed-confirmation');
 failed:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',bounced_at=now()-interval '2 days',created_at=now()-interval '3 days',source_version=0 WHERE message_id=failed;
 msg:=public.enqueue_email('order_tickets',jsonb_build_object('organization',org,'occasion',oc,'unit',un),'fixed@example.invalid','{}','current-tickets');
 tickets:=(msg->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=oid,workflow_state='accepted',accepted_at=now(),source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=oid) WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'acceptance alone does not resolve old confirmation');
 UPDATE public.email_messages SET opened_at=now() WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'opening alone does not resolve old confirmation');
 UPDATE public.email_messages SET delivered_at=now() WHERE message_id=tickets;
 PERFORM assert_eq(public.order_email_current_issues(oid),'[]'::jsonb,'delivered current tickets resolve obsolete confirmation without cross-kind repair link');
 PERFORM assert_true((SELECT bounced_at IS NOT NULL FROM public.email_messages WHERE message_id=failed),'historical failure remains intact');
 UPDATE public.email_messages SET recipient='other@example.invalid' WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'another recipient cannot resolve confirmation');
 UPDATE public.email_messages SET recipient='fixed@example.invalid',source_version=source_version+1 WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'stale ticket version cannot resolve confirmation');
 UPDATE public.email_messages SET source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=oid),data=data||'{"repair_payment_fingerprint":"stale"}' WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'stale payment facts cannot resolve confirmation');
 UPDATE public.email_messages SET data=data-'repair_payment_fingerprint',delivered_at=now()-interval '4 days' WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'older delivery cannot resolve later confirmation failure');
 UPDATE public.email_messages SET delivered_at=now(),bounced_at=now()+interval '1 second' WHERE message_id=tickets;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),2,'failed tickets preserve both unresolved issues');
 UPDATE public.email_messages SET bounced_at=NULL WHERE message_id=tickets;
 msg:=public.enqueue_email('order_update',jsonb_build_object('organization',org,'occasion',oc,'unit',un),'fixed@example.invalid','{}','independent-update');
 UPDATE public.email_messages SET order_id=oid,workflow_state='dead' WHERE message_id=(msg->>'message_id')::uuid;
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(oid)),1,'independent update failure remains actionable');
 PERFORM assert_eq(public.order_email_current_issues(oid)#>>'{0,kind}','order_update','only obsolete confirmation is superseded');
END $$;
ROLLBACK;
