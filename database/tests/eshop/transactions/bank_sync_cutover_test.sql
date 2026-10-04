-- Historical rows retain their identities and manual pairing decisions on replay.
DO $$
DECLARE bank bigint; connection bigint; tx bigint; receipt jsonb; envelope jsonb;
BEGIN
  INSERT INTO eshop.bank_accounts(title,type,account_number) VALUES('Cutover fixture','FIO','12345/2010') RETURNING id INTO bank;
  INSERT INTO eshop.transactions(bank_account_id,transaction_id,amount,currency,date,vs,ingest_source)
    VALUES(bank,887766,10,'CZK','2026-10-04 12:00:00','12345','legacy') RETURNING id INTO tx;
  INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES(bank,12345,10,'CZK');
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256)
    VALUES('cutover-test','festapp','88',bank,'12345/2010','FIO','api','provisioning','abcdef0123',repeat('a',64)) RETURNING id INTO connection;
  PERFORM public.activate_bank_sync_connection(connection,repeat('a',64));
  PERFORM assert_true(NOT (SELECT is_fetch_enabled FROM eshop.bank_accounts WHERE id=bank),'old polling fenced');
  PERFORM assert_eq((SELECT transaction_id FROM eshop.bank_transaction_identities WHERE instance_id='cutover-test'),tx,'historical movement adopted');
  envelope:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000001',
    'data',jsonb_build_object('id',88,'bank_account_id',88,'amount_cents',1000,'currency','CZK','date','2026-10-04T12:00:00Z',
      'direction','incoming','identity_kind','movement','identity_provenance','fio_api_column22','source','fio_api',
      'transaction_id','887766','raw_vs','12345'));
  receipt:=public.ingest_bank_sync_transaction('cutover-test','festapp',repeat('a',64),envelope);
  PERFORM assert_eq(receipt->>'outcome','already_ingested','history not imported again');
  PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=tx),'manual unpair survives replay');
  PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=bank),1::bigint,'no duplicate movement');
  envelope:=jsonb_set(envelope,'{delivery_id}','"01K00000000000000000000002"');
  envelope:=jsonb_set(envelope,'{data,amount_cents}','2000');
  receipt:=public.ingest_bank_sync_transaction('cutover-test','festapp',repeat('b',64),envelope);
  PERFORM assert_eq(receipt->>'outcome','quarantined_conflict','changed historical bank facts are quarantined');
  PERFORM assert_eq((SELECT amount FROM eshop.transactions WHERE id=tx),10::numeric,'ledger amount preserved');
END $$;
