-- Growth must come from bank-backed orders, not traffic, capacity or manual paid state.
DO $$
DECLARE org bigint; un bigint; occ bigint; bank bigint; pi bigint; txn bigint; i integer;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Growth fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Growth Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Growth occasion',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Growth bank','FIO','99123/2010',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code)
 VALUES(bank,99123,100,'CZK') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'paid','{}',100,'CZK',pi);
 -- Keep maintenance focused on this fixture without changing persistent test data.
 INSERT INTO public.abuse_unit_evidence SELECT id,0,now() FROM public.units
 ON CONFLICT(unit) DO UPDATE SET measured_at=excluded.measured_at;
 UPDATE public.abuse_unit_evidence SET measured_at=now()-interval '1 hour' WHERE unit=un;
 PERFORM public.refresh_abuse_unit_evidence_v1();
 PERFORM assert_eq((SELECT verified_orders FROM public.abuse_unit_evidence WHERE unit=un),0::bigint,'manual paid state earns no growth');
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_id,ingest_source)
 VALUES(now(),40,'CZK',bank,pi,99123001,'fio_api') RETURNING id INTO txn;
 UPDATE public.abuse_unit_evidence SET measured_at=now()-interval '1 hour' WHERE unit=un;
 PERFORM public.refresh_abuse_unit_evidence_v1();
 PERFORM assert_eq((SELECT verified_orders FROM public.abuse_unit_evidence WHERE unit=un),0::bigint,'unverified transaction earns no growth');
 INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
 VALUES('growth-test','FIO','99123/2010','movement','one',txn),
 ('growth-test','FIO','99123/2010','remote_transaction','two',txn);
 UPDATE public.abuse_unit_evidence SET measured_at=now()-interval '1 hour' WHERE unit=un;
 PERFORM public.refresh_abuse_unit_evidence_v1();
 PERFORM assert_eq((SELECT verified_orders FROM public.abuse_unit_evidence WHERE unit=un),0::bigint,'partial bank payment and manual paid state earn no growth');
 UPDATE eshop.transactions SET amount=100 WHERE id=txn;
 UPDATE public.abuse_unit_evidence SET measured_at=now()-interval '1 hour' WHERE unit=un;
 PERFORM public.refresh_abuse_unit_evidence_v1();
 PERFORM assert_eq((SELECT verified_orders FROM public.abuse_unit_evidence WHERE unit=un),1::bigint,'one actual order counts once despite multiple transaction identities');
 UPDATE public.abuse_policy_rules SET base_limit=1,hard_cap=4 WHERE rule_key='email.ordinary.unit.day';
 FOR i IN 1..4 LOOP
  PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),
   'growth-'||i||'@example.invalid','{}','growth-'||i);
 END LOOP;
 UPDATE public.abuse_unit_evidence SET verified_orders=100000 WHERE unit=un;
 BEGIN
  PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'cap@example.invalid','{}','growth-cap');
  RAISE EXCEPTION 'growth bypassed finite hard cap';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 UPDATE public.abuse_budget_usage SET amount=1 WHERE rule_key='email.ordinary.unit.day' AND scope_id=un::text;
 UPDATE public.abuse_unit_evidence SET measured_at=now()-interval '16 minutes' WHERE unit=un;
 BEGIN
  PERFORM public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',occ),'stale@example.invalid','{}','growth-stale');
  RAISE EXCEPTION 'stale evidence retained growth';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
END $$;
