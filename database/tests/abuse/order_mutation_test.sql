DO $$
DECLARE actor uuid; org bigint; un bigint; occ bigint; a bigint; b bigint; ta bigint; tb bigint; command uuid:=gen_random_uuid(); result jsonb;
BEGIN
 PERFORM create_user_for_test('mutation-abuse','mutation-abuse@example.invalid');actor:=get_user_id('mutation-abuse');
 INSERT INTO public.organizations(title) VALUES('Mutation fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Mutation Unit',org) RETURNING id INTO un;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Mutation fixture',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(occ,actor,true);
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'ordered','{}') RETURNING id INTO a;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data) VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,'ordered','{}') RETURNING id INTO b;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'ordered','mutation-a') RETURNING id INTO ta;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(occ,'ordered','mutation-b') RETURNING id INTO tb;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(a,ta),(b,tb);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='order.mutation.actor.burst';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.storno_order_client_sync_v1(a,command);
 PERFORM public.storno_order_client_sync_v1(a,command);
 BEGIN PERFORM public.storno_tickets_bulk(ARRAY[tb]); RAISE EXCEPTION 'ticket facade reset cancellation usage'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 BEGIN PERFORM public.update_order_and_tickets_to_storno_ws(b); RAISE EXCEPTION 'unversioned facade bypassed canonical cancellation'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 BEGIN PERFORM public.delete_order_client_sync_v1(b,gen_random_uuid()); RAISE EXCEPTION 'deletion reset mutation usage'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=b),'ordered','denied mutations preserve order and ticket');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='order.mutation.actor.burst' AND scope_id=actor::text),1::numeric,'replay and rejected alternate route do not reset or duplicate usage');
 PERFORM assert_false(has_function_privilege('anon','public.update_order_and_tickets_to_storno_ws(bigint)','EXECUTE'),'old facade has no anonymous grant');
END $$;
