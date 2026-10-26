DO $$
DECLARE org bigint; un bigint; occ bigint; a jsonb; b jsonb; claim jsonb; result jsonb; oid bigint; tid bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Dispatch fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Dispatch Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled)
 VALUES('Dispatch fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day',true) RETURNING id INTO occ;
 a:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'scheduled@example.invalid','{}','scheduled-a','fixture',now()+interval '2 days');
 b:=public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'scheduled@example.invalid','{}','scheduled-b','fixture',now()+interval '2 days');
 -- Simulate their scheduled times converging. No provider or network is called.
 UPDATE public.email_messages SET target_time=now(),prepared='{}' WHERE organization=org;
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.send.ordinary.recipient.burst';
 UPDATE public.email_capacity SET paused=false,shared_account=false,daily_quota=100,provider_sent_24h=0,max_rate=100,
  rate_factor=1,max_sending=2,max_preparing=2,quota_at=now(),next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL;
 claim:=public.claim_email();
 result:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(result->>'disposition','send','first actual recipient send is admitted');
 PERFORM assert_eq(public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid)->>'disposition','replay','same provider attempt does not charge recipient twice');
 PERFORM public.finish_email_attempt((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid,'accepted','synthetic-provider');
 UPDATE public.email_capacity SET next_send_at=now();
 claim:=public.claim_email();
 result:=public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_eq(result->>'disposition','deferred','future intents cannot burst through the actual recipient gate');
 PERFORM assert_true((SELECT target_time>=now()+interval '60 seconds' FROM public.email_messages WHERE message_id=(claim->>'message_id')::uuid),'retry uses release time of the conservative bucket');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='email.send.ordinary.recipient.burst'),1::numeric,'defer does not renew the recipient lockout');
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.send.ordinary.recipient.day';
 UPDATE public.email_messages SET target_time=now() WHERE message_id=(claim->>'message_id')::uuid;
 claim:=public.claim_email();
 PERFORM public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid);
 PERFORM assert_true((SELECT target_time>=now()+interval '24 hours' FROM public.email_messages WHERE message_id=(claim->>'message_id')::uuid),'daily exhaustion schedules one durable wait instead of a tight polling loop');
 -- Ordinary exhaustion must not prevent delivery of an accepted paid obligation.
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'paid','{"email":"scheduled@example.invalid"}',100,'CZK') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'paid',public.generate_ticket_symbol(org,occ)) RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
 PERFORM public.enqueue_paid_order_tickets(oid);
 claim:=public.claim_email();
 PERFORM assert_eq((claim->>'order_id')::bigint,oid,'existing paid class is selected from the same queue');
 PERFORM public.prepare_email((claim->>'message_id')::uuid,(claim->>'lease_token')::uuid,'{"ciphertext":"fixture"}','{}');
 PERFORM assert_eq(public.begin_email_send((claim->>'attempt_id')::uuid,(claim->>'lease_token')::uuid)->>'disposition','send','paid delivery has bounded recipient capacity separate from bulk');
END $$;
