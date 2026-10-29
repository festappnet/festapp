-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb; oid bigint; tid bigint; ticket bigint; used_id bigint; cancelled_id bigint;
 snapshot jsonb; version_before bigint; messages_before bigint; result jsonb; rejected boolean:=false; mid uuid;
BEGIN
 x:=pg_temp.payment_fixture(300); oid:=(x->>'order')::bigint; ticket:=(x->>'ticket')::bigint;
 snapshot:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_pair(x,299);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'below deposit remains unpaid');
 tid:=pg_temp.payment_pair(x,1);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'exact deposit pays order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'paid'::text,'exact deposit pays admission');
 PERFORM pg_temp.payment_accept_tickets(x);
 snapshot:=pg_temp.payment_history(oid);
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'used') RETURNING id INTO used_id;
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'storno') RETURNING id INTO cancelled_id;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,used_id),(oid,cancelled_id);
 result:=public.apply_transaction_pairing(tid,NULL,'test','system');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'unpairing below deposit revokes paid state');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'ordered'::text,'unpairing revokes sent admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_id),'used'::text,'unpairing preserves consumed admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=cancelled_id),'storno'::text,'unpairing preserves cancellation');
 PERFORM assert_eq(pg_temp.payment_history(oid),snapshot,'payment reversal preserves the established history contract');
 result:=public.apply_transaction_pairing(tid,(x->>'payment')::bigint,'test','system');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'paid'::text,'repairing payment restores eligible admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_id),'used'::text,'repayment preserves used');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=cancelled_id),'storno'::text,'repayment preserves storno');

 SELECT email_payment_version INTO version_before FROM eshop.orders WHERE id=oid;
 SELECT count(*) INTO messages_before FROM public.email_messages WHERE order_id=oid;
 result:=public.apply_transaction_pairing(tid,(x->>'payment')::bigint,'test','system');
 PERFORM assert_eq(result->>'status','unchanged'::text,'same pairing is idempotent');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),version_before,'pairing replay preserves email version');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid),messages_before,'pairing replay adds no email');

 snapshot:=jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
  'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=(x->>'payment')::bigint),
  'history',pg_temp.payment_history(oid));
 BEGIN
  PERFORM pg_temp.payment_edit(x,-1);
 EXCEPTION WHEN OTHERS THEN
  IF position('Product prices cannot be negative' in SQLERRM)>0 THEN rejected:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_eq(rejected,true,'invalid price is rejected through the public command');
 PERFORM assert_eq(jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
  'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=(x->>'payment')::bigint),
  'history',pg_temp.payment_history(oid)),snapshot,'rejected command changes no order/payment/history');

 -- An acknowledgement arriving after the payment was removed cannot resurrect
 -- admission or create a false sent event, even if the provider accepted it.
 x:=pg_temp.payment_fixture(); oid:=(x->>'order')::bigint; ticket:=(x->>'ticket')::bigint;
 tid:=pg_temp.payment_pair(x,1000);
 SELECT message_id INTO STRICT mid FROM public.email_messages
 WHERE order_id=oid AND message_kind='order_tickets'
 AND source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=oid);
 result:=public.apply_transaction_pairing(tid,NULL,'test','system');
 snapshot:=pg_temp.payment_history(oid);
 UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now(),
  post_action=jsonb_build_object('ticket_ids',jsonb_build_array(ticket)) WHERE message_id=mid;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.apply_email_post_actions(mid);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'late acknowledgement keeps unpaid order ordered');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=ticket),'ordered'::text,'late acknowledgement cannot revive admission');
 PERFORM assert_eq(pg_temp.payment_history(oid),snapshot,'stale acceptance appends no false sent history');
END $$;
