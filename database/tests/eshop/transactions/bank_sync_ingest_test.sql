DO $$
DECLARE
  v_bank bigint; v_alias bigint; v_connection bigint; v_pi bigint; v_pi2 bigint; v_old bigint;
  v_event jsonb; v_result jsonb; v_receipt jsonb; v_count bigint;
BEGIN
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync fixture','FIO','1234/2010',ARRAY['EUR']) RETURNING id INTO v_bank;
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync alias','FIO','CZ6508000000192000145399',ARRAY['EUR']) RETURNING id INTO v_alias;
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,
    physical_account,provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at)
    VALUES('test','festapp','42',v_bank,'1234/2010','FIO','api','connected','0123456789',repeat('a',64),now()) RETURNING id INTO v_connection;
  INSERT INTO eshop.bank_sync_account_aliases VALUES(v_alias,v_connection);
  INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code,creditor_reference)
    VALUES(v_alias,1234567890,20,'EUR',public.generate_creditor_reference(1234567890)) RETURNING id INTO v_pi;
  v_event:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000001','pairing_code','0123456789',
    'data',jsonb_build_object('id',1,'bank_account_id',42,'amount_cents',1000,'currency','EUR','date','2026-10-04T12:00:00Z',
      'direction','incoming','identity_kind','movement','identity_provenance','fio_api_column22','source','fio_api',
      'transaction_id','900001','raw_vs',NULL,'payer_reference','RF471234567890'));
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','paired','alias RF must pair through the existing engine');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=v_pi),10::numeric,'exact EUR amount');
  v_receipt:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result,v_receipt,'stable committed receipt');
  BEGIN
    PERFORM public.ingest_bank_sync_transaction('test','festapp',repeat('b',64),v_event);
    RAISE EXCEPTION 'changed delivery body was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_DELIVERY_CONFLICT' THEN RAISE; END IF;
  END;
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000002"');
  v_event:=jsonb_set(v_event,'{data,id}','2');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','already_ingested','new delivery and D1 row preserve financial identity');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=v_pi),10::numeric,'retry does not repay');
  PERFORM assert_eq((SELECT count(*) FROM eshop.transaction_pairing_events WHERE new_payment_info_id=v_pi),1::bigint,'one pairing audit');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000003"');
  v_event:=jsonb_set(v_event,'{data,id}','3');
  v_event:=jsonb_set(v_event,'{data,transaction_id}','"900002"');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','paired','second real identical payment must survive');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=v_pi),20::numeric,'second movement is another 10 EUR');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000004"');
  v_event:=jsonb_set(v_event,'{data,id}','4');
  v_event:=jsonb_set(v_event,'{data,transaction_id}','"900003"');
  v_event:=jsonb_set(v_event,'{data,amount_cents}','-1000');
  v_event:=jsonb_set(v_event,'{data,direction}','"outgoing"');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','stored_outgoing','signed debit stays in ledger');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=v_pi),20::numeric,'debit is not a manual refund');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000005"');
  v_event:=jsonb_set(v_event,'{data,id}','5');
  v_event:=jsonb_set(v_event,'{data,transaction_id}','"900004"');
  v_event:=jsonb_set(v_event,'{data,amount_cents}','0');
  v_event:=jsonb_set(v_event,'{data,direction}','"zero"');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','stored_zero','zero facts stay in ledger');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000006"');
  v_event:=jsonb_set(v_event,'{data,id}','6');
  v_event:=jsonb_set(v_event,'{data,transaction_id}','"900002"');
  v_event:=jsonb_set(v_event,'{data,amount_cents}','1100');
  v_event:=jsonb_set(v_event,'{data,direction}','"incoming"');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','quarantined_conflict','changed movement facts quarantined');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000007"');
  v_event:=jsonb_set(v_event,'{data,id}','7');
  v_event:=jsonb_set(v_event,'{data,identity_kind}','"observation"');
  v_event:=jsonb_set(v_event,'{data,source}','"email"');
  v_event:=jsonb_set(v_event,'{data,identity_provenance}','"authenticated_email_unverified_movement"');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','quarantined_identity','email observation never independently credits');
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000008"');
  v_event:=jsonb_set(v_event,'{data,bank_account_id}','999999');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','quarantined_scope','signed unknown remote mapping retained');
  PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=v_bank),4::bigint,'one ledger copy per real movement');

  -- Link existing imported history without touching pairing or audit.
  INSERT INTO eshop.transactions(bank_account_id,transaction_id,amount,currency,date,ingest_source)
    VALUES(v_bank,900009,5,'EUR','2026-10-04','fio_api') RETURNING id INTO v_old;
  v_event:=jsonb_set(v_event,'{delivery_id}','"01K00000000000000000000009"');
  v_event:=jsonb_set(v_event,'{data,bank_account_id}',to_jsonb(42));
  v_event:=jsonb_set(v_event,'{data,id}','9');
  v_event:=jsonb_set(v_event,'{data,identity_kind}','"movement"');
  v_event:=jsonb_set(v_event,'{data,source}','"fio_api"');
  v_event:=jsonb_set(v_event,'{data,identity_provenance}','"fio_api_column22"');
  v_event:=jsonb_set(v_event,'{data,transaction_id}','"900009"');
  v_event:=jsonb_set(v_event,'{data,amount_cents}','500');
  v_event:=jsonb_set(v_event,'{data,payer_reference}','null');
  v_result:=public.ingest_bank_sync_transaction('test','festapp',repeat('a',64),v_event);
  PERFORM assert_eq(v_result->>'outcome','already_ingested','legacy movement only linked');
  PERFORM assert_eq((SELECT transaction_id FROM eshop.bank_transaction_identities WHERE instance_id='test' AND identity_kind='movement' AND identity_value='900009'),v_old,'existing ledger identity retained');
  BEGIN
    PERFORM public.insert_transactions('[]',v_bank);
    RAISE EXCEPTION 'legacy authority bypassed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.process_email_transaction(jsonb_build_object('bank_account_id',v_alias));
    RAISE EXCEPTION 'email alias authority bypassed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED' THEN RAISE; END IF;
  END;
END;
$$;
