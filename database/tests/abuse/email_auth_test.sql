DO $$
DECLARE org bigint; un bigint; occ bigint; oid bigint; a jsonb; b jsonb; n bigint; key text:=encode(extensions.digest('abuse reset fixture','sha256'),'hex');
BEGIN
 INSERT INTO public.organizations(title) VALUES('Abuse email fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Fair use unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled)
 VALUES('Fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',true) RETURNING id INTO occ;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.backlog.unit';
 a:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'one@example.invalid','{}','fixture-one');
 b:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'one@example.invalid','{}','fixture-one');
 PERFORM assert_eq(a->>'message_id',b->>'message_id','mail dedupe precedes admission');
 BEGIN
  PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'two@example.invalid','{}','fixture-two');
  RAISE EXCEPTION 'ordinary backlog bypassed';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'paid','{"email":"paid@example.invalid"}',100,'CZK') RETURNING id INTO oid;
 PERFORM public.enqueue_paid_order_tickets(oid);
 PERFORM public.enqueue_paid_order_tickets(oid);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid),1::bigint,'paid commitment retained once despite exhausted ordinary backlog');
 PERFORM assert_eq((SELECT admission_class FROM public.email_messages WHERE order_id=oid),'commitment','paid reserve is derived from actual order');
 UPDATE eshop.orders SET state='sent' WHERE id=oid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE order_id=oid),true);
 PERFORM assert_eq((SELECT admission_class FROM public.email_messages WHERE order_id=oid),'commitment','delivery-state transition cannot revoke an accepted paid reservation');
 BEGIN
  PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ,'priority',0,'paid',true),'spoof@example.invalid','{}','spoof');
  RAISE EXCEPTION 'priority spoof consumed reserve';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- Essential auth has its own bounded backlog instead of sharing bulk occupancy.
 PERFORM public.enqueue_email('sign_in',jsonb_build_object('organization',org),'auth@example.invalid','{}','auth-fixture');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE organization=org),3::bigint,'auth and paid survive bulk exhaustion');
 -- New UUIDs and a different tenant cannot reset the shared recipient budget.
 UPDATE public.email_messages SET workflow_state='accepted' WHERE organization=org AND message_kind='custom';
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.ordinary.recipient.burst';
 PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'recipient@example.invalid','{}','recipient-one');
 UPDATE public.email_messages SET workflow_state='accepted' WHERE organization=org AND message_kind='custom';
 BEGIN
  PERFORM public.enqueue_email('app_links',jsonb_build_object('organization',org,'occasion',occ),'recipient@example.invalid','{}',gen_random_uuid()::text);
  RAISE EXCEPTION 'recipient budget reset by kind/UUID';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_true(public.consume_auth_abuse_v1('reset.account',key),'first durable attempt');
 PERFORM assert_true(public.consume_auth_abuse_v1('reset.account',key),'second durable attempt');
 PERFORM assert_true(public.consume_auth_abuse_v1('reset.account',key),'third durable attempt');
 PERFORM assert_false(public.consume_auth_abuse_v1('reset.account',key),'fourth is denied with committed consumption');
 PERFORM assert_false(public.consume_password_reset_rate_limit_v1(key,3,900),'legacy path shares canonical budget');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='reset.account' AND scope_id=public.abuse_recipient_key_v1(key)),5::numeric,'denied attempts are persisted');
 PERFORM assert_false(public.consume_auth_abuse_v1(NULL,NULL),'NULL inputs fail closed');
 PERFORM assert_false(has_function_privilege('authenticated','public.consume_auth_abuse_v1(text,text)','EXECUTE'),'attempt admission is service only');
 -- Last provider fence remains authoritative, regardless of queue class.
 UPDATE public.email_capacity SET paused=true;
 PERFORM assert_true(public.claim_email() IS NULL,'reserve never bypasses provider pause');
END $$;
