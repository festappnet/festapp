-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); y jsonb:=pg_temp.payment_fixture();
 other_form_key uuid; un bigint; cash_payment bigint; cash_order bigint; ticket bigint; payload jsonb; movement jsonb;
 response jsonb; original jsonb; method text; command uuid:=gen_random_uuid(); amount text; invalid jsonb;
BEGIN
 SELECT key INTO other_form_key FROM public.forms WHERE id=(y->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}',bank_account=NULL WHERE id=(x->>'form')::bigint;
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=(x->>'form')::bigint),
  'email','cash-guards@example.invalid','payment_method','cash','client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 SET LOCAL ROLE authenticated;
 response:=public.create_ticket_order_client_sync_v1(payload-'client_capabilities',gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(response->>'status','rejected','old checkout cannot silently create cash');
 response:=public.create_ticket_order_client_sync_v1(payload||'{"payment_method":"bank"}',gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(response->>'status','rejected','bank cannot be spoofed on cash-only form');
 response:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'status','applied','cash guard fixture checkout');
 cash_order:=(response#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO cash_payment FROM eshop.orders WHERE id=cash_order;
 SELECT DISTINCT opt.ticket INTO ticket FROM eshop.order_product_ticket opt WHERE opt."order"=cash_order;
 -- Free reservations obey the same method selection before later repricing.
 UPDATE eshop.products SET price=0 WHERE id=(x->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 FOREACH method IN ARRAY ARRAY['bank','stripe'] LOOP
  response:=public.create_ticket_order_client_sync_v1(payload||jsonb_build_object('payment_method',method),gen_random_uuid(),gen_random_uuid());
  PERFORM assert_eq(response->>'status','rejected','free cash-only form refuses spoofed '||method);
 END LOOP;
 response:=public.create_ticket_order_client_sync_v1(payload-'payment_method',gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'status','applied','free cash reservation can infer its configured method');
 UPDATE eshop.products SET price=1000 WHERE id=(x->>'product')::bigint;
 UPDATE eshop.products SET price=0 WHERE id=(y->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 response:=public.create_ticket_order_client_sync_v1(payload||jsonb_build_object('form',other_form_key,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',y->'product'))))),gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'status','rejected','free bank form refuses spoofed cash');
 movement:=jsonb_build_object('amount','250.50','currency','CZK','unitId',un,'paymentInfoId',cash_payment,'receivedAt',now(),'note','Pokladna');
 SET LOCAL ROLE authenticated;
 FOREACH amount IN ARRAY ARRAY['0','0.00','NaN','Infinity','-Infinity','1.001','1e2','250,50','100000000.00'] LOOP
  BEGIN
   PERFORM public.insert_manual_transaction(movement||jsonb_build_object('amount',amount),gen_random_uuid());
   RAISE EXCEPTION 'invalid cash amount accepted: %',amount;
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CASH_AMOUNT_INVALID' THEN RAISE; END IF; END;
 END LOOP;
 BEGIN
  PERFORM public.insert_manual_transaction(movement||'{"amount":250.50}',gen_random_uuid());
  RAISE EXCEPTION 'numeric JSON accepted instead of exact decimal string';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'CASH_AMOUNT_INVALID' THEN RAISE; END IF; END;
 FOR invalid IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  movement||'{"currency":"EUR"}',movement||jsonb_build_object('unitId',un+1000000),
  movement||jsonb_build_object('paymentInfoId',y->'payment'))) LOOP
  BEGIN
   PERFORM public.insert_manual_transaction(invalid,gen_random_uuid());
   RAISE EXCEPTION 'foreign cash scope accepted';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM NOT IN ('CASH_ORDER_SCOPE_MISMATCH','User is not manager.') THEN RAISE; END IF;
  END;
 END LOOP;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=cash_payment),0::bigint,'all rejected commands leave ledger untouched');
 SET LOCAL ROLE authenticated;
 response:=public.insert_manual_transaction(movement,command);
 original:=response;
 response:=public.insert_manual_transaction(movement,command);
 RESET ROLE;
 PERFORM assert_eq(original->>'code','200','valid exact cash accepted');
 PERFORM assert_true((response#>>'{mutation,replayed}')::boolean,'duplicate command replays');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=cash_payment),1::bigint,'one movement after replay');
 -- Financial corrections preserve admission use, including when the balance falls.
 UPDATE eshop.tickets SET state='used' WHERE id=ticket;
 SET LOCAL ROLE authenticated;
 response:=public.insert_manual_transaction(movement||'{"amount":"-50.25"}',gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(response->>'code','200','explicit negative correction accepted');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=cash_payment),200.25::numeric,'exact correction adjusts ledger balance');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'used','cash correction preserves used admission');
 DELETE FROM public.unit_users WHERE unit=un AND "user"=(x->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.insert_manual_transaction(movement,command);
  RAISE EXCEPTION 'receipt replay leaked after management revoked';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'User is not manager.' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=cash_payment),2::bigint,'revoked replay adds no movement');
END $$;
