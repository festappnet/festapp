DO $$
DECLARE org bigint; a bigint; b bigint; o1 bigint; o2 bigint; first_claim jsonb; next_claim jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Fairness fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('A',org) RETURNING id INTO a;
 INSERT INTO public.units(title,organization) VALUES('B',org) RETURNING id INTO b;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('A',org,a,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO o1;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('B',org,b,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO o2;
 PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',o1),'a1@example.invalid','{}','a1');
 PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',o1),'a2@example.invalid','{}','a2');
 PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',o2),'b@example.invalid','{}','b');
 UPDATE public.email_messages SET created_at=now()-interval '5 minutes',target_time=now()-interval '5 minutes' WHERE unit=a;
 UPDATE public.email_messages SET prepared='{}' WHERE organization=org AND recipient IN ('a2@example.invalid','b@example.invalid');
 UPDATE public.email_capacity SET paused=false,quota_at=now(),max_preparing=2,circuit_until=NULL;
 first_claim:=public.claim_email();
 PERFORM assert_eq((first_claim->>'unit')::bigint,a,'first sender can prepare');
 next_claim:=public.claim_email();
 PERFORM assert_eq((next_claim->>'unit')::bigint,b,'older backlog cannot monopolize the same priority class');
 -- A prepared snapshot is still subject to pending bytes, not only its small intent.
 UPDATE public.abuse_policy_rules SET base_limit=100 WHERE rule_key='email.backlog.unit.bytes';
 BEGIN
  PERFORM public.prepare_email((first_claim->>'message_id')::uuid,(first_claim->>'lease_token')::uuid,jsonb_build_object('ciphertext',repeat('x',200)));
  RAISE EXCEPTION 'prepared bytes bypassed pending budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_true((SELECT prepared IS NULL FROM public.email_messages WHERE message_id=(first_claim->>'message_id')::uuid),'failed snapshot admission rolls back bytes');
END $$;
