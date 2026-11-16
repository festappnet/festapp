-- Provider calls are covered by the gateway tests; this exercises real SQL completion.
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; f bigint; bank bigint; payment bigint;
 oid bigint; q bigint; cmd uuid; ns text; symbol bigint; provisional bigint;
 currency text; enrolled boolean; failed boolean; old_count bigint;
BEGIN
 FOREACH enrolled IN ARRAY ARRAY[false,true] LOOP
  INSERT INTO organizations(title) VALUES('Fakturoid reference test') RETURNING id INTO org;
  INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled) VALUES(org,'bank',true);
  INSERT INTO units(title,organization) VALUES('Fakturoid reference test',org) RETURNING id INTO un;
  INSERT INTO occasions(title,unit,organization,link,start_time,end_time)
   VALUES('Fakturoid reference test',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
   VALUES('Reference bank','FIO',CASE WHEN enrolled THEN '19-2000145399/0800' ELSE '1234/2010' END,ARRAY['CZK','EUR']) RETURNING id INTO bank;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
  INSERT INTO forms(occasion,bank_account,is_open,data) VALUES(oc,bank,true,'{"payments":{"bankEnabled":true}}') RETURNING id INTO f;
  IF enrolled THEN
   ns:=public.enroll_payment_reference_account(bank);
   INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES(org,'active',repeat('a',64));
   UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true WHERE id=ns;
  END IF;
  FOREACH currency IN ARRAY ARRAY['CZK','EUR'] LOOP
   cmd:=gen_random_uuid(); symbol:=CASE WHEN currency='CZK' THEN 20260950 ELSE 20260951 END;
   oid:=public.allocate_ticket_order_identity_internal(f);
   INSERT INTO eshop.payment_info(amount,currency_code,bank_account,variable_symbol,deadline)
    VALUES(100,currency,bank,CASE WHEN enrolled THEN NULL ELSE 4830 END,now()+interval '1 day') RETURNING id INTO payment;
   UPDATE eshop.orders SET payment_info=payment,price=100,currency_code=currency,state='preparing_payment' WHERE id=oid;
   IF enrolled THEN
    provisional:=public.reserve_order_payment_reference_internal(payment,f);
    UPDATE eshop.payment_info SET variable_symbol=provisional WHERE id=payment;
   ELSE provisional:=4830; END IF;
   IF currency='EUR' THEN
    UPDATE eshop.payment_info SET creditor_reference=public.generate_creditor_reference(provisional) WHERE id=payment;
   END IF;
   INSERT INTO email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash)
    VALUES('infinity','TICKET_ORDER_CONFIRMATION',jsonb_build_object('command_id',cmd,
     'fakturoid_pending',true,'ticket_order',jsonb_build_object('order',jsonb_build_object('id',oid,
       'payment_info',jsonb_build_object('variable_symbol',provisional)))),org,oc,un,'order_confirmation',cmd::text,repeat('b',64)) RETURNING id INTO q;
   PERFORM assert_jsonb_contains(public.customer_order_payment_internal(oid),
    '{"status":"preparing","instructionsAvailable":false,"reference":null,"qrPayment":null,"publicAccount":null}',
    'pending Fakturoid preparation exposes no payable reference, account or QR');
   IF currency='EUR' THEN
    failed:=false;
    BEGIN PERFORM public.complete_fakturoid_ticket_order_v1(oid,cmd,symbol);
    EXCEPTION WHEN check_violation THEN failed:=true; END;
    PERFORM assert_true(failed,'EUR mismatch cannot change RF numeric base');
    symbol:=provisional;
   ELSE
    -- A symbol reserved/used by another payment must fail atomically.
    IF enrolled THEN
     PERFORM public.reserve_payment_reference_internal(payment,f,'test:occupied',
      '{"mode":"exact","value":"20260949"}',repeat('c',64));
     -- Retained history can belong to a deleted payment.
     UPDATE eshop.payment_reference_reservations SET original_payment_info_id=-1 WHERE namespace_id=ns AND variable_symbol=20260949;
    ELSE
     INSERT INTO eshop.payment_info(amount,currency_code,bank_account,variable_symbol) VALUES(100,'CZK',bank,20260949);
    END IF;
    failed:=false;
    BEGIN PERFORM public.complete_fakturoid_ticket_order_v1(oid,cmd,20260949);
    EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'PAYMENT_REFERENCE_CONFLICT' THEN RAISE; END IF; failed:=true; END;
    PERFORM assert_true(failed,'provider collision rejected');
    PERFORM assert_eq((SELECT variable_symbol FROM eshop.payment_info WHERE id=payment),provisional,'collision preserves payment');
    PERFORM assert_eq((SELECT target_time FROM email_messages WHERE id=q),'infinity'::timestamptz,'collision keeps email blocked');
   END IF;
   PERFORM assert_eq(public.complete_fakturoid_ticket_order_v1(oid,cmd,symbol),symbol,'completion returns provider symbol');
   PERFORM assert_eq((SELECT variable_symbol FROM eshop.payment_info WHERE id=payment),symbol,'stored reference equals invoice');
   PERFORM assert_eq((SELECT (data#>>'{ticket_order,order,payment_info,variable_symbol}')::bigint FROM email_messages WHERE id=q),symbol,'email reference equals invoice');
   PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'order published after reference adoption');
   IF currency='CZK' THEN
    PERFORM assert_jsonb_contains(public.customer_order_payment_internal(oid),
     jsonb_build_object('instructionsAvailable',true,'reference',symbol::text,
      'qrPayment',jsonb_build_object('variable_symbol',symbol)),
     'customer instructions become available with the final Fakturoid reference');
   END IF;

   PERFORM assert_true((SELECT target_time<>'infinity'::timestamptz AND NOT data ? 'fakturoid_pending' FROM email_messages WHERE id=q),'email released after adoption');
   SELECT count(*) INTO old_count FROM eshop.payment_reference_reservations WHERE original_payment_info_id=payment;
   PERFORM assert_eq(public.complete_fakturoid_ticket_order_v1(oid,cmd,symbol),symbol,'completion replay is stable');
   PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations WHERE original_payment_info_id=payment),old_count,'replay creates no additional reservations');
   IF enrolled AND currency='CZK' THEN
    PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns AND variable_symbol=symbol AND original_payment_info_id=payment),'provider symbol reserved');
    PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns AND variable_symbol=provisional AND original_payment_info_id=payment),'provisional tombstone retained');
   END IF;
  END LOOP;
 END LOOP;
END $$;
