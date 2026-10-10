BEGIN;
CREATE FUNCTION pg_temp.assert_cancelled_rejected(p_sql text) RETURNS void
LANGUAGE plpgsql AS $guard_test$
DECLARE response text; rejected boolean:=false;
BEGIN
 BEGIN
  EXECUTE p_sql INTO response;
 EXCEPTION WHEN SQLSTATE '55000' THEN rejected:=true;
 END;
 IF NOT rejected AND left(response,1)='{' THEN
  rejected:=coalesce(response::jsonb->>'code','200')<>'200' AND
    concat(response::jsonb->>'message',response::jsonb->>'detail') LIKE '%ORDER_CANCELLED%';
 END IF;
 PERFORM assert_true(rejected,'cancelled command must reject: '||p_sql);
END $guard_test$;
INSERT INTO public.organizations(id,title) VALUES(780,'Cancelled order fixture');
INSERT INTO public.units(id,organization,title) VALUES(780,780,'Cancelled unit');
INSERT INTO auth.users(id,email) VALUES('00000000-0000-0000-0000-000000000780','cancelled@example.invalid');
INSERT INTO public.user_info(id,email_readonly) VALUES('00000000-0000-0000-0000-000000000780','cancelled@example.invalid');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000780',true);
INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(780,'00000000-0000-0000-0000-000000000780',true);
INSERT INTO public.occasions(id,organization,unit,title,link,start_time,end_time)
VALUES(780,780,780,'Cancelled occasion','cancelled-order-read-only',now(),now()+interval '1 day');
INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_order)
VALUES(780,'00000000-0000-0000-0000-000000000780',true,true,true);
INSERT INTO eshop.bank_accounts(id,title,account_number,type,supported_currencies)
VALUES(7800,'Cancelled account','1234/5678','FIO',ARRAY['CZK']);
INSERT INTO eshop.product_types(id,occasion,title) VALUES(7800,780,'Ticket');
INSERT INTO eshop.products(id,occasion,product_type,title,price,currency_code)
VALUES(78001,780,7800,'Ticket',450,'CZK');
DO $$
DECLARE pi bigint; oid bigint; tid bigint; result jsonb; blocked boolean:=false; before_order jsonb; before_ticket jsonb; before_payment jsonb; hid bigint; statement text; tx bigint;
BEGIN
 INSERT INTO eshop.payment_info(variable_symbol,amount,paid,currency_code,bank_account)
 VALUES(780780,0,0,'CZK',7800) RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,payment_info,state,price,currency_code)
 VALUES(public.next_order_sequence(780),public.generate_order_symbol(),780,pi,'storno',0,'CZK') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state) VALUES(780,'storno') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,78001);
 UPDATE eshop.orders SET data=jsonb_build_object('email','cancelled@example.invalid','tickets',jsonb_build_array(jsonb_build_object('id',tid,'products',jsonb_build_array(jsonb_build_object('id',78001,'price',0))))) WHERE id=oid;
 INSERT INTO eshop.orders_history("order",state,price) VALUES(oid,'storno',0) RETURNING id INTO hid;
 SELECT to_jsonb(o) INTO before_order FROM eshop.orders o WHERE id=oid;
 SELECT to_jsonb(t) INTO before_ticket FROM eshop.tickets t WHERE id=tid;
 SELECT to_jsonb(p) INTO before_payment FROM eshop.payment_info p WHERE id=pi;
 BEGIN
  result:=public.update_ticket_products_wsv2(tid,'[{"id":78001,"price":450}]');
  blocked:=(result->>'code') IS DISTINCT FROM '200';
 EXCEPTION WHEN SQLSTATE '55000' THEN blocked:=true;
 END;
 PERFORM assert_true(blocked,'price edit must reject a cancelled order');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','price edit must not resurrect cancelled order');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),0::numeric,'cancelled order price stays zero');

 FOREACH statement IN ARRAY ARRAY[
  format('SELECT public.update_ticket_products_internal_v1(%s,''[{"id":78001,"price":450}]'')',tid),
  format('SELECT public.update_ticket_products_client_sync_v1(%s,''[{"id":78001,"price":450}]'',gen_random_uuid())',tid),
  format('SELECT public.update_order_note_hidden(%s,''changed'')',oid),
  format('SELECT public.update_ticket_note_hidden(%s,''changed'')',tid),
  format('SELECT public.update_order_responses(%s,''{}'')',oid),
  format('SELECT public.update_order_and_tickets_to_sent(%s,ARRAY[%s]::bigint[])',oid,tid),
  format('SELECT public.update_order_and_tickets_to_storno_221(%s)',oid),
  format('SELECT public.delete_order_221(%s)',oid),
  format('SELECT public.delete_order_history(%s)',hid),
  format('SELECT public.set_payment_deadline(%s,now())',pi),
  format('SELECT public.update_payment_info_variable_symbol(%s,123)',pi),
  format('SELECT public.enqueue_order_email(''TICKET_ORDER_UPDATE'',jsonb_build_object(''order_id'',%s),780::bigint,780::bigint,780::bigint)',oid)
 ] LOOP
  PERFORM pg_temp.assert_cancelled_rejected(statement);
 END LOOP;
 result:=public.update_order_and_tickets_to_paid_ws(oid);
 PERFORM assert_true(result->>'code'<>'200','payment cannot reactivate cancelled order');
 PERFORM assert_eq((SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),before_order,'rejected commands preserve complete order');
 PERFORM assert_eq((SELECT to_jsonb(t) FROM eshop.tickets t WHERE id=tid),before_ticket,'rejected commands preserve complete ticket');
 PERFORM assert_eq((SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=pi),before_payment,'rejected commands preserve complete payment');
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.orders_history WHERE "order"=oid),1,'rejected commands preserve history');
 PERFORM assert_eq((SELECT count(*)::int FROM public.email_messages WHERE order_id=oid),0,'rejected commands enqueue no email');
 -- Independently guard the parent even if an inconsistent ticket still says used/sent.
 UPDATE eshop.tickets SET state='used' WHERE id=tid;
 PERFORM pg_temp.assert_cancelled_rejected(format('SELECT public.update_ticket_to_unused_ws(%s)',tid));
 UPDATE eshop.tickets SET state='sent' WHERE id=tid;
 PERFORM pg_temp.assert_cancelled_rejected(format('SELECT public.update_ticket_to_used_ws(%s)',tid));
 -- Manual bank/cash pairing cannot attach to or detach from a cancelled order.
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,transaction_type)
 VALUES(now(),450,'CZK',7800,'manual') RETURNING id INTO tx;
 PERFORM pg_temp.assert_cancelled_rejected(format('SELECT public.apply_transaction_pairing(%s,%s,''manual_attach'',''user'')',tx,pi));
 PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=tx),'rejected manual attach preserves transaction');
 UPDATE eshop.transactions SET payment_info=pi WHERE id=tx;
 PERFORM pg_temp.assert_cancelled_rejected(format('SELECT public.apply_transaction_pairing(%s,NULL,''manual_unlink'',''user'')',tx));
 PERFORM assert_eq((SELECT payment_info FROM eshop.transactions WHERE id=tx),pi,'rejected manual unlink preserves transaction');
 -- Real imported movement processing remains independent from order edits.
 PERFORM public.apply_transaction_pairing(tx,NULL,'fixture_bank_fact','service');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','bank fact cannot reopen a cancelled order');
 -- Cancellation email delivery is still legitimate; it does not reopen the order.
 result:=public.enqueue_order_email('TICKET_ORDER_STORNO',jsonb_build_object('order_id',oid),780,780,780);
 PERFORM assert_not_null(result->>'message_id','cancellation confirmation can still be queued');
 -- Active orders retain their existing editor behavior.
 UPDATE eshop.orders SET state='ordered' WHERE id=oid;
 result:=public.update_order_note_hidden(oid,'active note');
 PERFORM assert_eq(result->>'code','200','active order remains editable');
 PERFORM assert_eq((SELECT note_hidden FROM eshop.orders WHERE id=oid),'active note','active note edit persists');

END $$;
ROLLBACK;
