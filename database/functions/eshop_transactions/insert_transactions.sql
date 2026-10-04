CREATE OR REPLACE FUNCTION public.insert_transactions(transactions jsonb, bank_account_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_input jsonb;
  v_date timestamptz;
  v_id bigint;
  v_movement_id bigint;
  v_result jsonb;
  v_items jsonb := '[]'::jsonb;
  v_inserted integer := 0;
  v_skipped integer := 0;
BEGIN
  PERFORM public.require_service_role();
  PERFORM public.require_legacy_bank_authority(bank_account_id);
  IF jsonb_typeof(transactions) <> 'array' THEN RAISE EXCEPTION 'TRANSACTIONS_ARRAY_REQUIRED'; END IF;

  FOR v_input IN SELECT value FROM jsonb_array_elements(transactions) LOOP
    BEGIN
      v_date := (v_input->'column0'->>'value')::timestamptz;
      v_movement_id := nullif(v_input->'column22'->>'value', '')::bigint;
    EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
      v_skipped := v_skipped + 1;
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'ingest_status', 'failed', 'reason', 'invalid_bank_payload'));
      CONTINUE;
    END;

    SELECT t.id INTO v_id FROM eshop.transactions t
    WHERE t.bank_account_id = insert_transactions.bank_account_id
      AND t.transaction_id = v_movement_id;
    IF v_id IS NOT NULL THEN
      v_skipped := v_skipped + 1;
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id,
        'ingest_status', 'skipped', 'match_verdict', 'already_ingested'));
      CONTINUE;
    END IF;

    INSERT INTO eshop.transactions (
      transaction_id, date, amount, currency, counter_account, bank_code,
      bank_name, ks, vs, ss, user_identification, transaction_type,
      performed_by, comment, command_id, bank_account_id,
      message_for_recipient, counter_account_name, payer_reference, ingest_source
    ) VALUES (
      v_movement_id, v_date, (v_input->'column1'->>'value')::numeric,
      v_input->'column14'->>'value', v_input->'column2'->>'value',
      v_input->'column3'->>'value', v_input->'column12'->>'value',
      nullif(v_input->'column4'->>'value', ''), nullif(v_input->'column5'->>'value', ''),
      nullif(v_input->'column6'->>'value', ''), v_input->'column7'->>'value',
      v_input->'column8'->>'value', v_input->'column9'->>'value',
      v_input->'column25'->>'value', nullif(v_input->'column17'->>'value', '')::bigint,
      bank_account_id, v_input->'column16'->>'value', v_input->'column10'->>'value',
      v_input->'column27'->>'value', 'fio_api'
    ) RETURNING id INTO v_id;
    v_inserted := v_inserted + 1;

    BEGIN
      v_result := public.match_bank_transaction(v_id);
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id, 'ingest_status', 'inserted',
        'match_verdict', v_result->>'verdict', 'reason', v_result->>'reason'));
    EXCEPTION WHEN OTHERS THEN
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'source_id', v_movement_id, 'stored_id', v_id, 'ingest_status', 'inserted',
        'match_verdict', 'failed', 'reason', SQLSTATE));
    END;
  END LOOP;

  RETURN jsonb_build_object('inserted', v_inserted, 'skipped', v_skipped, 'items', v_items);
END;
$$;

CREATE INDEX IF NOT EXISTS idx_transaction_id ON eshop.transactions (transaction_id);
REVOKE ALL ON FUNCTION public.insert_transactions(jsonb,bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.insert_transactions(jsonb,bigint) TO service_role;
