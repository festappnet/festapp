BEGIN;
INSERT INTO public.organizations(id,title) VALUES(780,'Cancelled order fixture');
INSERT INTO public.units(id,organization,title) VALUES(780,780,'Cancelled unit');
INSERT INTO auth.users(id,email) VALUES('00000000-0000-0000-0000-000000000780','cancelled@example.invalid');
INSERT INTO public.user_info(id,email_readonly) VALUES('00000000-0000-0000-0000-000000000780','cancelled@example.invalid');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000780',true);
INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(780,'00000000-0000-0000-0000-000000000780',true);
INSERT INTO public.occasions(id,organization,unit,title,link,start_time,end_time)
VALUES(780,780,780,'Cancelled occasion','cancelled-order-read-only',now(),now()+interval '1 day');
INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_order,is_editor_order_view)
VALUES(780,'00000000-0000-0000-0000-000000000780',true,true,true,true);
INSERT INTO eshop.bank_accounts(id,title,account_number,type,supported_currencies)
VALUES(7800,'Cancelled account','1234/5678','FIO',ARRAY['CZK']);
INSERT INTO eshop.product_types(id,occasion,title) VALUES(7800,780,'Ticket');
INSERT INTO eshop.products(id,occasion,product_type,title,price,currency_code)
VALUES(78001,780,7800,'Ticket',450,'CZK');
DO $$
DECLARE oid bigint; hid bigint; pi bigint; tid bigint; blocked boolean:=false; before_order jsonb; before_ticket jsonb; before_payment jsonb;
BEGIN
 INSERT INTO eshop.payment_info(variable_symbol,amount,paid,currency_code,bank_account)
 VALUES(780780,0,0,'CZK',7800) RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,payment_info,state,price,currency_code)
 VALUES(public.next_order_sequence(780),public.generate_order_symbol(),780,pi,'storno',0,'CZK') RETURNING id INTO oid;
 INSERT INTO eshop.tickets(occasion,state) VALUES(780,'storno') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,78001);
 INSERT INTO eshop.orders_history("order",state,price) VALUES(oid,'ordered',100) RETURNING id INTO hid;
 -- History administration is independent of the current order state.
 UPDATE public.unit_users SET is_manager=false
 WHERE unit=780 AND "user"='00000000-0000-0000-0000-000000000780';
 blocked:=false;
 BEGIN
  PERFORM public.delete_order_history(hid);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'User is not manager.' THEN RAISE; END IF;
  blocked:=true;
 END;
 PERFORM assert_true(blocked,'occasion editor cannot delete history without unit manager rights');
 PERFORM assert_true(EXISTS(SELECT FROM eshop.orders_history WHERE id=hid),'unauthorized deletion preserves history');
 UPDATE public.unit_users SET is_manager=true
 WHERE unit=780 AND "user"='00000000-0000-0000-0000-000000000780';
 SELECT to_jsonb(o) INTO before_order FROM eshop.orders o WHERE id=oid;
 SELECT to_jsonb(t) INTO before_ticket FROM eshop.tickets t WHERE id=tid;
 SELECT to_jsonb(p) INTO before_payment FROM eshop.payment_info p WHERE id=pi;
 PERFORM public.delete_order_history(hid);
 PERFORM assert_true(NOT EXISTS(SELECT FROM eshop.orders_history WHERE id=hid),'unit manager can delete cancelled order history');
 PERFORM assert_eq((SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),before_order,'history deletion preserves cancelled order');
 PERFORM assert_eq((SELECT to_jsonb(t) FROM eshop.tickets t WHERE id=tid),before_ticket,'history deletion preserves ticket');
 PERFORM assert_eq((SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=pi),before_payment,'history deletion preserves payment');
END $$;
ROLLBACK;
