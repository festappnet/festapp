CREATE OR REPLACE FUNCTION public.match_bank_transaction(p_transaction_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_candidate_ids bigint[];
  v_candidate_id bigint;
  v_signal_count integer := 0;
BEGIN
  PERFORM public.require_service_role();

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MATCH_TRANSACTION_NOT_FOUND'; END IF;

  IF v_transaction.payment_info IS NOT NULL THEN
    RETURN jsonb_build_object('verdict', 'already_paired',
      'transaction_id', p_transaction_id, 'payment_info_id', v_transaction.payment_info);
  END IF;
  IF v_transaction.amount <= 0
     OR v_transaction.bank_account_id IS NULL
     OR nullif(trim(v_transaction.currency::text), '') IS NULL THEN
    RETURN jsonb_build_object('verdict', 'ineligible', 'reason', 'invalid_direction_or_scope');
  END IF;
  IF v_transaction.ingest_source LIKE '%_email'
     AND v_transaction.transaction_id IS NULL
     AND v_transaction.command_id IS NULL THEN
    RETURN jsonb_build_object('verdict', 'ineligible', 'reason', 'unverified_identity');
  END IF;

  WITH raw_signals(kind, value) AS (
    SELECT 'vs', trim(v_transaction.vs::text)
      WHERE trim(COALESCE(v_transaction.vs::text, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(v_transaction.payer_reference)
      WHERE v_transaction.payer_reference IS NOT NULL
        AND public.is_valid_creditor_reference(v_transaction.payer_reference)
    UNION ALL
    SELECT 'rf', public.normalize_creditor_reference(m.captures[2])
      FROM regexp_matches(
        upper(concat_ws(E'\n', v_transaction.message_for_recipient,
          v_transaction.user_identification, v_transaction.comment)),
        '(^|[^A-Z0-9])(RF[0-9]{2}[A-Z0-9[:space:]]{1,25})([^A-Z0-9]|$)', 'g'
      ) AS m(captures)
      WHERE public.is_valid_creditor_reference(m.captures[2])
    UNION ALL
    SELECT 'vs', trim(v_transaction.message_for_recipient)
      WHERE nullif(trim(COALESCE(v_transaction.vs::text, '')), '') IS NULL
        AND trim(COALESCE(v_transaction.message_for_recipient, '')) ~ '^[0-9]{1,10}$'
    UNION ALL
    SELECT 'vs', substring(v_transaction.message_for_recipient
      FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})')
      WHERE nullif(trim(COALESCE(v_transaction.vs::text, '')), '') IS NULL
        AND substring(v_transaction.message_for_recipient
          FROM '(?i)(?:VS|variabilní symbol)[[:space:]]*[:=-]?[[:space:]]*([0-9]{1,10})') IS NOT NULL
  ), signals AS (
    SELECT DISTINCT kind, value FROM raw_signals
  ), candidates AS (
    SELECT DISTINCT pi.id
    FROM signals s
    JOIN eshop.payment_info pi
      ON (s.kind = 'rf' AND pi.creditor_reference = s.value)
      OR (s.kind = 'vs' AND pi.variable_symbol = s.value::bigint)
    WHERE (pi.bank_account = v_transaction.bank_account_id
      OR public.bank_sync_accounts_match(p_transaction_id,pi.bank_account))
      AND upper(trim(pi.currency_code::text)) = upper(trim(v_transaction.currency::text))
  )
  SELECT (SELECT count(*) FROM signals), array_agg(c.id ORDER BY c.id)
  INTO v_signal_count, v_candidate_ids
  FROM candidates c;

  IF v_signal_count = 0 OR v_candidate_ids IS NULL THEN
    RETURN jsonb_build_object('verdict', 'unmatched', 'reason', 'no_unique_reference');
  END IF;
  IF cardinality(v_candidate_ids) <> 1 THEN
    RETURN jsonb_build_object('verdict', 'ambiguous', 'candidate_count', cardinality(v_candidate_ids));
  END IF;

  v_candidate_id := v_candidate_ids[1];
  PERFORM public.apply_transaction_pairing(
    p_transaction_id, v_candidate_id, 'automatic_reference', 'service',
    jsonb_build_object('signal_count', v_signal_count)
  );
  RETURN jsonb_build_object('verdict', 'paired', 'transaction_id', p_transaction_id,
    'payment_info_id', v_candidate_id);
END;
$$;

REVOKE ALL ON FUNCTION public.match_bank_transaction(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_bank_transaction(bigint) TO service_role;
