CREATE OR REPLACE FUNCTION public.process_email_transaction(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bank_account_id bigint := (p_data->>'bank_account_id')::bigint;
  v_external_id text := nullif(p_data->>'external_id', '');
  v_movement_id bigint := nullif(p_data->>'movement_id', '')::bigint;
  v_command_id bigint := nullif(p_data->>'bank_command_id', '')::bigint;
  v_source text := COALESCE(nullif(p_data->>'ingest_source', ''), 'legacy_email');
  v_existing_id bigint;
  v_id bigint;
  v_match jsonb;
BEGIN
  PERFORM public.require_service_role();
  PERFORM public.require_legacy_bank_authority(v_bank_account_id);
  IF v_source NOT IN ('fio_email', 'airbank_email', 'legacy_email') THEN RAISE EXCEPTION 'EMAIL_SOURCE_INVALID'; END IF;

  UPDATE eshop.bank_accounts SET last_fetch_time = timezone('UTC', now()), updated_at = now()
  WHERE id = v_bank_account_id;

  IF v_external_id IS NOT NULL THEN
    SELECT id INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND external_id = v_external_id;
    IF FOUND THEN
      RETURN jsonb_build_object('ingest_status', 'skipped', 'reason', 'transport_replay',
        'stored_id', v_existing_id, 'match_verdict', 'already_ingested');
    END IF;
  END IF;

  IF v_movement_id IS NOT NULL THEN
    SELECT id INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND transaction_id = v_movement_id;
  ELSIF v_command_id IS NOT NULL THEN
    SELECT min(id) INTO v_existing_id FROM eshop.transactions
    WHERE bank_account_id = v_bank_account_id AND command_id = v_command_id
    HAVING count(*) = 1;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    UPDATE eshop.transactions SET external_id = COALESCE(external_id, v_external_id)
    WHERE id = v_existing_id;
    RETURN jsonb_build_object('ingest_status', 'reconciled', 'stored_id', v_existing_id,
      'match_verdict', 'already_ingested');
  END IF;

  INSERT INTO eshop.transactions (
    bank_account_id, amount, currency, counter_account, bank_code, bank_name,
    vs, ks, ss, message_for_recipient, date, external_id, transaction_id,
    command_id, counter_account_name, payer_reference, ingest_source
  ) VALUES (
    v_bank_account_id, (p_data->>'amount')::numeric, upper(trim(p_data->>'currency')),
    p_data->>'counter_account', p_data->>'bank_code', p_data->>'bank_name',
    nullif(p_data->>'vs', ''), nullif(p_data->>'ks', ''), nullif(p_data->>'ss', ''),
    p_data->>'message', (p_data->>'date')::timestamptz, v_external_id, v_movement_id,
    v_command_id, p_data->>'sender_name', p_data->>'payer_reference', v_source
  ) RETURNING id INTO v_id;

  BEGIN
    v_match := public.match_bank_transaction(v_id);
  EXCEPTION WHEN OTHERS THEN
    v_match := jsonb_build_object('verdict', 'failed', 'reason', SQLSTATE);
  END;
  RETURN jsonb_build_object('ingest_status', 'inserted', 'stored_id', v_id,
    'match_verdict', v_match->>'verdict', 'reason', v_match->>'reason');
END;
$$;

REVOKE ALL ON FUNCTION public.process_email_transaction(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_email_transaction(jsonb) TO service_role;
