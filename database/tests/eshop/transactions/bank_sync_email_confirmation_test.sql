-- test-setup: database/tests/helpers/form_measurement_fixture.sql
CREATE FUNCTION pg_temp.confirm_error(bank bigint,delivery text,payment bigint,expected text,checked boolean DEFAULT true,hash text DEFAULT repeat('a',64),not_duplicate boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN
  PERFORM public.confirm_bank_sync_email_observation(bank,delivery,payment,hash,checked,not_duplicate);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM=expected THEN RETURN; END IF;
  RAISE;
 END;
 RAISE EXCEPTION 'Expected confirmation rejection: %',expected;
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; oc bigint:=(x->>'occasion')::bigint;
 bank bigint; conn bigint; pi bigint; pi2 bigint; oid bigint; tx bigint; other_bank bigint; other_unit bigint; alias_bank bigint;
 event jsonb; receipt jsonb; repeated jsonb; actor uuid:=(x->>'actor')::uuid; rows jsonb;
 delivery text:='01K00000000000000000000901'; second_delivery text:='01K00000000000000000000902';
BEGIN
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason)
 VALUES((x->>'organization')::bigint,true,1,'fixture','Email confirmation eligibility');
 UPDATE public.forms SET data=data||'{"analytics":{"enabled":true,"purchase_timing":"paid"}}' WHERE id=(x->>'form')::bigint;
 SELECT bank_account INTO bank FROM public.forms WHERE id=(x->>'form')::bigint;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
  physical_account,provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at)
 VALUES('email-confirm','festapp','901',bank,'1007/2010','FIO','email','connected','abcdef0123',repeat('a',64),now()) RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,1007,100,'CZK','bank') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,form,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,(x->>'form')::bigint,'ordered','{"email":"payments@example.invalid"}',100,'CZK',pi) RETURNING id INTO oid;
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,1007,100,'CZK','bank') RETURNING id INTO pi2;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"other@example.invalid"}',100,'CZK',pi2);
 event:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id',delivery,
  'data',jsonb_build_object('id','901','bank_account_id','901','amount_cents',10000,'currency','CZK',
  'date','2026-11-22T12:00:00Z','direction','incoming','identity_kind','observation','source','email',
  'raw_vs','1007','counter_account','222/2010','sender_name','Jan Novák','message','Vstupenky'));
 PERFORM public.ingest_bank_sync_transaction('email-confirm','festapp',repeat('a',64),event);
 PERFORM assert_false(public.form_paid_conversion_eligible_internal(oid),'quarantine is not received money');
 PERFORM assert_false(EXISTS(SELECT FROM eshop.transactions WHERE bank_account_id=bank),'email never automatically credits');
 rows:=(public.get_bank_sync_email_queue_page_v1(bank)->'items');
 PERFORM assert_eq(jsonb_array_length(rows),1,'email queue contains the observation');
 PERFORM assert_eq(jsonb_array_length(rows->0->'candidates'),2,'exact account/currency/VS candidates');
 PERFORM assert_true((rows#>>'{0,candidates,0,amount_matches}')::boolean,'SQL remaining due comparison');
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_ATTESTATION_REQUIRED',false);
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_DELIVERY_CONFLICT',true,repeat('b',64));
 UPDATE eshop.bank_sync_connections SET mode='api' WHERE id=conn;
 PERFORM assert_eq(jsonb_array_length((public.get_bank_sync_email_queue_page_v1(bank)->'items')),1,'email observation stays in queue after switch to api mode');
 UPDATE eshop.bank_sync_inbox SET payload=jsonb_set(payload,'{data,source}','"fio_api"') WHERE connection_id=conn AND delivery_id=delivery;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_NOT_CONFIRMABLE');
 UPDATE eshop.bank_sync_connections SET mode='email' WHERE id=conn;
 UPDATE eshop.bank_sync_inbox SET outcome='quarantined_conflict' WHERE connection_id=conn AND delivery_id=delivery;
 PERFORM assert_eq(jsonb_array_length(public.get_bank_sync_email_queue_page_v1(bank)->'items'),0,'API-era conflict excluded after switch to email');
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_NOT_CONFIRMABLE');
 BEGIN
  PERFORM public.dismiss_bank_sync_email_observation(bank,delivery,repeat('a',64),'API-era conflict');
  RAISE EXCEPTION 'Expected API-era dismissal rejection';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'BANK_SYNC_NOT_CONFIRMABLE' THEN RAISE; END IF;
 END;
 UPDATE eshop.bank_sync_inbox SET payload=event,outcome='quarantined_identity' WHERE connection_id=conn AND delivery_id=delivery;
 UPDATE eshop.bank_sync_inbox SET payload=jsonb_set(payload,'{data,amount_cents}','0') WHERE connection_id=conn AND delivery_id=delivery;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_NOT_CONFIRMABLE');
 UPDATE eshop.bank_sync_inbox SET payload=event WHERE connection_id=conn AND delivery_id=delivery;
 UPDATE eshop.payment_info SET currency_code='EUR' WHERE id=pi;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_TARGET_MISMATCH');
 UPDATE eshop.payment_info SET currency_code='CZK',payment_method='cash',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL WHERE id=pi;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_TARGET_MISMATCH');
 UPDATE eshop.payment_info SET payment_method='bank',bank_account=bank,variable_symbol=1007 WHERE id=pi;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Other account','FIO',ARRAY['CZK']) RETURNING id INTO other_bank;
 UPDATE eshop.payment_info SET bank_account=other_bank WHERE id=pi;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_TARGET_MISMATCH');
 UPDATE eshop.payment_info SET bank_account=bank WHERE id=pi;
 INSERT INTO public.units(title,organization) VALUES('Other unit',(x->>'organization')::bigint) RETURNING id INTO other_unit;
 UPDATE public.occasions SET unit=other_unit WHERE id=oc;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'BANK_SYNC_TARGET_MISMATCH');
 UPDATE public.occasions SET unit=un WHERE id=oc;
 UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=oc AND "user"=actor;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'User is not editor.',true,repeat('b',64));
 PERFORM assert_eq(jsonb_array_length((public.get_bank_sync_email_queue_page_v1(bank)->'items')->0->'candidates'),0,'no order rights means no candidate');
 UPDATE public.occasion_users SET is_editor_order=true WHERE occasion=oc AND "user"=actor;
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=bank AND "user"=actor;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'User is not an admin for the specified bank account.');
 UPDATE eshop.bank_account_users SET is_admin=true WHERE bank_account=bank AND "user"=actor;
 UPDATE eshop.organization_payment_method_policies SET enabled=false WHERE organization_id=(x->>'organization')::bigint AND method='bank';
 receipt:=public.confirm_bank_sync_email_observation(bank,delivery,pi,repeat('a',64),true);
 tx:=(receipt->>'transaction_id')::bigint;
 PERFORM assert_eq(receipt->>'actor_id',actor::text,'resolution actor');
 PERFORM assert_true((receipt->>'checked_internet_banking')::boolean,'attestation stored');
 PERFORM assert_eq(receipt->'facts',event->'data','immutable facts snapshot');
 repeated:=public.confirm_bank_sync_email_observation(bank,delivery,pi,repeat('a',64),true);
 PERFORM assert_eq(repeated,receipt,'same confirmation returns the original receipt');
 UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=oc AND "user"=actor;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'User is not editor.',true,repeat('b',64));
 UPDATE public.occasion_users SET is_editor_order=true WHERE occasion=oc AND "user"=actor;
 PERFORM pg_temp.confirm_error(bank,delivery,pi2,'BANK_SYNC_ALREADY_RESOLVED');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'one credit');
 PERFORM assert_eq(jsonb_array_length((public.get_bank_sync_email_queue_page_v1(bank)->'items')),0,'resolved row leaves queue');
 PERFORM assert_true(public.form_paid_conversion_eligible_internal(oid),'confirmed full bank receipt is conversion eligible');
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=bank AND "user"=actor;
 PERFORM pg_temp.confirm_error(bank,delivery,pi,'User is not an admin for the specified bank account.');
 UPDATE eshop.bank_account_users SET is_admin=true WHERE bank_account=bank AND "user"=actor;
 event:=event||jsonb_build_object('delivery_id',second_delivery,'data',event->'data'||'{"id":"902"}'::jsonb);
 PERFORM public.ingest_bank_sync_transaction('email-confirm','festapp',repeat('a',64),event);
 rows:=(public.get_bank_sync_email_queue_page_v1(bank)->'items');
 PERFORM assert_eq(jsonb_array_length(rows),1,'duplicate of confirmed email stays visible in queue');
 PERFORM assert_eq(jsonb_array_length(rows->0->'possible_duplicates'),1,'queue surfaces related confirmed transaction');
 PERFORM assert_eq((rows#>>'{0,possible_duplicates,0,transaction_id}')::bigint,tx,'possible duplicate points to original credit');
 rows:=(SELECT jsonb_build_object('outcome',i.outcome,'receipt',i.receipt) FROM eshop.bank_sync_inbox i WHERE connection_id=conn AND delivery_id=second_delivery);
 repeated:=public.confirm_bank_sync_email_observation(bank,second_delivery,pi2,repeat('a',64),true);
 PERFORM assert_eq(rows,(SELECT jsonb_build_object('outcome',i.outcome,'receipt',i.receipt) FROM eshop.bank_sync_inbox i WHERE connection_id=conn AND delivery_id=second_delivery),'possible duplicate confirmation preserves committed receipt and outcome');
 PERFORM assert_eq(repeated->>'action','possible_duplicate','duplicate of confirmed email is not auto-resolved');
 PERFORM assert_false((repeated->>'transaction_paired')::boolean,'possible duplicate does not pair without attestation');
 PERFORM assert_eq((repeated#>>'{possible_duplicates,0,transaction_id}')::bigint,tx,'possible duplicate response includes original credit');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=bank),1::bigint,'possible duplicate adds no credit until decided');
 PERFORM public.dismiss_bank_sync_email_observation(bank,second_delivery,repeat('a',64),'Confirmed duplicate notification');
 PERFORM public.remove_transaction_from_payment_info_ws(tx,pi);
 PERFORM assert_false(public.form_paid_conversion_eligible_internal(oid),'unpaired before dispatch cannot qualify');
 PERFORM assert_true(EXISTS(SELECT FROM eshop.transaction_pairing_events WHERE transaction_id=tx
  AND action='unpaired' AND actor_id=actor),'unlink has actor and event timestamp');
 PERFORM assert_eq((SELECT resolution-'possible_duplicate_transaction_ids' FROM eshop.bank_sync_inbox WHERE connection_id=conn AND delivery_id=delivery),receipt,'unlink preserves original confirmation audit');
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Reviewed account alias','FIO',ARRAY['CZK']) RETURNING id INTO alias_bank;
 INSERT INTO eshop.bank_sync_account_aliases(bank_account_id,connection_id) VALUES(alias_bank,conn);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(alias_bank,actor,true);
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,alias_bank);
 UPDATE eshop.payment_info SET bank_account=alias_bank WHERE id=pi2;
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=bank AND "user"=actor;
 PERFORM pg_temp.confirm_error(alias_bank,delivery,pi,'User is not an admin for the specified bank account.',true,repeat('b',64));
 BEGIN
  PERFORM (public.get_bank_sync_email_queue_page_v1(alias_bank)->'items');
  RAISE EXCEPTION 'alias-only admin read queue';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.dismiss_bank_sync_email_observation(alias_bank,delivery,repeat('b',64),'Dismiss');
  RAISE EXCEPTION 'alias-only admin inspected dismissal digest';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE eshop.bank_account_users SET is_admin=true WHERE bank_account=bank AND "user"=actor;
 PERFORM assert_true(public.bank_sync_accounts_match(tx,alias_bank),'confirmed provenance grants reviewed alias matching before API identity');
 PERFORM public.add_transaction_to_payment_info_ws(tx,pi2);
 PERFORM assert_eq((SELECT payment_info FROM eshop.transactions WHERE id=tx),pi2,'disabled bank sales allow verified transaction reassignment');
 PERFORM public.remove_transaction_from_payment_info_ws(tx,pi2);
 PERFORM assert_eq((public.get_transactions_for_order(oid)#>>'{actions,pairingAccountId}')::bigint,bank,
  'order detail offers pairing with bank sales disabled when a receipt is available');
 PERFORM assert_true(public.get_transactions_for_order_all_available(pi2) @> jsonb_build_array(jsonb_build_object('id',tx)),
  'disabled-sales alias picker finds its verified receipt on the canonical ledger');
 PERFORM public.add_transaction_to_payment_info_ws(tx,pi2);
 -- A distinct API movement with identical facts keeps its own identity.
 UPDATE eshop.bank_sync_connections SET mode='api' WHERE id=conn;
 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000903','data',event->'data'||
  '{"id":"903","source":"fio_api","identity_kind":"movement","identity_provenance":"fio_api_column22","transaction_id":"1007903"}'::jsonb);
 repeated:=public.ingest_bank_sync_transaction('email-confirm','festapp',repeat('a',64),event);
 PERFORM assert_eq(repeated->>'outcome','unmatched','identical facts still require review');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=bank),2::bigint,'API movement remains separate');
 PERFORM assert_true((SELECT transaction_id<>tx FROM eshop.bank_transaction_identities
  WHERE instance_id='email-confirm' AND identity_kind='movement'),'movement identity stays with the proven API row');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi2),100::numeric,'review holds the second credit');
 BEGIN
  PERFORM public.add_transaction_to_payment_info_ws(
   (SELECT transaction_id FROM eshop.bank_transaction_identities WHERE instance_id='email-confirm' AND identity_kind='movement'),pi);
  RAISE EXCEPTION 'Expected the pairing guard to reject the held API transaction';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'BANK_SYNC_API_DUPLICATE_REVIEW_REQUIRED' THEN RAISE; END IF;
 END;
 -- Multiple possible confirmed-email matches: store API movement unpaired so
 -- real money is never trapped and nothing double-credits.
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 SELECT bank_account_id,amount,currency,date,vs,counter_account,'banksync_email_confirmed'
 FROM eshop.transactions WHERE id=tx;
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 SELECT bank_account_id,amount,currency,date,vs,counter_account,'banksync_email_confirmed'
 FROM eshop.transactions WHERE id=tx;
 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000904','data',event->'data'||'{"id":"904","transaction_id":"1007904"}'::jsonb);
 repeated:=public.ingest_bank_sync_transaction('email-confirm','festapp',repeat('a',64),event);
 PERFORM assert_eq((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(repeated) k),ARRAY['delivery_id','ok','outcome','receipt_version','refund'],'receipt retains exactly the published keys');
 PERFORM assert_eq(repeated,public.ingest_bank_sync_transaction('email-confirm','festapp',repeat('a',64),event),'ingest replay preserves bounded receipt');
 PERFORM assert_eq(repeated->>'outcome','unmatched','multiple confirmations stored unpaired');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=bank),5::bigint,'API movement recorded in bank ledger');
 PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=(SELECT (diagnostics->>'transaction_id')::bigint FROM eshop.bank_sync_inbox WHERE delivery_id=event->>'delivery_id' AND connection_id=conn)),'ambiguous API movement is not auto-paired');
 PERFORM assert_eq((SELECT jsonb_array_length(diagnostics->'possible_duplicate_transaction_ids') FROM eshop.bank_sync_inbox WHERE delivery_id=event->>'delivery_id' AND connection_id=conn),3,'internal diagnostics record possible duplicate confirmed transactions');
END $$;

-- Small independently scoped cases: real ingest and confirmation, no network.
CREATE FUNCTION pg_temp.email_case() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb:=pg_temp.fixture(NULL); bank bigint; conn bigint; pi bigint; oid bigint; event jsonb;
BEGIN
 SELECT bank_account INTO bank FROM public.forms WHERE id=(x->>'form')::bigint;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,(x->>'actor')::uuid,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES((x->>'unit')::bigint,(x->>'actor')::uuid,true);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
  physical_account,provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at)
 VALUES('email-regression-'||bank,'festapp',bank::text,bank,'account-'||bank,'FIO','email','connected','abcdef0123',repeat('a',64),now()) RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,1007,100,'CZK','bank') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence((x->>'occasion')::bigint),public.generate_order_symbol(),(x->>'occasion')::bigint,
  'ordered','{"name":"Jana Nováková","email":"jana@example.invalid"}',100,'CZK',pi) RETURNING id INTO oid;
 event:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000801',
  'data',jsonb_build_object('id',bank::text,'bank_account_id',bank::text,'amount_cents',10000,'currency','CZK',
   'date','2026-11-22T00:30:00Z','direction','incoming','identity_kind','observation','source','email',
   'raw_vs','1007','counter_account','222/2010','message','Vstupenky'));
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('a',64),event);
 RETURN x||jsonb_build_object('bank',bank,'connection',conn,'payment',pi,'order',oid,'event',event);
END $$;

DO $$
DECLARE x jsonb; bank bigint; pi bigint; tx bigint; event jsonb; receipt jsonb; scenario text; count_before bigint;
BEGIN
 FOREACH scenario IN ARRAY ARRAY['padded_vs','whitespace_vs','split_counter','local_date','counter_conflict','date_conflict','two_candidates','rf','rf_message','missing_email_vs','missing_api_vs'] LOOP
  x:=pg_temp.email_case();bank:=(x->>'bank')::bigint;pi:=(x->>'payment')::bigint;event:=x->'event';
  IF scenario IN ('rf','rf_message') THEN
   UPDATE eshop.bank_accounts SET supported_currencies=ARRAY['CZK','EUR'] WHERE id=bank;
   UPDATE eshop.payment_info SET currency_code='EUR',creditor_reference=public.generate_creditor_reference(1007) WHERE id=pi;
   UPDATE eshop.orders SET currency_code='EUR' WHERE id=(x->>'order')::bigint;
   event:=jsonb_set(event,'{data,currency}','"EUR"');
   event:=jsonb_set(event,'{data,payer_reference}',to_jsonb(public.generate_creditor_reference(1007)));
   IF scenario='rf_message' THEN
    event:=jsonb_set(event,'{data,message}',to_jsonb('Reference '||public.generate_creditor_reference(1007)));
    event:=jsonb_set(event,'{data,payer_reference}','null');
   END IF;
   UPDATE eshop.bank_sync_inbox SET payload=event WHERE connection_id=(x->>'connection')::bigint;
  END IF;
  IF scenario='missing_email_vs' THEN
   UPDATE eshop.bank_sync_inbox SET payload=event #- '{data,raw_vs}' WHERE connection_id=(x->>'connection')::bigint;
  END IF;
  receipt:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true);
  tx:=(receipt->>'transaction_id')::bigint;
  event:=event||jsonb_build_object('delivery_id','01K00000000000000000000802','data',event->'data'||
   '{"id":"802","source":"fio_api","identity_kind":"movement","identity_provenance":"fio_api_column22","transaction_id":"1007802"}'::jsonb);
  IF scenario='missing_api_vs' THEN event:=event #- '{data,raw_vs}';
  ELSIF scenario='padded_vs' THEN event:=jsonb_set(event,'{data,raw_vs}','"00001007"');
  ELSIF scenario='whitespace_vs' THEN event:=jsonb_set(event,'{data,raw_vs}','" 1007 "');
  ELSIF scenario='split_counter' THEN event:=jsonb_set(event,'{data}',event->'data'||'{"counter_account":" 2 2 2 ","bank_code":"2010"}');
  ELSIF scenario='local_date' THEN
   UPDATE eshop.transactions SET date='2026-11-21 23:30' WHERE id=tx;
   event:=jsonb_set(event,'{data,date}','"2026-11-22T12:00:00Z"');
  ELSIF scenario='counter_conflict' THEN event:=jsonb_set(event,'{data,counter_account}','"different notation"');
  ELSIF scenario='date_conflict' THEN event:=jsonb_set(event,'{data,date}','"2026-11-23T12:00:00Z"');
  ELSIF scenario='two_candidates' THEN
   INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
    SELECT bank_account_id,amount,currency,date+interval '1 day',vs,counter_account,ingest_source FROM eshop.transactions WHERE id=tx;
  ELSIF scenario='rf' THEN
   event:=jsonb_set(event,'{data,payer_reference}',to_jsonb(lower(public.generate_creditor_reference(1007))));
  END IF;
  SELECT count(*) INTO count_before FROM eshop.transactions WHERE bank_account_id=bank;
  UPDATE eshop.bank_sync_connections SET mode='api' WHERE id=(x->>'connection')::bigint;
  receipt:=public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('b',64),event);
  PERFORM assert_eq(receipt->>'outcome','unmatched','possible duplicate stored unpaired: '||scenario);
  PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=bank),count_before+1,'movement recorded in ledger: '||scenario);
  PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=(SELECT (diagnostics->>'transaction_id')::bigint FROM eshop.bank_sync_inbox WHERE delivery_id=event->>'delivery_id' AND connection_id=(x->>'connection')::bigint)),'possible duplicate is not auto-paired: '||scenario);
  PERFORM assert_true((SELECT jsonb_array_length(diagnostics->'possible_duplicate_transaction_ids')>=1 FROM eshop.bank_sync_inbox WHERE delivery_id=event->>'delivery_id' AND connection_id=(x->>'connection')::bigint),'possible duplicate ids recorded internally: '||scenario);
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'no double credit on payment_info: '||scenario);
 END LOOP;
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; pi bigint:=(x->>'payment')::bigint;
 conn bigint:=(x->>'connection')::bigint; event jsonb:=x->'event'; receipt jsonb; old bigint; alias_bank bigint;
BEGIN
 -- A prior API movement can have the same facts as a separate email payment.
 -- Scope the prior ledger row to an alias the current actor cannot read.
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies)
 VALUES('Private alias','FIO',ARRAY['CZK']) RETURNING id INTO alias_bank;
 INSERT INTO eshop.bank_sync_account_aliases(bank_account_id,connection_id) VALUES(alias_bank,conn);
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,bank_code,ingest_source)
 VALUES(alias_bank,100,'CZK','2026-11-21 23:00',' 00001007 ','222','2010','fio_api') RETURNING id INTO old;
 event:=jsonb_set(event,'{data,date_offset_min}','60');
 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000802','data',event->'data'||'{"id":"802"}'::jsonb);
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('a',64),event);
 PERFORM assert_eq(public.get_bank_sync_email_queue_page_v1(bank)#>'{items,1,possible_duplicates}',
  '[{"restricted":true}]'::jsonb,'exact-looking API-first email stays in queue with redacted alias hint');
 receipt:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true);
 PERFORM assert_eq(receipt->>'action','possible_duplicate','API-first data is a suggestion');
 PERFORM assert_eq(receipt->'possible_duplicates','[{"restricted":true}]'::jsonb,'confirmation redacts alias facts too');
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(alias_bank,(x->>'actor')::uuid,true);
 PERFORM assert_eq((public.get_bank_sync_email_queue_page_v1(bank)#>>'{items,1,possible_duplicates,0,transaction_id}')::bigint,old,
  'alias bank admin sees candidate details');
 DELETE FROM eshop.bank_account_users WHERE bank_account=alias_bank;
 receipt:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true,true,receipt->>'duplicate_review_token');
 PERFORM assert_eq(receipt->>'action','confirmed','verified separate payment gets its own credit');
 PERFORM assert_true((receipt->>'transaction_id')::bigint<>old,'separate receipts use separate ledger rows');
 PERFORM assert_false(receipt ? 'possible_duplicate_transaction_ids','response omits private candidate IDs');
 PERFORM assert_eq(public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true),receipt,
  'replay preserves response redaction');
 PERFORM assert_eq((SELECT resolution->'possible_duplicate_transaction_ids'
  FROM eshop.bank_sync_inbox WHERE connection_id=conn AND delivery_id=event->>'delivery_id'),jsonb_build_array(old),
  'internal audit retains candidate identity');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; conn bigint:=(x->>'connection')::bigint;
 pi bigint:=(x->>'payment')::bigint; event jsonb:=x->'event'; rows jsonb; result jsonb; v_state text; v_symbol text;
BEGIN
 -- Identifying data and the exact same eligible set in suggestions/manual search.
 rows:=public.find_bank_sync_email_targets_v1(bank,event->'data',' 00001007 ');
 PERFORM assert_eq(jsonb_array_length(rows),1,'manual lookup normalizes VS');
 PERFORM assert_eq(rows->0->>'customer_email','jana@example.invalid','identify customer');
 PERFORM assert_true(rows->0 ? 'order_symbol' AND rows->0 ? 'state','identify order and state');
 PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,event->'data','VS 1007')),1,'lookup parses VS prefix with space');
 PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,event->'data','vs:001007')),1,'lookup parses vs: prefix with leading zeros');
 PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,event->'data','VS=1007')),1,'lookup parses VS= prefix');
 SELECT order_symbol INTO v_symbol FROM eshop.orders WHERE id=(x->>'order')::bigint;
 rows:=public.find_bank_sync_email_targets_v1(bank,event->'data',v_symbol);
 PERFORM assert_eq(jsonb_array_length(rows),1,'lookup by public order number');
 rows:=public.find_bank_sync_email_targets_v1(bank,event->'data',lower(v_symbol));
 PERFORM assert_eq(jsonb_array_length(rows),1,'lookup by lowercase order symbol');
 UPDATE eshop.payment_info SET creditor_reference=public.generate_creditor_reference(1007) WHERE id=pi;
 rows:=public.find_bank_sync_email_targets_v1(bank,event->'data',public.generate_creditor_reference(1007));
 PERFORM assert_eq(jsonb_array_length(rows),1,'manual RF lookup');
 event:=jsonb_set(event,'{data,raw_vs}','null');
 event:=jsonb_set(event,'{data,message}','"VS: 00001007"');
 UPDATE eshop.bank_sync_inbox SET payload=event WHERE connection_id=conn;
 rows:=(public.get_bank_sync_email_queue_page_v1(bank)->'items');
 PERFORM assert_eq(jsonb_array_length(rows->0->'candidates'),1,'message VS suggestions');
 event:=jsonb_set(event,'{data,message}',to_jsonb('Reference '||public.generate_creditor_reference(1007)));
 UPDATE eshop.bank_sync_inbox SET payload=event WHERE connection_id=conn;
 rows:=(public.get_bank_sync_email_queue_page_v1(bank)->'items');
 PERFORM assert_eq(jsonb_array_length(rows->0->'candidates'),1,'message RF suggestions');
 FOREACH v_state IN ARRAY ARRAY['paid','sent','storno','preparing_payment'] LOOP
  UPDATE eshop.orders SET state=v_state WHERE id=(x->>'order')::bigint;
  PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,event->'data','1007')),0,'excluded state: '||v_state);
  PERFORM pg_temp.confirm_error(bank,event->>'delivery_id',pi,'BANK_SYNC_TARGET_MISMATCH');
 END LOOP;
 UPDATE eshop.orders SET state='ordered' WHERE id=(x->>'order')::bigint;
 UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=(x->>'occasion')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,event->'data','1007')),0,'unit B bank admin without order rights sees no lookup results');
 PERFORM pg_temp.confirm_error(bank,event->>'delivery_id',pi,'User is not editor.');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; conn bigint:=(x->>'connection')::bigint;
 event jsonb:=x->'event'; page jsonb; next_page jsonb; row jsonb; resolution jsonb; n integer;
BEGIN
 FOR n IN 2..5 LOOP
  event:=event||jsonb_build_object('delivery_id','01K0000000000000000000080'||n,
   'data',event->'data'||jsonb_build_object('id','email-'||n));
  PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('a',64),event);
 END LOOP;
 page:=public.get_bank_sync_email_queue_page_v1(bank,2,NULL);
 PERFORM assert_eq(jsonb_array_length(page->'items'),2,'first page bounded');
 FOR row IN SELECT value FROM jsonb_array_elements(page->'items') LOOP
  BEGIN
   PERFORM public.dismiss_bank_sync_email_observation(bank,row->>'delivery_id',repeat('a',64),' ');
   RAISE EXCEPTION 'empty dismissal reason accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BANK_SYNC_DISMISS_REASON_REQUIRED' THEN RAISE; END IF; END;
  resolution:=public.dismiss_bank_sync_email_observation(bank,row->>'delivery_id',repeat('a',64),'No incoming payment in banking');
  PERFORM assert_eq(public.dismiss_bank_sync_email_observation(bank,row->>'delivery_id',repeat('a',64),'No incoming payment in banking'),resolution,'dismiss replay stable');
  BEGIN
   PERFORM public.dismiss_bank_sync_email_observation(bank,row->>'delivery_id',repeat('a',64),'Changed reason');
   RAISE EXCEPTION 'dismiss reason was overwritten';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BANK_SYNC_ALREADY_RESOLVED' THEN RAISE; END IF; END;
  PERFORM assert_true(resolution->>'actor_id'=x->>'actor' AND resolution ? 'resolved_at','dismiss audit');
 END LOOP;
 next_page:=public.get_bank_sync_email_queue_page_v1(bank,2,page->'next_cursor');
 PERFORM assert_eq(jsonb_array_length(next_page->'items'),2,'cursor does not skip rows after preceding resolutions');
 PERFORM assert_true(next_page#>>'{items,0,delivery_id}' > page#>>'{items,1,delivery_id}','keyset advances even at equal timestamps');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; pi bigint:=(x->>'payment')::bigint;
 other jsonb; demo_bank bigint; demo_oc bigint; demo_org bigint;
BEGIN
 other:=pg_temp.email_case(); -- actor is the same bootstrap user, but not this account's admin after revoke.
 DELETE FROM eshop.bank_account_users WHERE bank_account=(other->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 PERFORM pg_temp.confirm_error((other->>'bank')::bigint,x#>>'{event,delivery_id}',pi,'User is not an admin for the specified bank account.');
 -- Mark this disposable fixture as demo; no dependency on a retained demo seed.
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,is_listed,sort_order,description,reference_at)
 VALUES((x->>'occasion')::bigint,(x->>'organization')::bigint,'ball','email-test',bank,false,0,'Disposable demo',now());
 PERFORM pg_temp.confirm_error(bank,x#>>'{event,delivery_id}',pi,'DEMO_BANK_ACCOUNT_READ_ONLY');
 DELETE FROM public.demo_occasions WHERE occasion=(x->>'occasion')::bigint;
 -- A demo target is denied even when the receiving account itself is not demo,
 -- and must never be suggested in queue candidates or manual lookup.
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES((other->>'unit')::bigint,bank);
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,is_listed,sort_order,description,reference_at)
 VALUES((x->>'occasion')::bigint,(x->>'organization')::bigint,'ball','email-test',(other->>'bank')::bigint,false,0,'Disposable demo',now());
 PERFORM assert_eq(jsonb_array_length((public.get_bank_sync_email_queue_page_v1(bank)->'items')->0->'candidates'),0,'demo occasion excluded from queue candidates');
 PERFORM assert_eq(jsonb_array_length(public.find_bank_sync_email_targets_v1(bank,x#>'{event,data}','1007')),0,'demo occasion excluded from manual lookup');
 PERFORM pg_temp.confirm_error(bank,x#>>'{event,delivery_id}',pi,'DEMO_OCCASION_READ_ONLY');
END $$;

-- Differential contract against the pre-extraction matcher on real rows.
CREATE FUNCTION pg_temp.original_bank_signals(p_vs text,p_reference text,p_message text,p_identification text,p_comment text)
RETURNS TABLE(kind text,value text) LANGUAGE sql AS $$
  WITH raw_signals(kind, value) AS (
    SELECT 'vs', trim(p_vs)
      WHERE trim(COALESCE(p_vs, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(p_reference)
      WHERE p_reference IS NOT NULL
        AND public.is_valid_creditor_reference(p_reference)
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(m.captures[2])
      FROM regexp_matches(
        upper(concat_ws(E'\n', p_message,
          p_identification, p_comment)),
        '(^|[^A-Z0-9])(RF[0-9]{2}[A-Z0-9[:space:]]{1,25})([^A-Z0-9]|$)', 'g'
      ) AS m(captures)
      WHERE public.is_valid_creditor_reference(m.captures[2])
    UNION ALL
    SELECT 'vs', trim(p_message)
      WHERE nullif(trim(COALESCE(p_vs, '')), '') IS NULL
        AND trim(COALESCE(p_message, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'vs', substring(p_message
      FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})')
      WHERE nullif(trim(COALESCE(p_vs, '')), '') IS NULL
        AND substring(p_message
          FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})') IS NOT NULL
  ), signals AS (
    SELECT DISTINCT kind, value FROM raw_signals
  ) SELECT * FROM signals;
$$;
DO $$
DECLARE
 x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; oc bigint:=(x->>'occasion')::bigint;
 pi_vs1 bigint; pi_vs2 bigint; pi_vs3 bigint; pi_rf1 bigint; pi_rf2 bigint; pi_amb1 bigint; pi_amb2 bigint;
 rf1 text:=public.generate_creditor_reference(1014); rf2 text:=public.generate_creditor_reference(1015);
 sample jsonb; tx_id bigint; expected_ids bigint[]; expected_verdict text; actual jsonb;
BEGIN
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method) VALUES(bank,1011,100,'CZK','bank') RETURNING id INTO pi_vs1;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d1@example.invalid"}',100,'CZK',pi_vs1);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method) VALUES(bank,1012,100,'CZK','bank') RETURNING id INTO pi_vs2;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d2@example.invalid"}',100,'CZK',pi_vs2);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method) VALUES(bank,1013,100,'CZK','bank') RETURNING id INTO pi_vs3;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d3@example.invalid"}',100,'CZK',pi_vs3);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,creditor_reference,amount,currency_code,payment_method) VALUES(bank,1014,rf1,100,'CZK','bank') RETURNING id INTO pi_rf1;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d4@example.invalid"}',100,'CZK',pi_rf1);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,creditor_reference,amount,currency_code,payment_method) VALUES(bank,1015,rf2,100,'CZK','bank') RETURNING id INTO pi_rf2;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d5@example.invalid"}',100,'CZK',pi_rf2);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method) VALUES(bank,1016,100,'CZK','bank') RETURNING id INTO pi_amb1;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d6@example.invalid"}',100,'CZK',pi_amb1);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method) VALUES(bank,1016,100,'CZK','bank') RETURNING id INTO pi_amb2;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info) VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"d7@example.invalid"}',100,'CZK',pi_amb2);

 FOR sample IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('label','exact_vs','vs','1011'),
  jsonb_build_object('label','padded_vs','vs',' 00001012 '),
  jsonb_build_object('label','message_vs','message','VS: 00001013'),
  jsonb_build_object('label','invalid_vs_no_fallback','vs','invalid','message','VS: 1011'),
  jsonb_build_object('label','rf_lower','ref',lower(rf1)),
  jsonb_build_object('label','rf_message','message','Reference '||rf2),
  jsonb_build_object('label','ambiguous_vs','vs','1016'),
  jsonb_build_object('label','unmatched','message','No reference here')
 )) LOOP
  INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,payer_reference,message_for_recipient,user_identification,comment,ingest_source)
  VALUES(bank,100,'CZK','2026-11-22 12:00',sample->>'vs',sample->>'ref',sample->>'message',sample->>'identification',sample->>'comment','banksync_api')
  RETURNING id INTO tx_id;

  SELECT array_agg(DISTINCT p.id ORDER BY p.id) INTO expected_ids
  FROM pg_temp.original_bank_signals(sample->>'vs',sample->>'ref',sample->>'message',sample->>'identification',sample->>'comment') s
  JOIN eshop.payment_info p
    ON (s.kind='rf' AND p.creditor_reference=s.value)
    OR (s.kind='vs' AND p.variable_symbol=CASE WHEN s.kind='vs' THEN s.value::bigint END)
  WHERE p.bank_account=bank AND upper(trim(p.currency_code))='CZK';

  expected_verdict:=CASE
   WHEN expected_ids IS NULL OR cardinality(expected_ids)=0 THEN 'unmatched'
   WHEN cardinality(expected_ids)=1 THEN 'paired'
   ELSE 'ambiguous' END;

  actual:=public.match_bank_transaction(tx_id);
  PERFORM assert_eq(actual->>'verdict',expected_verdict,'real match_bank_transaction verdict: '||(sample->>'label'));
  IF expected_verdict='paired' THEN
   PERFORM assert_eq((actual->>'payment_info_id')::bigint,expected_ids[1],'real match_bank_transaction target: '||(sample->>'label'));
   PERFORM assert_eq((SELECT payment_info FROM eshop.transactions WHERE id=tx_id),expected_ids[1],'transaction row paired: '||(sample->>'label'));
  ELSE
   PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=tx_id),'unmatched/ambiguous stays unpaired: '||(sample->>'label'));
  END IF;
 END LOOP;
END $$;

-- N2: Missing signals are NOT a wildcard; no-VS payments with different VS or
-- counter-account are distinct; same-counter-account no-VS flags possible_duplicate
-- and supports explicit p_not_duplicate=true attestation.
DO $$
DECLARE
 x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; conn bigint:=(x->>'connection')::bigint;
 oc bigint:=(x->>'occasion')::bigint; pi bigint:=(x->>'payment')::bigint; pi2 bigint;
 ev1 jsonb; ev2 jsonb; receipt jsonb; tx1 bigint; tx2 bigint;
BEGIN
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,2002,100,'CZK','bank') RETURNING id INTO pi2;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,'ordered','{"email":"second@example.invalid"}',100,'CZK',pi2);
 -- Same amount/date/currency payments that must NOT block a no-VS email:
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 VALUES(bank,100,'CZK','2026-11-22 12:00','9999','111/2010','banksync_email_confirmed');
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 VALUES(bank,100,'CZK','2026-11-22 12:00',NULL,'333/2010','banksync_api');

 ev1:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000701',
  'data',jsonb_build_object('id','701','bank_account_id',bank::text,'amount_cents',10000,'currency','CZK',
   'date','2026-11-22T12:00:00Z','direction','incoming','identity_kind','observation','source','email',
   'counter_account','222/2010','message','Platba bez symbolu'));
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('c',64),ev1);
 receipt:=public.confirm_bank_sync_email_observation(bank,'01K00000000000000000000701',pi,repeat('c',64),true);
 PERFORM assert_eq(receipt->>'action','confirmed','no-VS email is not wildcard-blocked by other same-amount payments');
 PERFORM assert_true((receipt->>'transaction_paired')::boolean,'no-VS email paired cleanly');
 PERFORM assert_false((receipt->>'not_duplicate')::boolean,'no duplicate override needed');
 tx1:=(receipt->>'transaction_id')::bigint;

 -- Second no-VS email with matching normalized counter-account IS a possible duplicate:
 ev2:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000702',
  'data',jsonb_build_object('id','702','bank_account_id',bank::text,'amount_cents',10000,'currency','CZK',
   'date','2026-11-22T12:00:00Z','direction','incoming','identity_kind','observation','source','email',
   'counter_account',' 2 2 2 ','bank_code','2010','message','Druha platba bez symbolu'));
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('d',64),ev2);
 receipt:=public.confirm_bank_sync_email_observation(bank,'01K00000000000000000000702',pi2,repeat('d',64),true);
 PERFORM assert_eq(receipt->>'action','possible_duplicate','matching counter-account no-VS triggers possible_duplicate');
 PERFORM assert_false((receipt->>'transaction_paired')::boolean,'possible_duplicate does not pair');
 PERFORM assert_eq((receipt#>>'{possible_duplicates,0,transaction_id}')::bigint,tx1,'surfaces related confirmed tx');
 -- Explicit confirm-anyway attestation creates a separate audited payment:
 receipt:=public.confirm_bank_sync_email_observation(bank,'01K00000000000000000000702',pi2,repeat('d',64),true,true,receipt->>'duplicate_review_token');
 PERFORM assert_eq(receipt->>'action','confirmed','confirm-anyway succeeds with p_not_duplicate=true');
 PERFORM assert_true((receipt->>'not_duplicate')::boolean,'not_duplicate attestation stored in resolution');
 PERFORM assert_true((receipt->>'transaction_paired')::boolean,'separate payment paired');
 tx2:=(receipt->>'transaction_id')::bigint;
 PERFORM assert_true(tx2<>tx1,'separate transaction created');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi2),100::numeric,'second order paid');
 PERFORM assert_true(EXISTS(SELECT FROM eshop.transaction_pairing_events
  WHERE transaction_id=tx2 AND action='paired' AND details->>'not_duplicate'='true'),'pairing audit records not_duplicate');

 PERFORM assert_false(has_function_privilege('service_role','public.bank_sync_fact_dates_match_internal(eshop.transactions,jsonb,integer)','EXECUTE'),
  'email date comparator stays private');
 PERFORM assert_true(has_function_privilege('service_role','public.bank_sync_existing_facts_match(eshop.transactions,jsonb)','EXECUTE'),
  'service_role granted bank_sync_existing_facts_match');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; unit_b bigint; occasion_b bigint; pi_b bigint; candidate jsonb;
BEGIN
 INSERT INTO public.units(title,organization) VALUES('Second organizer',(x->>'organization')::bigint) RETURNING id INTO unit_b;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit_b,bank);
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Second event',(x->>'organization')::bigint,unit_b,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occasion_b;
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,1007,100,'CZK','bank') RETURNING id INTO pi_b;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(occasion_b),public.generate_order_symbol(),occasion_b,'ordered','{"email":"second@example.invalid"}',100,'CZK',pi_b);
 PERFORM assert_true(public.can_manage_bank_account(bank),'account manager retains unit A authority');
 PERFORM pg_temp.confirm_error(bank,x#>>'{event,delivery_id}',pi_b,'User is not editor.');
 FOR candidate IN SELECT value FROM jsonb_array_elements(public.find_bank_sync_email_targets_v1(bank,x#>'{event,data}','1007')) LOOP
  PERFORM assert_false((candidate->>'payment_info_id')::bigint=pi_b,'unit B order without editing permission excluded from lookup');
 END LOOP;
END $$;


DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; conn bigint:=(x->>'connection')::bigint;
 pi bigint:=(x->>'payment')::bigint; order_id bigint:=(x->>'order')::bigint;
 event jsonb:=x->'event'; receipt jsonb; state text;
BEGIN
 UPDATE eshop.payment_info SET amount=200,deposit_amount=100 WHERE id=pi;
 UPDATE eshop.orders SET price=200 WHERE id=order_id;
 receipt:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true);
 PERFORM assert_eq(receipt->>'action','confirmed','first email pays the deposit');
 SELECT o.state INTO state FROM eshop.orders o WHERE id=order_id;
 PERFORM assert_true(state IN ('paid','sent'),'deposit makes admission eligible');
 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000802','data',event->'data'||'{"id":"802"}'::jsonb);
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('b',64),event);
 PERFORM assert_eq((public.get_bank_sync_email_queue_page_v1(bank)#>>'{items,0,candidates,0,remaining_due}')::numeric,
  100::numeric,'queue suggests deposit order with balance');
 PERFORM assert_eq((public.find_bank_sync_email_targets_v1(bank,event->'data','1007')#>>'{0,remaining_due}')::numeric,
  100::numeric,'lookup finds remaining deposit balance');
 receipt:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('b',64),true,true,
  public.get_bank_sync_email_queue_page_v1(bank)#>>'{items,0,duplicate_review_token}');
 PERFORM assert_eq(receipt->>'action','confirmed','second distinct email movement settles the balance');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),200::numeric,'deposit and balance credited once each');
 PERFORM assert_eq(public.find_bank_sync_email_targets_v1(bank,event->'data','1007'),'[]'::jsonb,'settled order excluded');
END $$;


DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; conn bigint:=(x->>'connection')::bigint;
 pi bigint:=(x->>'payment')::bigint; oid bigint:=(x->>'order')::bigint; event jsonb:=x->'event';
 out jsonb; replay jsonb; review jsonb; original bigint; api bigint;
BEGIN
 UPDATE eshop.payment_info SET amount=200,deposit_amount=100 WHERE id=pi;
 UPDATE eshop.orders SET price=200 WHERE id=oid;
 out:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true);
 original:=(out->>'transaction_id')::bigint;
 event:=jsonb_set(event,'{delivery_id}','"01K00000000000000000000802"');
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('b',64),event);
 PERFORM assert_eq(public.get_bank_sync_email_queue_page_v1(bank)->'items','[]'::jsonb,
  'new delivery of resolved source observation stays out of queue');
 replay:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('b',64),true,true);
 PERFORM assert_eq(replay,out,'same source observation reuses audited confirmation across delivery IDs');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'repeat source observation cannot pay the balance');

 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000803','data',event->'data'||
  '{"id":"803","source":"fio_api","identity_kind":"movement","identity_provenance":"fio_api_column22","transaction_id":"1007803"}'::jsonb);
 out:=public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('c',64),event);
 PERFORM assert_eq(out->>'outcome','unmatched','later API candidate is held for review');
 SELECT transaction_id INTO api FROM eshop.bank_transaction_identities
  WHERE instance_id='email-regression-'||bank AND identity_kind='movement' AND identity_value='1007803';
 PERFORM assert_true(api<>original,'API identity remains on its own ledger row');
 review:=public.get_transactions_for_order_all_available(pi)#>'{0,bankSyncReview}';
 PERFORM assert_eq((review#>>'{possible_duplicates,0,transaction_id}')::bigint,original,'normal picker exposes review on held API row');
 out:=public.resolve_bank_sync_api_duplicate_v1(api,pi,review->>'review_token',original);
 PERFORM assert_eq(out->>'action','api_same_movement','same movement reviewed');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'equivalent API entry adds no credit');
 PERFORM assert_eq((SELECT transaction_id FROM eshop.transactions WHERE id=api),1007803::bigint,'bank-provided ID retained');
 PERFORM assert_true(public.get_transactions_for_order_all_available(pi) IS NULL,'reviewed duplicate not offered for another credit');
 PERFORM assert_eq(public.resolve_bank_sync_api_duplicate_v1(api,pi,review->>'review_token',original),out,'same decision is replayable');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; pi bigint:=(x->>'payment')::bigint;
 event jsonb:=x->'event'; out jsonb; reviewed text; tx bigint;
BEGIN
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 VALUES(bank,100,'CZK','2026-11-22 12:00','1007','222/2010','fio_api');
 reviewed:=public.get_bank_sync_email_queue_page_v1(bank)#>>'{items,0,duplicate_review_token}';
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,vs,counter_account,ingest_source)
 VALUES(bank,100,'CZK','2026-11-22 12:00','1007','222/2010','fio_api') RETURNING id INTO tx;
 out:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true,true,reviewed);
 PERFORM assert_eq(out->>'action','possible_duplicate','stale duplicate acknowledgement is rejected');
 PERFORM assert_eq(jsonb_array_length(out->'possible_duplicates'),2,'new candidates returned for review');
 PERFORM assert_true(out->>'duplicate_review_token'<>reviewed,'review token binds candidate identity');
 out:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true,true,out->>'duplicate_review_token');
 PERFORM assert_eq(out->>'action','confirmed','updated acknowledgement accepted');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.email_case(); bank bigint:=(x->>'bank')::bigint; pi bigint:=(x->>'payment')::bigint;
 oc bigint:=(x->>'occasion')::bigint; actor uuid:=(x->>'actor')::uuid; event jsonb:=x->'event';
 other_occ bigint; target_pi bigint; original bigint; api bigint; result jsonb; review jsonb;
BEGIN
 result:=public.confirm_bank_sync_email_observation(bank,event->>'delivery_id',pi,repeat('a',64),true);
 original:=(result->>'transaction_id')::bigint;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Target event',(x->>'organization')::bigint,(x->>'unit')::bigint,gen_random_uuid()::text,now(),now()+interval '1 day')
 RETURNING id INTO other_occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view)
 VALUES(other_occ,actor,true,true);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,payment_method)
 VALUES(bank,2008,100,'CZK','bank') RETURNING id INTO target_pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code,payment_info)
 VALUES(public.next_order_sequence(other_occ),public.generate_order_symbol(),other_occ,'ordered','{"email":"other@example.invalid"}',100,'CZK',target_pi);

 UPDATE public.occasion_users SET is_editor_order=false WHERE occasion=oc AND "user"=actor;
 BEGIN
  PERFORM public.add_transaction_to_payment_info_ws(original,target_pi);
  RAISE EXCEPTION 'Expected original-order authorization to deny remapping';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'User is not editor.' THEN RAISE; END IF;
 END;
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'original order credit retained');

 event:=event||jsonb_build_object('delivery_id','01K00000000000000000000803','data',event->'data'||
  '{"id":"803","source":"fio_api","identity_kind":"movement","identity_provenance":"fio_api_column22","transaction_id":"1007803"}'::jsonb);
 PERFORM public.ingest_bank_sync_transaction('email-regression-'||bank,'festapp',repeat('b',64),event);
 SELECT transaction_id INTO api FROM eshop.bank_transaction_identities
 WHERE instance_id='email-regression-'||bank AND identity_kind='movement' AND identity_value='1007803';
 BEGIN
  PERFORM public.add_transaction_to_payment_info_ws(api,target_pi);
  RAISE EXCEPTION 'Expected ordinary attachment to reject held API transaction';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'BANK_SYNC_API_DUPLICATE_REVIEW_REQUIRED' THEN RAISE; END IF;
 END;
 review:=public.get_transactions_for_order_all_available(target_pi)#>'{0,bankSyncReview}';
 result:=public.resolve_bank_sync_api_duplicate_v1(api,target_pi,'old-token',NULL);
 PERFORM assert_eq(result->>'action','review_changed','API review refuses stale attestation');
 result:=public.resolve_bank_sync_api_duplicate_v1(api,target_pi,review->>'review_token',NULL);
 PERFORM assert_eq(result->>'action','api_distinct','separate verified movement is paired');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=target_pi),100::numeric,'separate movement credits the selected order once');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'original receipt remains credited to its own order');
 PERFORM assert_eq((SELECT transaction_id FROM eshop.transactions WHERE id=api),1007803::bigint,'separate movement keeps the original bank ID');
END $$;
