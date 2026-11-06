-- Test-only, synthetic states on the disposable pre-hardening connector schema.
DO $$
DECLARE fx jsonb; oc bigint; org bigint; u bigint; oid bigint; v_ticket bigint; pi bigint; conn uuid; attempt uuid; i integer:=0; label text; bank_fixture jsonb;
BEGIN
 -- Exercise the real bank-deposit lifecycle and queue receipt before upgrade.
 bank_fixture:=pg_temp.payment_fixture(250);
 PERFORM pg_temp.payment_pair(bank_fixture,250);
 PERFORM pg_temp.payment_accept_tickets(bank_fixture);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 FOREACH label IN ARRAY ARRAY['ordered','paid','sent','partial_refund','full_refund','disputed','expired','leased'] LOOP
  i:=i+1;fx:=public.scanner_test_fixture(1);oc:=(fx->>'occasion')::bigint;v_ticket:=(fx#>>'{tickets,0}')::bigint;
  SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
  SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE eshop.order_product_ticket.ticket=(fx#>>'{tickets,0}')::bigint LIMIT 1;
  IF label='bank_deposit' THEN
   INSERT INTO eshop.payment_info(amount,currency_code,payment_method,deposit_amount) VALUES(100,'CZK','bank',25) RETURNING id INTO pi;
  ELSE
   INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state) VALUES(org,u,'acct_upgrade'||i,false,'connected') RETURNING id INTO conn;
   INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id) VALUES(100,'CZK','stripe',conn) RETURNING id INTO pi;
   INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state)
    VALUES(oid,pi,org,u,conn,false,10000,'CZK',1,'upgrade:'||extensions.gen_random_uuid(),now()+interval '31 minutes',CASE WHEN label IN ('paid','sent','partial_refund','full_refund','disputed') THEN 'paid' WHEN label='expired' THEN 'expired' ELSE 'uncertain' END) RETURNING id INTO attempt;
   IF label IN ('paid','sent','partial_refund','full_refund','disputed') THEN
    INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at) VALUES(conn,'pi_upgrade'||i,attempt,'payment',10000,'CZK',now());
   END IF;
   IF label IN ('partial_refund','full_refund') THEN
    INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at) VALUES(conn,'re_upgrade'||i,attempt,'refund',CASE WHEN label='full_refund' THEN 10000 ELSE 2300 END,'CZK',now());
   END IF;
   IF label='disputed' THEN INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at) VALUES(conn,'dp_upgrade'||i,attempt,10000,'under_review',now()); END IF;
   IF label='leased' THEN UPDATE eshop.stripe_checkout_attempts SET lease_token=extensions.gen_random_uuid(),lease_expires_at=now()+interval '2 minutes' WHERE id=attempt; END IF;
   INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at,committed_at,receipt)
    VALUES(conn,'evt_upgrade'||i,repeat('a',64),'festapp.fixture',now(),now(),'{"data":{"committed":true}}');
  END IF;
  UPDATE eshop.orders SET payment_info=pi,price=100,currency_code='CZK',state=CASE WHEN label='full_refund' THEN 'storno' WHEN label IN ('ordered','leased','bank_deposit') THEN 'ordered' WHEN label='expired' THEN 'expired' ELSE 'sent' END WHERE id=oid;
  IF label<>'bank_deposit' THEN PERFORM public.issue_stripe_capability_internal(oid,'return_read',now()+interval '5 minutes',attempt); END IF;
  PERFORM public.refresh_payment_info_totals_internal(pi);
  INSERT INTO eshop.orders_history("order",state,price,data) VALUES(oid,'ordered',100,jsonb_build_object('fixture',label));
 END LOOP;
END $$;
