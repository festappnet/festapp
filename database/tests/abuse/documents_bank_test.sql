DO $$
DECLARE actor uuid; stranger uuid; org bigint; un bigint; occ bigint; ticket bigint; oid bigint; bank bigint; op uuid:=gen_random_uuid(); result jsonb;
BEGIN
 PERFORM create_user_for_test('abuse-doc','abuse-doc@example.invalid'); actor:=get_user_id('abuse-doc');
 PERFORM create_user_for_test('abuse-stranger','abuse-stranger@example.invalid'); stranger:=get_user_id('abuse-stranger');
 INSERT INTO public.organizations(title) VALUES('Documents fixture') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id IN(actor,stranger);
 INSERT INTO public.units(title,organization) VALUES('Unit',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(occ,actor,true,true);
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'ordered','{}') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'ordered',public.generate_ticket_symbol(org,occ)) RETURNING id INTO ticket;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,ticket);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',stranger::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_ticket_document_data_v1(ticket); RAISE EXCEPTION 'foreign document read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_order_agreement_data_v1(oid); RAISE EXCEPTION 'foreign agreement read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='ticket.document.actor.burst';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.get_ticket_document_data_v1(ticket);
 PERFORM assert_eq((result#>>'{ticket,id}')::bigint,ticket,'authorized download retains the existing data contract');
 BEGIN PERFORM public.get_order_agreement_data_v1(oid); RAISE EXCEPTION 'different document route reset budget'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_true(public.admit_ticket_preview_v1(occ,1000),'preview checks actual Unit permission');
 EXECUTE 'RESET ROLE';
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Bank operation fixture','FIO','8888/2010',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='bank.operation.actor.day';
 result:=public.begin_bank_sync_operation(op,bank,'sync',repeat('a',64));
 PERFORM public.begin_bank_sync_operation(op,bank,'sync',repeat('a',64));
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='bank.operation.actor.day' AND scope_id=actor::text),1::numeric,'bank operation replay is charged once');
 UPDATE eshop.bank_sync_operations SET state='completed' WHERE id=op;
 BEGIN PERFORM public.begin_bank_sync_operation(gen_random_uuid(),bank,'sync',repeat('a',64)); RAISE EXCEPTION 'new operation UUID reset budget'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM eshop.bank_sync_operations WHERE bank_account_id=bank),1::bigint,'rejection leaves no pending external operation');
END $$;
