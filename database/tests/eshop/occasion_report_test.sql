BEGIN;
DO $$
DECLARE u uuid; org bigint; unit_id bigint; occ bigint; other_occ bigint;
  p1 bigint; p2 bigint; p3 bigint; p4 bigint; o1 bigint; o2 bigint; o3 bigint; o4 bigint;
  bank bigint; product1 bigint; product2 bigint; ticket_id bigint; r jsonb; m jsonb;
BEGIN
  PERFORM create_user_for_test('report_metrics','report-metrics@test.local');
  u:=get_user_id('report_metrics');
  INSERT INTO public.organizations(title) VALUES('Report metrics') RETURNING id INTO org;
  UPDATE public.user_info SET organization=org WHERE id=u;
  INSERT INTO public.units(title,organization) VALUES('Report metrics',org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(title,link,start_time,end_time,organization,unit)
    VALUES('Report metrics','report-metrics',now(),now(),org,unit_id) RETURNING id INTO occ;
  INSERT INTO public.occasions(title,link,start_time,end_time,organization,unit)
    VALUES('Other','report-other',now(),now(),org,unit_id) RETURNING id INTO other_occ;
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(occ,u,true);
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_eq((r->>'code')::int,200,'empty succeeds');
  PERFORM assert_eq(r->'report'->'orders','{"total":0,"by_state":[]}'::jsonb,'empty counts');
  PERFORM assert_eq(r->'report'->'money_by_currency','[]'::jsonb,'empty money');
  INSERT INTO eshop.bank_accounts(title) VALUES('Report bank') RETURNING id INTO bank;
  INSERT INTO eshop.payment_info(paid,returned,currency_code,deposit_amount) VALUES(120,20,'CZK',50) RETURNING id INTO p1;
  INSERT INTO eshop.payment_info(paid,returned,currency_code) VALUES(30,5,'EUR') RETURNING id INTO p2;
  INSERT INTO eshop.payment_info(paid,returned,currency_code,deposit_amount) VALUES(25,0,'CZK',25) RETURNING id INTO p3;
  INSERT INTO eshop.payment_info(paid,returned,currency_code) VALUES(40,10,'CZK') RETURNING id INTO p4;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state,payment_info) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,0,'storno',p4);
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state,payment_info) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,100,'paid',p1) RETURNING id INTO o1;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state,payment_info) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,0,'storno',p1) RETURNING id INTO o2;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state,payment_info,currency_code) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,30,'sent',p2,'EUR') RETURNING id INTO o3;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state,payment_info) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,100,'paid',p3) RETURNING id INTO o4;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,price,state) VALUES(public.next_order_sequence(occ), public.generate_order_symbol(), occ,NULL,'future'),(public.next_order_sequence(occ), public.generate_order_symbol(), occ,0,NULL);
  INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_type)
    VALUES(now(),40,'CZK',bank,p1,'manual'),(now(),-20,'CZK',bank,p1,'manual');
  INSERT INTO eshop.products(title,occasion) VALUES('Same title',occ) RETURNING id INTO product1;
  INSERT INTO eshop.products(title,occasion) VALUES('Same title',occ) RETURNING id INTO product2;
  INSERT INTO eshop.tickets(occasion,state) VALUES(occ,'paid') RETURNING id INTO ticket_id;
  INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(o1,product1,ticket_id),(o1,product2,ticket_id),(o4,product1,NULL);
  INSERT INTO eshop.spots(occasion,title,secret,order_product_ticket) VALUES(occ,'Seat',gen_random_uuid(),(SELECT min(id) FROM eshop.order_product_ticket WHERE "order"=o1));
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_eq((r->>'code')::int,200,'metrics succeeds');
  m:=r->'report'->'money_by_currency'->0;
  PERFORM assert_eq(m->>'currency','CZK','deterministic currencies');
  PERFORM assert_eq((m->>'current_order_value')::numeric,200::numeric,'current prices include storno zero');
  PERFORM assert_eq((m->>'received')::numeric,185::numeric,'shared payment once, deposit partial and storno receipts');
  PERFORM assert_eq((m->>'returned')::numeric,30::numeric,'refund including storno');
  PERFORM assert_eq((m->>'net_received')::numeric,155::numeric,'net');
  PERFORM assert_eq((m->>'manual_received')::numeric,40::numeric,'positive manual only');
  PERFORM assert_eq((m->>'other_received')::numeric,145::numeric,'other');
  PERFORM assert_eq((m->>'deposit_received_gross')::numeric,75::numeric,'gross deposits');
  PERFORM assert_eq((m->>'beyond_deposit_received_gross')::numeric,70::numeric,'overpayment beyond deposit');
  PERFORM assert_eq((r->'report'->'money_by_currency'->1->>'net_received')::numeric,25::numeric,'EUR refund');
  PERFORM assert_eq((r->'report'->'tickets'->>'total')::int,1,'ticket deduplicated');
  PERFORM assert_eq((r->'report'->'orders'->>'total')::int,7,'all orders');
  PERFORM assert_eq(jsonb_array_length(r->'report'->'products'),2,'same names distinct IDs');
  PERFORM assert_eq((SELECT sum((x->>'confirmed_count')::int)::int FROM jsonb_array_elements(r->'report'->'products') x),3,'one item is one unit');
  PERFORM assert_eq((r->'report'->'spots'->>'occupied')::int,1,'occupied seats');
  PERFORM assert_eq(public.format_occasion_report_text(r->'report'),r->>'data','text from same object');
  PERFORM assert_true(r->'report'->'orders'->'by_state' @> '[{"state":"unknown","count":1},{"state":"future","count":1}]','null and future state');
  -- Daily history includes partial money while an order is still ordered,
  -- deduplicates a shared payment and excludes another occasion's transactions.
  UPDATE eshop.orders SET state='ordered',created_at='2026-10-01 22:30:00+00' WHERE id=o4;
  UPDATE eshop.transactions SET date='2026-10-01 12:00:00' WHERE payment_info=p1;
  INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_type)
    VALUES('2026-10-03 12:00:00',12.50,'CZK',bank,p3,'bank'),
          ('2026-10-03 12:00:00',10,'EUR',bank,p2,'bank');
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_true(r->'report'->'timeline'->'orders' @> '[{"day":"2026-10-02","currency":"CZK","count":1}]', 'Prague order day at UTC midnight boundary');
  PERFORM assert_true(r->'report'->'timeline'->'payments' @> '[{"day":"2026-10-01","currency":"CZK","received":"40.00","returned":"20.00"}]','shared payment transactions counted once');
  PERFORM assert_true(r->'report'->'timeline'->'payments' @> '[{"day":"2026-10-03","currency":"CZK","received":"12.50","returned":"0"}]','partial bank payment on still ordered order');
  PERFORM assert_true(r->'report'->'timeline'->'payments' @> '[{"day":"2026-10-03","currency":"EUR","received":"10.00"}]','currencies remain separate');
  UPDATE eshop.orders SET currency_code='EUR' WHERE id=o2;
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_eq((r->>'code')::int,409,'currency mismatch safely fails');
  UPDATE eshop.orders SET currency_code='CZK',occasion=other_occ WHERE id=o2;
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_eq((r->>'code')::int,409,'cross occasion payment safely fails');
  PERFORM assert_true(NOT (r ? 'report') AND NOT (r ? 'detail'),'no financial leak');
  UPDATE eshop.orders SET occasion=occ WHERE id=o2;
  UPDATE eshop.transactions SET amount=200 WHERE payment_info=p1 AND amount>0;
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_true(r->'report'->'warnings' @> '[{"code":"negative_other_received","count":1}]','negative other visible');
  DELETE FROM public.occasion_users WHERE occasion=occ AND "user"=u;
  SET LOCAL ROLE authenticated;
  r:=public.get_report_ws('report-metrics');
  RESET ROLE;
  PERFORM assert_eq((r->>'code')::int,403,'revoked permission');
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.get_report_ws('report-metrics');
    RAISE EXCEPTION 'anonymous unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  PERFORM assert_false(has_function_privilege('authenticated','public.format_occasion_report_text(jsonb)','EXECUTE'),'formatter private');
END $$;
ROLLBACK;
