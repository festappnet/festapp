DO $$
DECLARE org bigint; un bigint; occ bigint; hidden bigint; ticket bigint; oid bigint; actor uuid; symbol text;
BEGIN
 PERFORM create_user_for_test('scan-abuse','scan-abuse@example.invalid');actor:=get_user_id('scan-abuse');
 INSERT INTO public.organizations(title) VALUES('Scan fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Scan Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions_hidden(secret) VALUES('scan-abuse-secret') RETURNING id INTO hidden;
 INSERT INTO public.occasions(title,organization,unit,occasion_hidden,link,start_time,end_time)
 VALUES('Scan fixture',org,un,hidden,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES(occ,actor,true,true);
 symbol:=public.generate_ticket_symbol(org,occ);
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'sent',symbol) RETURNING id INTO ticket;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'sent','{}') RETURNING id INTO oid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,ticket);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='scan.invalid.source.burst';
 PERFORM set_config('request.jwt.claim.role','anon',true);PERFORM set_config('request.jwt.claim.sub','',true);
 EXECUTE 'SET LOCAL ROLE anon';
 PERFORM assert_eq((public.scan_ticket(symbol,'wrong')->>'code')::int,401,'wrong proof is rejected');
 PERFORM assert_eq((public.scan_ticket(symbol,'scan-abuse-secret')->>'code')::int,429,'correct guessed proof cannot bypass exhausted source gate');
 PERFORM assert_eq((public.get_occasion_by_scan_code('scan-abuse-secret')->>'code')::int,429,'alternate scan lookup shares the same attempt gate');
 PERFORM set_config('request.headers','{"x-forwarded-for":"1.2.3.4","cf-connecting-ip":"2.3.4.5"}',true);
 PERFORM assert_eq((public.update_ticket_to_used(ticket,'scan-abuse-secret')->>'code')::int,429,'forwarded headers do not reset source identity');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'sent','denial leaves ticket unchanged');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='scan.invalid.source.burst'),1::numeric,'invalid proof consumption persists across API calls');
 PERFORM set_config('request.headers','{"x-festapp-client-ip":"203.0.113.21"}',true);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='scan.operation.unit.burst';
 EXECUTE 'SET LOCAL ROLE anon';
 PERFORM assert_eq((public.scan_ticket(symbol,'scan-abuse-secret')->>'code')::int,200,'independent trusted source retains legitimate access');
 PERFORM assert_eq((public.update_ticket_to_used(ticket,'scan-abuse-secret')->>'code')::int,429,'read and mark share Unit work budget');
 EXECUTE 'RESET ROLE';
 UPDATE public.abuse_policy_rules SET base_limit=10 WHERE rule_key='scan.operation.unit.burst';
 PERFORM set_config('request.headers','{}',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_eq((public.scan_ticket(symbol,'scan-abuse-secret')->>'code')::int,200,'authorized staff have recovery during anonymous source exhaustion');
 PERFORM assert_eq((public.update_ticket_to_used(ticket,'scan-abuse-secret')->>'code')::int,200,'legitimate admission still marks ticket');
 PERFORM assert_eq((public.update_ticket_to_used(ticket,'scan-abuse-secret')->>'code')::int,409,'repeat does not mark a second admission');
 EXECUTE 'RESET ROLE';
 PERFORM assert_false(has_function_privilege('anon','public.admit_scan_access_v1(bigint,boolean)','EXECUTE'),'client cannot claim a verified scan');
END $$;
