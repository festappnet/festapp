-- Pair verified bank refunds through the shared bank reference and manual pairing paths.

-- SOURCE: eshop_transactions/match_bank_transaction.sql
-- One extraction owner for automatic matching, email suggestions and identity checks.
CREATE OR REPLACE FUNCTION public.bank_transaction_signals_internal(
 p_vs text,p_reference text,p_message text,p_identification text DEFAULT NULL,p_comment text DEFAULT NULL
) RETURNS TABLE(kind text,value text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
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

 ) SELECT DISTINCT kind,CASE WHEN kind='vs' THEN value::bigint::text ELSE value END FROM raw_signals;
$$;
REVOKE ALL ON FUNCTION public.bank_transaction_signals_internal(text,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;

-- Incoming and outgoing bank movements resolve the same account-scoped references.
CREATE OR REPLACE FUNCTION public.bank_transaction_reference_candidates_internal(p_transaction eshop.transactions)
RETURNS TABLE(signal_count bigint,payment_ids bigint[])
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  WITH signals AS (
    SELECT * FROM public.bank_transaction_signals_internal(p_transaction.vs,p_transaction.payer_reference,
      p_transaction.message_for_recipient,p_transaction.user_identification,p_transaction.comment)
  ), candidates AS (
    SELECT DISTINCT pi.id
    FROM signals s
    JOIN eshop.payment_info pi
      ON (s.kind = 'rf' AND pi.creditor_reference = s.value)
      OR (s.kind = 'vs' AND pi.variable_symbol = CASE WHEN s.kind='vs' THEN s.value::bigint END)
    WHERE (pi.bank_account = p_transaction.bank_account_id
      OR public.bank_sync_accounts_match(p_transaction.id,pi.bank_account))
      AND upper(trim(pi.currency_code::text)) = upper(trim(p_transaction.currency::text))
  )
  SELECT (SELECT count(*) FROM signals), array_agg(c.id ORDER BY c.id)
  FROM candidates c;
$$;
REVOKE ALL ON FUNCTION public.bank_transaction_reference_candidates_internal(eshop.transactions) FROM PUBLIC,anon,authenticated,service_role;

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
  IF public.is_demo_bank_account((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id)) THEN
    RETURN jsonb_build_object('outcome','skipped_demo');
  END IF;
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

  SELECT c.signal_count,c.payment_ids INTO v_signal_count,v_candidate_ids
  FROM public.bank_transaction_reference_candidates_internal(v_transaction) c;

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

-- SOURCE: eshop_transactions/apply_transaction_pairing.sql
CREATE OR REPLACE FUNCTION public.apply_transaction_pairing(
  p_transaction_id bigint,
  p_payment_info_id bigint,
  p_method text,
  p_actor_kind text DEFAULT 'system',
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_transaction eshop.transactions%ROWTYPE;
  v_target eshop.payment_info%ROWTYPE;
  v_old_payment_info_id bigint;
  v_order_id bigint;
  v_order eshop.orders;
  v_order_ids bigint[];
  v_order_bindings jsonb;
  v_locked_order_bindings jsonb;
  v_api_review eshop.bank_sync_inbox;
  v_bank_refund boolean;
  v_payment_reason text;
BEGIN
  PERFORM public.check_bank_account_writable((SELECT bank_account_id FROM eshop.transactions WHERE id=p_transaction_id));
  PERFORM public.check_bank_account_writable((SELECT bank_account FROM eshop.payment_info WHERE id=p_payment_info_id));
  IF p_method IS NULL OR p_method !~ '^[a-z0-9_]{1,64}$' THEN
    RAISE EXCEPTION 'PAIRING_INVALID_METHOD';
  END IF;
  IF p_actor_kind NOT IN ('service', 'user', 'system') THEN
    RAISE EXCEPTION 'PAIRING_INVALID_ACTOR_KIND';
  END IF;

  SELECT * INTO v_transaction
  FROM eshop.transactions
  WHERE id = p_transaction_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_TRANSACTION_NOT_FOUND'; END IF;
  v_old_payment_info_id := v_transaction.payment_info;
  v_bank_refund := v_transaction.amount<0 AND v_transaction.ingest_source IN ('banksync_api','fio_api')
    AND v_transaction.transaction_type IS DISTINCT FROM 'manual';
  v_payment_reason := CASE WHEN v_bank_refund THEN 'refund_fact' ELSE 'payment_fact' END;

  IF p_payment_info_id IS NOT NULL AND v_transaction.ingest_source='banksync_api' THEN
    v_api_review:=public.bank_sync_api_review_row_internal(p_transaction_id);
    IF v_api_review.delivery_id IS NOT NULL AND
      v_api_review.resolution->>'action' IS DISTINCT FROM 'api_distinct' THEN
      RAISE EXCEPTION 'BANK_SYNC_API_DUPLICATE_REVIEW_REQUIRED';
    END IF;
  END IF;

  -- The transaction row stabilizes the old target (also held by ingest/matcher).
  -- Acquire every stored old/new form and order before either payment row,
  -- matching product edit and cancellation. Never trust a caller's scope list.
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]),
    coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_order_ids,v_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  PERFORM public.lock_order_capacity_scope_internal(v_order_ids);
  SELECT coalesce(jsonb_agg(jsonb_build_array(id,form,payment_info) ORDER BY id),'[]'::jsonb)
  INTO v_locked_order_bindings
  FROM eshop.orders WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id);
  IF v_order_bindings IS DISTINCT FROM v_locked_order_bindings THEN
    RAISE EXCEPTION 'PAIRING_ORDER_SCOPE_CHANGED' USING ERRCODE='40001';
  END IF;
  PERFORM 1 FROM eshop.payment_info WHERE id IN (v_old_payment_info_id,p_payment_info_id)
  ORDER BY id FOR UPDATE;

  -- A settled movement is immutable through the generic attach/unlink API.
  -- Cash voids and evidenced bank reclassification have their explicit owner.
  IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=p_transaction_id)
     AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    RAISE EXCEPTION 'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION';
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0
     AND NOT (v_bank_refund AND p_method IN ('automatic_reference','manual_attach'))
     AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b WHERE b.id=v_transaction.bank_account_id
       AND upper(b.type)='CASH' AND v_transaction.transaction_type='manual'
       AND v_transaction.ingest_source='manual') THEN
    RAISE EXCEPTION 'OUTGOING_REQUIRES_REFUND_CLASSIFICATION';
  END IF;
  IF v_old_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND NOT v_bank_refund THEN
    PERFORM public.assert_payment_refund_reservations_internal(v_old_payment_info_id,greatest(v_transaction.amount,0));
  END IF;
  IF p_payment_info_id IS NOT NULL AND v_old_payment_info_id IS DISTINCT FROM p_payment_info_id AND v_transaction.amount<0 AND NOT v_bank_refund THEN
    PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-v_transaction.amount);
  END IF;

  IF p_actor_kind='user' THEN
    -- The manual bank commands mutate the current and requested bindings.
    -- Authorize the stored orders and their payment accounts under their locks.
    IF v_old_payment_info_id IS NOT NULL AND p_method IN ('manual_attach','manual_unlink') THEN
      PERFORM public.check_is_admin_for_bank_account(pi.bank_account)
      FROM eshop.payment_info pi WHERE pi.id IN (v_old_payment_info_id,p_payment_info_id);
      PERFORM public.check_is_editor_order_on_occasion(o.occasion)
      FROM eshop.orders o WHERE o.payment_info IN (v_old_payment_info_id,p_payment_info_id);
    END IF;
    FOR v_order IN SELECT * FROM eshop.orders
      WHERE payment_info IN (v_old_payment_info_id,p_payment_info_id) ORDER BY id LOOP
      IF v_bank_refund AND v_order.state='storno' THEN
        PERFORM public.check_occasion_writable(v_order.occasion);
      ELSE
        PERFORM public.check_order_is_mutable(v_order.id);
      END IF;
    END LOOP;
  END IF;

  IF v_old_payment_info_id IS NOT DISTINCT FROM p_payment_info_id THEN
    RETURN jsonb_build_object('status', 'unchanged', 'transaction_id', p_transaction_id,
      'payment_info_id', p_payment_info_id);
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    SELECT * INTO v_target FROM eshop.payment_info WHERE id = p_payment_info_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PAIRING_PAYMENT_INFO_NOT_FOUND'; END IF;
    IF v_bank_refund AND v_target.payment_method IS DISTINCT FROM 'bank' THEN
      RAISE EXCEPTION 'OUTGOING_REQUIRES_BANK_PAYMENT';
    END IF;
    IF public.payment_method_is_online_internal(v_target.payment_method) THEN RAISE EXCEPTION 'STRIPE_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_target.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM eshop.bank_accounts b
      WHERE b.id=v_transaction.bank_account_id AND b.type='CASH' AND v_transaction.transaction_type='manual') THEN
      RAISE EXCEPTION 'CASH_BANK_PAIRING_UNSUPPORTED'; END IF;
    IF v_transaction.transaction_type='manual' THEN
      IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
        JOIN eshop.orders o ON o.occasion=oc.id JOIN eshop.bank_accounts b ON b.id=link.bank_account
        WHERE o.payment_info=v_target.id AND b.id=v_transaction.bank_account_id ) THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
    END IF;
    IF upper(trim(v_transaction.currency::text)) <> upper(trim(v_target.currency_code::text)) THEN
      RAISE EXCEPTION 'PAIRING_CURRENCY_MISMATCH';
    END IF;
    IF v_transaction.transaction_type IS DISTINCT FROM 'manual'
       AND v_transaction.bank_account_id <> v_target.bank_account
       AND NOT public.bank_sync_accounts_match(p_transaction_id,v_target.bank_account) THEN
      RAISE EXCEPTION 'PAIRING_BANK_ACCOUNT_MISMATCH';
    END IF;
  END IF;

  UPDATE eshop.transactions SET payment_info = p_payment_info_id WHERE id = p_transaction_id;

  IF v_old_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(v_old_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = v_old_payment_info_id;
    IF v_order_id IS NOT NULL THEN
      PERFORM public.reconcile_order_payment_internal_v1(v_order_id,v_payment_reason);
      IF v_bank_refund THEN PERFORM public.record_payment_fact_sync_internal(v_order_id); END IF;
    END IF;
  END IF;

  IF p_payment_info_id IS NOT NULL THEN
    PERFORM public.refresh_payment_info_totals_internal(p_payment_info_id);
    SELECT o.id INTO v_order_id FROM eshop.orders o WHERE o.payment_info = p_payment_info_id;
    IF v_order_id IS NOT NULL THEN
      PERFORM public.reconcile_order_payment_internal_v1(v_order_id,v_payment_reason);
      IF v_bank_refund THEN PERFORM public.record_payment_fact_sync_internal(v_order_id); END IF;
      IF v_transaction.amount>0 AND v_transaction.transaction_type IS DISTINCT FROM 'manual'
        AND v_transaction.ingest_source IS DISTINCT FROM 'manual' THEN
        PERFORM public.publish_form_measurement_event_internal('order_fully_paid',v_order_id);
      END IF;
    END IF;
  END IF;


  IF v_old_payment_info_id IS DISTINCT FROM p_payment_info_id THEN
    PERFORM public.notification_center_prepared_invalidate(e.id) FROM public.notification_center_events e
     JOIN eshop.orders o ON o.occasion=e.occasion AND o.id=(e.data->>'orderId')::bigint
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id AND o.payment_info=v_old_payment_info_id;
    UPDATE public.notification_center_events e SET status='resolved' FROM eshop.orders o
     WHERE e.kind='order_payment_received' AND e.data->>'paymentFact'='transaction:'||p_transaction_id
      AND o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion AND o.payment_info=v_old_payment_info_id;
    IF p_payment_info_id IS NOT NULL AND v_transaction.amount>0 THEN
      FOR v_order_id IN SELECT id FROM eshop.orders WHERE payment_info=p_payment_info_id LOOP
       PERFORM public.notification_center_payment_fact_internal(v_order_id,'transaction',p_transaction_id::text,
        v_transaction.amount,v_transaction.currency::text,coalesce(v_transaction.date,now()),
        EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=p_transaction_id AND new_payment_info_id IS NOT NULL));
      END LOOP;
    END IF;
  END IF;
  INSERT INTO eshop.transaction_pairing_events (
    transaction_snapshot_id, transaction_id, old_payment_info_id,
    new_payment_info_id, action, method, actor_id, actor_kind, details
  ) VALUES (
    p_transaction_id, p_transaction_id, v_old_payment_info_id,
    p_payment_info_id, CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    p_method, auth.uid(), p_actor_kind, COALESCE(p_details, '{}'::jsonb)
  );

  RETURN jsonb_build_object('status', CASE WHEN p_payment_info_id IS NULL THEN 'unpaired' ELSE 'paired' END,
    'transaction_id', p_transaction_id, 'payment_info_id', p_payment_info_id);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_transaction_pairing(bigint,bigint,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: eshop_bank_sync/bank_sync_api_review.sql
CREATE OR REPLACE FUNCTION public.bank_sync_pairing_candidates_internal(p_account bigint,p_recovery_only boolean)
RETURNS TABLE(movement eshop.transactions,review eshop.bank_sync_inbox)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT t,r FROM eshop.transactions t
 LEFT JOIN LATERAL public.bank_sync_api_review_row_internal(
   CASE WHEN t.ingest_source='banksync_api' THEN t.id END) r ON true
 WHERE t.bank_account_id IN (
  SELECT p_account
  UNION SELECT c.bank_account_id FROM eshop.bank_sync_connections c
  JOIN eshop.bank_sync_account_aliases a ON a.connection_id=c.id
  WHERE a.bank_account_id=p_account AND public.can_manage_bank_account(c.bank_account_id)
 )
 AND (t.bank_account_id=p_account OR public.bank_sync_accounts_match(t.id,p_account))
 AND (NOT p_recovery_only OR t.ingest_source='banksync_email_confirmed' OR r.delivery_id IS NOT NULL)
 AND t.payment_info IS NULL
 AND (t.amount>0 OR (t.amount<0 AND t.ingest_source IN ('banksync_api','fio_api')
      AND t.transaction_type IS DISTINCT FROM 'manual'))
 AND NOT EXISTS(SELECT FROM eshop.refund_settlements s WHERE s.transaction_id=t.id);
$$;

-- SOURCE: eshop_transactions/get_transactions_for_order.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id bigint; bank_allowed boolean; bank_configured boolean; payment_context jsonb; provider_rows jsonb:='[]'; provider_complete boolean:=true; method text; movement jsonb;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT can_read_orders(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  SELECT pi.payment_method='bank' AND public.payment_method_policy_enabled_internal(oc.unit,'bank'),
   EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
    WHERE l.unit=oc.unit AND upper(b.type)<>'CASH')
  INTO bank_allowed,bank_configured
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  payment_context:=public.payment_method_context_internal(order_id);
  SELECT pi.payment_method INTO method FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=order_id;
  IF public.payment_method_is_online_internal(method) THEN
   BEGIN
    SELECT public.payment_provider_call_internal(method,'movements',jsonb_build_object('paymentId',o.payment_info)) INTO movement FROM eshop.orders o WHERE o.id=order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('source','provider','sourceId',m->>'sourceId','provider',method,
     'date',m->'occurred_at','amount',CASE WHEN m->>'kind'='dispute' THEN NULL ELSE CASE WHEN m->>'kind'='refund' THEN -1 ELSE 1 END*(m->>'amount_minor')::numeric/100 END,
     'heldAmount',CASE WHEN m->>'kind'='dispute' THEN (m->>'amount_minor')::numeric/100 END,'status',m->>'status',
     'currency',m->>'currency','transaction_type',m->>'kind','isRefund',m->>'kind'='refund','voided',false)), '[]')
    INTO provider_rows FROM jsonb_array_elements(movement) m;
    provider_complete:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(movement) m WHERE nullif(m->>'sourceId','') IS NULL);
   EXCEPTION WHEN OTHERS THEN provider_complete:=false; END;
  ELSIF method NOT IN ('bank','cash') OR method IS NULL THEN provider_complete:=false;
  END IF;
  RETURN (
    SELECT jsonb_build_object(
      'order_state', o.state,'ledgerComplete',provider_complete,
      'paymentOperations',payment_context,
      'actions', jsonb_build_object(
        'canAddCash', EXISTS(SELECT 1 FROM jsonb_array_elements(payment_context->'methods') m WHERE m->>'id'='cash' AND m->'record'='true'::jsonb),
        'canConfigureBank', bank_allowed AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankSetup',bank_allowed AND NOT bank_configured AND public.can_manage_unit_bank_accounts(oc.unit),
        'showBankAccess',bank_allowed AND NOT public.can_manage_unit_bank_accounts(oc.unit),
        'bankState', CASE WHEN NOT bank_allowed THEN 'disabled' WHEN NOT public.can_read_unit_bank_accounts(oc.unit) THEN 'restricted'
          WHEN bank_configured THEN 'configured' ELSE 'absent' END,
        'pairingAccountId', CASE WHEN pi.payment_method='bank'
          AND public.can_manage_bank_account(pi.bank_account) AND public.can_write_orders(o.occasion)
          AND (
            (bank_allowed AND o.state IN ('created','ordered','paid','sent','storno'))
            OR (o.state IN ('created','ordered','paid','sent','expired')
             AND public.bank_sync_recovery_account_internal(pi.bank_account,oc.unit)
             AND EXISTS(SELECT FROM public.bank_sync_pairing_candidates_internal(pi.bank_account,true) c
              WHERE upper(trim((c.movement).currency))=upper(trim(pi.currency_code)))
            )
          ) THEN pi.bank_account END,
        'unitId', oc.unit,
        'removableTransactionIds', (SELECT coalesce(jsonb_agg(t.id),'[]')
          FROM eshop.transactions t JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
          WHERE t.payment_info=o.payment_info AND (o.state IN ('created','ordered','paid','sent')
            OR (o.state='storno' AND t.amount<0 AND t.ingest_source IN ('banksync_api','fio_api')
              AND t.transaction_type IS DISTINCT FROM 'manual')
            OR (o.state='expired' AND public.bank_sync_recovery_receipt_internal(t)))
          AND NOT public.payment_method_is_online_internal(pi.payment_method)
          AND NOT EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.transaction_id=t.id)
          AND NOT EXISTS(SELECT 1 FROM eshop.transaction_pairing_events e WHERE e.transaction_snapshot_id=t.id AND e.method='exact_cash_correction')
          AND CASE WHEN t.transaction_type='manual' THEN upper(b.type)='CASH'
            AND public.can_manage_unit_bank_accounts(oc.unit) AND EXISTS(
              SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=oc.unit AND l.bank_account=b.id)
            ELSE (bank_allowed OR public.bank_sync_recovery_receipt_internal(t))
            AND public.can_write_orders(o.occasion) AND public.can_manage_bank_account(b.id)
            AND public.can_manage_bank_account(pi.bank_account) END)
      ),
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('source',CASE WHEN t.ingest_source='manual' THEN 'cash' ELSE 'bank' END,'sourceId','transaction:'||t.id,'isRefund',m.is_refund,'voided',m.voided,'createdByName',
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        JOIN LATERAL public.payment_transaction_movements_internal(o.payment_info) m ON m.transaction_id=t.id
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)||provider_rows
    )
    FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id
  );
END;
$$;

-- SOURCE: eshop_transactions/get_transactions_for_order_all_available.sql
CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    bank_acc bigint;
    v_bank_sales boolean;
    v_unit bigint;
    v_recovery_only boolean;
    v_state text;
    v_currency text;
BEGIN
    SELECT pi.bank_account,public.payment_method_policy_enabled_internal(oc.unit,'bank'),oc.unit,o.state,pi.currency_code
    INTO bank_acc,v_bank_sales,v_unit,v_state,v_currency
    FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
    JOIN public.occasions oc ON oc.id=o.occasion
    WHERE pi.id=payment_info_id AND pi.payment_method='bank' AND public.can_read_orders(oc.id);
    IF bank_acc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='Bank payment account required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=bank_acc AND public.can_read_orders(demo_bank.occasion)) THEN
        PERFORM public.check_is_admin_for_bank_account(bank_acc);
    END IF;
    v_recovery_only:=v_state='expired' OR NOT v_bank_sales;
    IF v_recovery_only AND NOT public.bank_sync_recovery_account_internal(bank_acc,v_unit)
    THEN RAISE insufficient_privilege; END IF;

    RETURN (
        SELECT jsonb_agg(to_jsonb(c.movement)||
          CASE WHEN (c.review).delivery_id IS NOT NULL
          THEN jsonb_build_object('bankSyncReview',public.bank_sync_api_review_view_internal(c.review))
          ELSE '{}'::jsonb END ORDER BY (c.movement).date DESC,(c.movement).id)
        FROM public.bank_sync_pairing_candidates_internal(bank_acc,v_recovery_only) c
        WHERE (v_state IS DISTINCT FROM 'storno' OR (c.movement).amount<0)
          AND ((c.movement).amount>0 OR upper(trim((c.movement).currency))=upper(trim(v_currency)))
    );
END;
$$;

-- SOURCE: eshop_bank_sync/ingest_bank_sync_transaction.sql
CREATE OR REPLACE FUNCTION public.ingest_bank_sync_transaction(
  p_instance_id text, p_consumer_app_id text, p_body_sha256 text, p_envelope jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE
  v_data jsonb := p_envelope->'data';
  v_delivery text := p_envelope->>'delivery_id';
  v_connection eshop.bank_sync_connections%ROWTYPE;
  v_inbox eshop.bank_sync_inbox%ROWTYPE;
  v_tx eshop.transactions%ROWTYPE;
  v_ids bigint[];
  v_identity text := v_data->>'transaction_id';
  v_amount numeric;
  v_date timestamptz;
  v_outcome text;
  v_match jsonb;
  v_receipt jsonb;
  v_source_id bigint;
  v_command_id bigint;
  v_refund jsonb;
  v_possible_duplicate_ids bigint[];
  v_skip_matching boolean:=false;
BEGIN
  PERFORM public.require_service_role();
  IF p_consumer_app_id IS DISTINCT FROM 'festapp' OR nullif(p_instance_id,'') IS NULL
    OR p_body_sha256 IS NULL OR p_body_sha256 !~ '^[0-9a-f]{64}$'
    OR p_envelope->>'event' IS DISTINCT FROM 'transaction.received'
    OR p_envelope->>'event_version' IS DISTINCT FROM '2'
    OR v_delivery IS NULL OR v_delivery !~ '^[0-9A-HJKMNP-TV-Z]{26}$'
    OR v_data->>'currency' IS NULL OR v_data->>'currency' NOT IN ('CZK','EUR','USD')
    OR jsonb_typeof(v_data->'amount_cents') IS DISTINCT FROM 'number'
    OR v_data->>'amount_cents' !~ '^-?[0-9]+$'
    OR abs((v_data->>'amount_cents')::numeric)>9007199254740991
    OR v_data->>'id' IS NULL OR v_data->>'bank_account_id' IS NULL
    OR v_data->>'date' IS NULL OR v_data->>'date' !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_ENVELOPE';
  END IF;
  v_amount := (v_data->>'amount_cents')::numeric/100;
  v_date := (v_data->>'date')::timestamptz;
  IF v_data->>'direction' IS DISTINCT FROM (CASE WHEN v_amount>0 THEN 'incoming' WHEN v_amount<0 THEN 'outgoing' ELSE 'zero' END) THEN
    RAISE EXCEPTION 'BANK_SYNC_INVALID_DIRECTION';
  END IF;

  -- Lock order: delivery advisory -> connection -> identity/ledger -> payment_info.
  -- Legacy writers hold the same account row barrier before any ledger writes.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_instance_id||':'||p_consumer_app_id||':'||v_delivery,0));
  SELECT * INTO v_inbox FROM eshop.bank_sync_inbox
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  IF FOUND THEN
    IF v_inbox.body_sha256<>p_body_sha256 THEN RAISE EXCEPTION 'BANK_SYNC_DELIVERY_CONFLICT'; END IF;
    RETURN v_inbox.receipt;
  END IF;
  SELECT * INTO v_connection FROM eshop.bank_sync_connections
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id
      AND remote_bank_account_id=v_data->>'bank_account_id' FOR UPDATE;
  INSERT INTO eshop.bank_sync_inbox(instance_id,consumer_app_id,delivery_id,body_sha256,event_version,
    remote_transaction_id,connection_id,epoch,payload)
    VALUES(p_instance_id,p_consumer_app_id,v_delivery,p_body_sha256,'2',v_data->>'id',v_connection.id,v_connection.epoch,p_envelope);

  IF v_connection.id IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_connection.state='shadow' THEN v_outcome:='shadow_recorded';
  ELSIF v_connection.state NOT IN ('connected','degraded') OR v_connection.legacy_blocked_at IS NULL THEN v_outcome:='quarantined_scope';
  ELSIF v_data->>'identity_kind' IS DISTINCT FROM 'movement'
    OR v_data->>'identity_provenance' IS DISTINCT FROM 'fio_api_column22'
    OR v_data->>'source' IS DISTINCT FROM 'fio_api'
    OR v_connection.provider<>'FIO' OR nullif(v_identity,'') IS NULL THEN
    v_outcome:='quarantined_identity';
    IF (v_data->>'source' ~ '(^|_)email$') AND v_amount>0 THEN
      v_possible_duplicate_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,false);
    END IF;
  ELSE
    SELECT t.* INTO v_tx FROM eshop.bank_transaction_identities i
      JOIN eshop.transactions t ON t.id=i.transaction_id
      WHERE i.instance_id=p_instance_id AND i.provider=v_connection.provider
        AND i.physical_account=v_connection.physical_account AND i.identity_kind='movement' AND i.identity_value=v_identity
      FOR UPDATE OF t;
    IF v_tx.id IS NULL AND v_identity ~ '^[0-9]{1,19}$' AND v_identity::numeric<=9223372036854775807 THEN
      v_source_id:=v_identity::bigint;
      SELECT array_agg(id ORDER BY id) INTO v_ids FROM eshop.transactions
        WHERE transaction_id=v_source_id AND ingest_source='fio_api'
          AND (bank_account_id=v_connection.bank_account_id OR bank_account_id IN
            (SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=v_connection.id));
      IF cardinality(v_ids)>1 THEN v_outcome:='quarantined_conflict';
      ELSIF cardinality(v_ids)=1 THEN SELECT * INTO v_tx FROM eshop.transactions WHERE id=v_ids[1] FOR UPDATE;
      END IF;
    END IF;
    -- Keep each proven API movement and its own identity. If a manually
    -- confirmed email might describe it, leave the new credit for review.
    IF v_outcome IS NULL AND v_tx.id IS NULL AND v_amount>0 THEN
      v_possible_duplicate_ids:=public.bank_sync_email_duplicate_candidates_internal(v_connection.id,v_data,true);
      v_skip_matching:=cardinality(v_possible_duplicate_ids)>0;
    END IF;
    IF v_outcome IS NULL AND v_tx.id IS NOT NULL THEN
      IF NOT public.bank_sync_existing_facts_match(v_tx,v_data) THEN
        v_outcome:='quarantined_conflict';
      ELSE v_outcome:='already_ingested';
      END IF;
    END IF;
    IF v_outcome IS NULL THEN
      IF v_data->>'command_id' ~ '^[0-9]{1,19}$' AND (v_data->>'command_id')::numeric<=9223372036854775807 THEN
        v_command_id:=(v_data->>'command_id')::bigint;
      END IF;
      INSERT INTO eshop.transactions(transaction_id,bank_account_id,amount,currency,date,vs,ks,ss,
        command_id,payer_reference,message_for_recipient,counter_account,counter_account_name,bank_code,bank_name,
        user_identification,transaction_type,performed_by,comment,ingest_source)
        VALUES(v_source_id,v_connection.bank_account_id,v_amount,v_data->>'currency',v_date AT TIME ZONE 'UTC',
          nullif(v_data->>'raw_vs',''),nullif(v_data->>'ks',''),nullif(v_data->>'ss',''),v_command_id,
          v_data->>'payer_reference',v_data->>'message',v_data->>'counter_account',v_data->>'sender_name',
          v_data->>'bank_code',v_data->>'bank_name',v_data->>'user_identification',v_data->>'transaction_type',
          v_data->>'performed_by',v_data->>'comment','banksync_api') RETURNING * INTO v_tx;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id);
      IF v_amount<0 THEN v_outcome:='stored_outgoing';
      ELSIF v_amount=0 THEN v_outcome:='stored_zero';
      ELSIF v_skip_matching THEN v_outcome:='unmatched';
      ELSE
        v_match:=public.payment_provider_call_internal('bank','observe_payment',jsonb_build_object('transactionId',v_tx.id));
        v_outcome:=v_match->>'verdict';
        IF v_outcome NOT IN ('paired','unmatched','ambiguous','ineligible','already_paired') OR v_outcome IS NULL THEN
          RAISE EXCEPTION 'BANK_SYNC_MATCHER_INVALID_RESULT';
        END IF;
        IF v_outcome='already_paired' THEN v_outcome:='already_ingested'; END IF;
      END IF;
    END IF;
    IF v_outcome<>'quarantined_conflict' THEN
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'movement',v_identity,v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
      INSERT INTO eshop.bank_transaction_identities(instance_id,provider,physical_account,identity_kind,identity_value,transaction_id)
        VALUES(p_instance_id,v_connection.provider,v_connection.physical_account,'remote_transaction',v_data->>'id',v_tx.id)
        ON CONFLICT (instance_id,provider,physical_account,identity_kind,identity_value) DO UPDATE
          SET transaction_id=eshop.bank_transaction_identities.transaction_id
          WHERE eshop.bank_transaction_identities.transaction_id=EXCLUDED.transaction_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'BANK_SYNC_IDENTITY_CONFLICT'; END IF;
    END IF;
  END IF;
  IF v_tx.id IS NOT NULL AND v_tx.amount<0 AND NOT v_skip_matching AND v_outcome IN ('stored_outgoing','already_ingested') THEN
    v_refund:=public.payment_provider_call_internal('bank','observe_refund',jsonb_build_object('transactionId',v_tx.id));
  END IF;
  v_receipt:=jsonb_build_object('ok',true,'receipt_version',1,'delivery_id',v_delivery,'outcome',v_outcome,'refund',v_refund);
  UPDATE eshop.bank_sync_inbox SET outcome=v_outcome,receipt=v_receipt,committed_at=now(),
    diagnostics=jsonb_build_object('transaction_id',v_tx.id,
      'possible_duplicate_transaction_ids',coalesce(to_jsonb(v_possible_duplicate_ids),'[]'),
      'reason',CASE WHEN v_skip_matching THEN 'stored_unpaired_possible_duplicate' END)
    WHERE instance_id=p_instance_id AND consumer_app_id=p_consumer_app_id AND delivery_id=v_delivery;
  UPDATE eshop.bank_sync_connections SET receiver_commit_at=now(),
    last_error=CASE WHEN v_outcome LIKE 'quarantined_%' THEN v_outcome ELSE last_error END WHERE id=v_connection.id;
  RETURN v_receipt;
END;
$$;
REVOKE ALL ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_bank_sync_transaction(text,text,text,jsonb) TO service_role;

-- SOURCE: payment_providers/bank_settlement.sql
-- Called after verified BankSync fact persistence, never from an untrusted client.
CREATE OR REPLACE FUNCTION public.observe_bank_refund_internal(p_transaction bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE t eshop.transactions; pi eshop.payment_info; o eshop.orders; req eshop.refund_requests;
 candidates bigint[]; owner_id bigint; order_id bigint; candidate_count bigint; recipient text;
BEGIN
 SELECT * INTO STRICT t FROM eshop.transactions WHERE id=p_transaction FOR UPDATE;
 IF t.amount>=0 OR t.ingest_source NOT IN ('banksync_api','fio_api')
    OR public.is_demo_bank_account(t.bank_account_id) THEN RETURN jsonb_build_object('matched',false); END IF;
 IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=t.id) THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
 IF t.payment_info IS NULL AND EXISTS(
  SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_snapshot_id=t.id AND method='manual_unlink'
 ) THEN RETURN jsonb_build_object('matched',false,'reason','manually_unlinked'); END IF;
 SELECT c.payment_ids INTO candidates FROM public.bank_transaction_reference_candidates_internal(t) c;
 IF coalesce(cardinality(candidates),0)<>1 THEN
  RETURN jsonb_build_object('matched',false,'reason','no_unique_reference');
 END IF;
 owner_id:=candidates[1];
 SELECT min(id),count(*) INTO order_id,candidate_count FROM eshop.orders WHERE payment_info=owner_id;
 IF candidate_count<>1 THEN RETURN jsonb_build_object('matched',false,'reason','no_unique_order'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
 SELECT * INTO o FROM eshop.orders WHERE id=order_id AND payment_info=owner_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('matched',false); END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=owner_id FOR UPDATE;
 IF pi.payment_method IS DISTINCT FROM 'bank' OR (t.payment_info IS NOT NULL AND t.payment_info<>pi.id)
    OR NOT EXISTS(SELECT 1 FROM public.bank_transaction_reference_candidates_internal(t) c WHERE c.payment_ids=candidates) THEN
  RETURN jsonb_build_object('matched',false,'reason','scope_or_reference_changed');
 END IF;
 IF t.ingest_source='banksync_api' AND EXISTS(
  SELECT 1 FROM public.bank_sync_api_review_row_internal(t.id) r WHERE r.delivery_id IS NOT NULL
   AND r.resolution->>'action' IS DISTINCT FROM 'api_distinct'
 ) THEN RETURN jsonb_build_object('matched',false,'reason','duplicate_review_required'); END IF;
 recipient:=public.try_payment_reference_account_internal(CASE WHEN t.counter_account LIKE '%/%' OR t.counter_account ~ '^[A-Za-z]{2}' THEN t.counter_account
  ELSE t.counter_account||'/'||t.bank_code END);
 -- Record a matching instruction if there is one. The movement identifies its order independently.
 SELECT * INTO req FROM eshop.refund_requests WHERE payment_info=pi.id AND method='bank'
  AND payload#>>'{instructions,recipientIban}'=recipient
  AND (t.date::date>=created_at::date OR payload->'existingDebits' @> jsonb_build_array(t.id)) ORDER BY (status IN ('pending','processing','unknown')) DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF req.id IS NULL THEN
  IF t.date::date<(o.created_at AT TIME ZONE 'UTC')::date THEN
   RETURN jsonb_build_object('matched',false,'reason','movement_predates_order');
  END IF;
  IF t.payment_info=pi.id THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
  PERFORM public.apply_transaction_pairing(t.id,pi.id,'automatic_reference','service');
  RETURN jsonb_build_object('matched',true,'orderId',o.id,'requestId',NULL);
 END IF;
 UPDATE eshop.transactions SET payment_info=pi.id WHERE id=t.id;
 INSERT INTO eshop.refund_settlements(transaction_id,request_id) VALUES(t.id,req.id);
 UPDATE eshop.refund_requests SET status='succeeded',updated_at=now(),result=jsonb_build_object('transactionId',t.id,
  'actualAmount',(-t.amount)::text,'deviation',req.amount<>-t.amount OR req.status IN ('cancelled','succeeded')) WHERE id=req.id;
 INSERT INTO eshop.payment_operation_events(request_id,operation,details) VALUES(req.id,'bank_event',jsonb_build_object('transactionId',t.id,'amount',t.amount));
 INSERT INTO eshop.transaction_pairing_events(transaction_snapshot_id,transaction_id,new_payment_info_id,action,method,actor_kind,actor_id,details)
 VALUES(t.id,t.id,pi.id,'paired','refund_settlement',CASE WHEN auth.role()='service_role' THEN 'service' ELSE 'user' END,auth.uid(),jsonb_build_object('requestId',req.id));
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 PERFORM public.reconcile_order_payment_internal_v1(o.id,'refund_fact');
 PERFORM public.record_payment_fact_sync_internal(o.id);
 RETURN jsonb_build_object('matched',true,'orderId',o.id,'requestId',req.id);
END $$;
REVOKE ALL ON FUNCTION public.observe_bank_refund_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
