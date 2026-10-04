-- A failing domain side-effect must roll back ledger, identity and receipt.
ALTER TABLE eshop.transaction_pairing_events ADD CONSTRAINT banksync_test_fault
  CHECK(method <> 'automatic_reference') NOT VALID;
DO $$
DECLARE v_bank bigint; v_event jsonb;
BEGIN
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync fault fixture','FIO','8888/2010',ARRAY['CZK']) RETURNING id INTO v_bank;
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256,legacy_blocked_at)
    VALUES('test-fault','festapp','44',v_bank,'8888/2010','FIO','api','connected','abcdef0123',repeat('a',64),now());
  INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES(v_bank,12345,10,'CZK');
  v_event:=jsonb_build_object('event','transaction.received','event_version','2','delivery_id','01K00000000000000000000001','pairing_code','abcdef0123',
    'data',jsonb_build_object('id',1,'bank_account_id',44,'amount_cents',1000,'currency','CZK','date','2026-10-04T12:00:00Z',
      'direction','incoming','identity_kind','movement','identity_provenance','fio_api_column22','source','fio_api','transaction_id','990001','raw_vs','12345','payer_reference',NULL));
  BEGIN
    PERFORM public.ingest_bank_sync_transaction('test-fault','festapp',repeat('a',64),v_event);
    RAISE EXCEPTION 'matcher fault was swallowed';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE bank_account_id=v_bank),0::bigint,'failed matcher rolls back ledger');
  PERFORM assert_eq((SELECT count(*) FROM eshop.bank_sync_inbox WHERE instance_id='test-fault'),0::bigint,'no receipt before domain commit');
  PERFORM assert_eq((SELECT count(*) FROM eshop.bank_transaction_identities WHERE instance_id='test-fault'),0::bigint,'no surviving identity after failure');
END;
$$;
