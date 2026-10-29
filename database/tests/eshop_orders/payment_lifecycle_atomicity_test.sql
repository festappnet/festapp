-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Replace only the email-intent boundary, transactionally, to fail AFTER money
-- and state writes. This is fault injection, not a simulated payment engine.
CREATE FUNCTION pg_temp.payment_snapshot(x jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
  'order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=(x->>'order')::bigint),
  'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=(x->>'payment')::bigint),
  'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM eshop.tickets t
   WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=(x->>'order')::bigint)),
  'links',(SELECT jsonb_agg(to_jsonb(opt) ORDER BY opt.id) FROM eshop.order_product_ticket opt WHERE opt."order"=(x->>'order')::bigint),
  'emails',(SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.email_messages m WHERE m.order_id=(x->>'order')::bigint),
  'history',pg_temp.payment_history((x->>'order')::bigint));
$$;
DO $test$
DECLARE x jsonb:=pg_temp.payment_fixture(); before_state jsonb; tid bigint;
 result jsonb; failed boolean:=false; command uuid:=gen_random_uuid();
BEGIN
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,transaction_type)
 VALUES(now(),1000,'CZK',(x->>'bank')::bigint,'manual') RETURNING id INTO tid;
 before_state:=pg_temp.payment_snapshot(x);
 EXECUTE $ddl$CREATE OR REPLACE FUNCTION public.enqueue_paid_order_tickets(p_order bigint)
 RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $fault$
 BEGIN RAISE EXCEPTION 'PAYMENT_TEST_INTENT_FAILURE'; END $fault$$ddl$;
 BEGIN
  result:=public.apply_transaction_pairing(tid,(x->>'payment')::bigint,'test','system');
 EXCEPTION WHEN OTHERS THEN
  IF position('PAYMENT_TEST_INTENT_FAILURE' in SQLERRM)>0 THEN failed:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_eq(failed,true,'bank pairing propagates failure after paid transition');
 PERFORM assert_eq(pg_temp.payment_snapshot(x),before_state,'failed pairing rolls back money, tickets, history and intents');
 PERFORM assert_eq((SELECT payment_info FROM eshop.transactions WHERE id=tid),NULL::bigint,'failed pairing keeps movement unassigned');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transaction_pairing_events WHERE transaction_snapshot_id=tid),0::bigint,'failed pairing adds no successful audit receipt');

 failed:=false;
 BEGIN
  PERFORM pg_temp.payment_edit(x,0,command);
 EXCEPTION WHEN OTHERS THEN
  IF position('PAYMENT_TEST_INTENT_FAILURE' in SQLERRM)>0 THEN failed:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_eq(failed,true,'product command propagates failure after price/state updates');
 PERFORM assert_eq(pg_temp.payment_snapshot(x),before_state,'failed product edit rolls back price, tickets, history and intents');
 PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts WHERE command_id=command),0::bigint,
  'failed product edit leaves no successful or incomplete command receipt');
END $test$;
