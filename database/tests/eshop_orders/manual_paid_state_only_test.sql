BEGIN;
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; actor uuid; oid bigint; pi bigint; tid bigint; kind text; result jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Manual payment regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Manual payment regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,features,is_order_synchronization_enabled)
 VALUES('Manual payment regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day',
 '[{"code":"ticket","is_enabled":true}]',true) RETURNING id INTO oc;
 SELECT id INTO STRICT actor FROM auth.users LIMIT 1;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 FOREACH kind IN ARRAY ARRAY['manual','bank','free'] LOOP
  INSERT INTO eshop.payment_info(amount,paid,currency_code)
  VALUES(CASE WHEN kind='free' THEN 0 ELSE 100 END,CASE WHEN kind='bank' THEN 100 ELSE 0 END,'CZK') RETURNING id INTO pi;
  INSERT INTO eshop.orders(occasion,order_symbol,order_sequence,state,data,price,currency_code,payment_info)
  VALUES(oc,public.generate_order_symbol(),public.next_order_sequence(oc),'ordered','{"email":"regression@example.invalid"}',
   CASE WHEN kind='free' THEN 0 ELSE 100 END,'CZK',pi) RETURNING id INTO oid;
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES(oc,'ordered',public.generate_ticket_symbol(org,oc)) RETURNING id INTO tid;
  INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,tid);
  IF kind='manual' THEN
   result:=public.update_order_and_tickets_to_paid_ws(oid);
   IF result->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Manual paid failed: %',result; END IF;
   IF EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=oid) THEN RAISE EXCEPTION 'Manual paid queued an email before Send'; END IF;
   IF (SELECT state FROM eshop.orders WHERE id=oid) IS DISTINCT FROM 'paid'
    OR (SELECT state FROM eshop.tickets WHERE id=tid) IS DISTINCT FROM 'paid' THEN RAISE EXCEPTION 'Manual paid did not update states'; END IF;
   PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',oid),org,oc,un);
  ELSIF kind='bank' THEN
   PERFORM public.recalculate_order_payment_status(oid);
  ELSE
   result:=public.update_order_and_tickets_to_paid(oid);
   IF result->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'Free paid failed: %',result; END IF;
  END IF;
  IF (SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets')<>1 THEN
   RAISE EXCEPTION '% flow must queue exactly one ticket intent',kind; END IF;
 END LOOP;
 RAISE NOTICE 'PASS: manual paid changes states only; Send queues once; bank and free automatic delivery preserved';
END $$;
ROLLBACK;
