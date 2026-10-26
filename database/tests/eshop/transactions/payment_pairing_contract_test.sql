DO $$
DECLARE
  v_bank bigint;
  v_other_bank bigint;
  v_pi bigint;
  v_other_pi bigint;
  v_transaction bigint;
  v_reference text;
  v_result jsonb;
BEGIN
  v_reference := public.generate_creditor_reference(1234567890);
  PERFORM assert_eq(v_reference, 'RF471234567890',
    'RF must preserve the complete ten-digit VS after its checksum');
  PERFORM assert_true(public.is_valid_creditor_reference(v_reference), 'generated RF must validate');
  PERFORM assert_true(v_reference ~ '^RF[0-9]{3,}$', 'RF payload after checksum is numeric');
  PERFORM assert_false(public.is_valid_creditor_reference(left(v_reference, 3) ||
    CASE substring(v_reference, 4, 1) WHEN '9' THEN '8' ELSE '9' END || substring(v_reference, 5)),
    'changed checksum must fail');

  INSERT INTO eshop.bank_accounts(title, type, account_number, supported_currencies)
  VALUES ('Pairing test', 'FIO', 'DE71110220330123456789', ARRAY['EUR']) RETURNING id INTO v_bank;
  INSERT INTO eshop.payment_info(bank_account, variable_symbol, amount, currency_code, creditor_reference)
  VALUES (v_bank, 1234567890, 10, 'EUR', v_reference) RETURNING id INTO v_pi;

  BEGIN
    UPDATE eshop.payment_info SET variable_symbol = 1234567891 WHERE id = v_pi;
    RAISE EXCEPTION 'RF-linked VS mutation unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO eshop.bank_accounts(title, type, account_number, supported_currencies)
  VALUES ('Other creditor', 'FIO', 'DE02120300000000202051', ARRAY['EUR'])
  RETURNING id INTO v_other_bank;
  INSERT INTO eshop.payment_info(bank_account, variable_symbol, amount, currency_code, creditor_reference)
  VALUES (v_other_bank, 1234567890, 10, 'EUR', v_reference);
  INSERT INTO eshop.transactions(date, amount, currency, bank_account_id, message_for_recipient,
    transaction_id, ingest_source)
  VALUES (now(), 10, 'EUR', v_bank, v_reference, 900000001, 'fio_api') RETURNING id INTO v_transaction;

  v_result := public.match_bank_transaction(v_transaction);
  PERFORM assert_eq(v_result->>'verdict', 'paired', 'valid RF must pair');
  PERFORM assert_eq((SELECT payment_info FROM eshop.transactions WHERE id = v_transaction), v_pi,
    'matcher must attach expected payment info');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id = v_pi), 10::numeric,
    'canonical mutation must recalculate paid');

  v_result := public.match_bank_transaction(v_transaction);
  PERFORM assert_eq(v_result->>'verdict', 'already_paired', 'matcher replay must be idempotent');
  PERFORM assert_eq((SELECT count(*) FROM eshop.transaction_pairing_events
    WHERE transaction_snapshot_id = v_transaction), 1::bigint, 'replay must not duplicate audit');

  PERFORM public.apply_transaction_pairing(v_transaction, NULL, 'test_unlink', 'system');
  PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id = v_pi), 0::numeric,
    'unlink must recalculate paid from rows');

  INSERT INTO eshop.payment_info(bank_account, variable_symbol, amount, currency_code)
  VALUES (v_bank, 777777, 10, 'EUR') RETURNING id INTO v_other_pi;
  INSERT INTO eshop.payment_info(bank_account, variable_symbol, amount, currency_code)
  VALUES (v_bank, 777777, 10, 'EUR');
  INSERT INTO eshop.transactions(date, amount, currency, bank_account_id, message_for_recipient,
    transaction_id, ingest_source)
  VALUES (now(), 10, 'EUR', v_bank, 'VS: 777777', 900000002, 'fio_api') RETURNING id INTO v_transaction;
  v_result := public.match_bank_transaction(v_transaction);
  PERFORM assert_eq(v_result->>'verdict', 'ambiguous', 'duplicate VS must not use LIMIT 1');
  PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id = v_transaction),
    'ambiguous transaction must remain unpaired');

  INSERT INTO eshop.transactions(date, amount, currency, bank_account_id, message_for_recipient,
    transaction_id, ingest_source)
  VALUES (now(), 10, 'EUR', v_bank, 'Invoice 777777 for customer', 900000003, 'fio_api')
  RETURNING id INTO v_transaction;
  v_result := public.match_bank_transaction(v_transaction);
  PERFORM assert_eq(v_result->>'verdict', 'unmatched', 'unlabelled number in prose must not match');
END;
$$;
