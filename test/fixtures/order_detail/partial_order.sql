-- Synthetic family order; partial cancellation uses the canonical owner.
-- Do not replay: the review sandbox keeps the user's subsequent edits.
DO $$
DECLARE oc bigint;frm bigint;actor uuid;un bigint;prod bigint;bank bigint;oid bigint;pi bigint;
 tid bigint;iid bigint;sid bigint;last_ticket bigint;i int;tickets jsonb:='[]';
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-order-detail-20261101') THEN RAISE EXCEPTION 'Wrong sandbox'; END IF;
 SELECT id,unit INTO oc,un FROM public.occasions WHERE link='order-detail-ples';
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE occasion=oc AND data->>'email'='veronika.horakova@example.invalid') THEN RAISE EXCEPTION 'Partial fixture already exists'; END IF;
 SELECT id INTO actor FROM public.user_info WHERE email_readonly='spravce@example.invalid';
 SELECT id INTO frm FROM public.forms WHERE occasion=oc ORDER BY id LIMIT 1;
 SELECT id INTO prod FROM eshop.products WHERE occasion=oc AND title='Vstup do hlavního sálu';
 SELECT bank_account INTO bank FROM eshop.unit_bank_accounts WHERE unit=un AND priority=1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('festapp.email_wake','scheduled',true);
 INSERT INTO eshop.payment_info(amount,paid,currency_code,bank_account,deadline,variable_symbol) VALUES(1950,1950,'CZK',bank,'2027-01-10 23:00+01',270109) RETURNING id INTO pi;
 oid:=public.allocate_ticket_order_identity_internal(frm);
 FOR i IN 1..3 LOOP
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data) VALUES(oc,'sent','RODINA-'||i,'{}') RETURNING id INTO tid;
  INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,tid,prod) RETURNING id INTO iid;
  SELECT id INTO sid FROM eshop.spots WHERE occasion=oc AND blueprint IS NOT NULL AND order_product_ticket IS NULL ORDER BY id LIMIT 1;
  UPDATE eshop.spots SET order_product_ticket=iid WHERE id=sid;
  tickets:=tickets||jsonb_build_array(jsonb_build_object('id',tid,'ticket_symbol','RODINA-'||i,'products',jsonb_build_array(jsonb_build_object('id',prod,'title','Vstup do hlavního sálu','price',650,'currency_code','CZK','spot_title',(SELECT title FROM eshop.spots WHERE id=sid)))));
  last_ticket:=tid;
 END LOOP;
 UPDATE eshop.orders SET price=1950,state='sent',currency_code='CZK',payment_info=pi,data=jsonb_build_object('name','Veronika','surname','Horáková','email','veronika.horakova@example.invalid','form',(SELECT key FROM public.forms WHERE id=frm),'tickets',tickets) WHERE id=oid;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,vs,transaction_type,created_by,ingest_source,message_for_recipient) VALUES(bank,pi,1950,'CZK',now()-interval '1 day','270109','manual',actor,'manual','Syntetický výchozí pohyb rodinné objednávky');
 INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data,created_by) SELECT id,now()-interval '1 day',state,price,currency_code,data,actor FROM eshop.orders WHERE id=oid;
 PERFORM public.storno_tickets_bulk_internal_v1(ARRAY[last_ticket],false);
 -- No refund is invented: this leaves the real overpayment for an explicit operation.
END $$;
