-- One owner for exact cash movements, account serialization and existing pairing.
CREATE OR REPLACE FUNCTION public.write_cash_movement_internal(
 p_amount numeric,p_currency text,p_unit_id bigint,p_variable_symbol text,p_date timestamptz,
 p_note text,p_payment_info_id bigint,p_purpose text,p_request uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
    v_account_id bigint;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
    v_candidate_ids bigint[];
    v_order eshop.orders;
    v_unit bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    IF p_amount IS NULL OR p_amount=0 OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount*100<>trunc(p_amount*100)
       OR p_currency IS NULL OR p_currency NOT IN ('CZK','EUR','PLN','USD','GBP') OR p_date IS NULL THEN
      RAISE EXCEPTION 'CASH_AMOUNT_INVALID'; END IF;
    IF p_payment_info_id IS NULL AND p_variable_symbol ~ '^[0-9]{1,10}$' THEN
      SELECT array_agg(pi.id ORDER BY pi.id) INTO v_candidate_ids FROM eshop.payment_info pi
      JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
      WHERE pi.variable_symbol=p_variable_symbol::bigint AND trim(pi.currency_code)=p_currency AND oc.unit=p_unit_id;
      IF cardinality(v_candidate_ids)=1 THEN
        RETURN public.write_cash_movement_internal(p_amount,p_currency,p_unit_id,p_variable_symbol,p_date,p_note,v_candidate_ids[1],p_purpose,p_request);
      END IF;
    END IF;
    IF p_payment_info_id IS NOT NULL THEN
      SELECT * INTO STRICT v_order FROM eshop.orders WHERE payment_info=p_payment_info_id;
      PERFORM public.lock_order_capacity_scope_internal(ARRAY[v_order.id]);
      SELECT unit INTO v_unit FROM public.occasions WHERE id=v_order.occasion;
      IF v_unit IS DISTINCT FROM p_unit_id OR trim(v_order.currency_code) IS DISTINCT FROM p_currency THEN
        RAISE EXCEPTION 'CASH_ORDER_SCOPE_MISMATCH'; END IF;
      IF p_purpose<>'refund' THEN PERFORM public.check_order_is_mutable(v_order.id); END IF;
      PERFORM 1 FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
      IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=v_order.id) THEN RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS'; END IF;
      IF p_amount<0 AND p_purpose<>'refund' THEN
        PERFORM public.assert_payment_refund_reservations_internal(p_payment_info_id,-p_amount);
      END IF;
    END IF;
    v_date := p_date;
    PERFORM pg_advisory_xact_lock(hashtextextended('cash-account:'||p_unit_id||':'||p_currency,79103));

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies)
    ORDER BY ba.id LIMIT 1;

    IF v_account_id IS NULL THEN
        INSERT INTO eshop.bank_accounts (
            title, type, supported_currencies, account_number, account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 'CASH', ARRAY[p_currency], '', ''
        )
        RETURNING id INTO v_account_id;

        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    INSERT INTO eshop.transactions (
        bank_account_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type,
        created_by,
        ingest_source
    ) VALUES (
        v_account_id,
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        CASE WHEN p_purpose='refund' THEN 'return' ELSE 'manual' END,
        auth.uid(),
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;

    END IF;

    IF v_payment_info_id IS NOT NULL THEN
        IF p_purpose='refund' THEN
          IF p_amount>=0 OR p_request IS NULL THEN RAISE EXCEPTION 'REFUND_CASH_INVALID'; END IF;
          UPDATE eshop.transactions SET payment_info=v_payment_info_id WHERE id=v_new_transaction_id;
          INSERT INTO eshop.refund_settlements(transaction_id,request_id,actor) VALUES(v_new_transaction_id,p_request,auth.uid());
          PERFORM public.refresh_payment_info_totals_internal(v_payment_info_id);
          PERFORM public.reconcile_order_payment_internal_v1(v_order.id,'refund_fact');
        ELSE
          PERFORM public.apply_transaction_pairing(v_new_transaction_id,v_payment_info_id,'manual_insert','user');
        END IF;
    END IF;
    RETURN v_new_transaction_id;
END;
$$;

REVOKE ALL ON FUNCTION public.write_cash_movement_internal(numeric,text,bigint,text,timestamptz,text,bigint,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
-- Released cash APIs and prepaid cash sales retain one ledger writer.
CREATE OR REPLACE FUNCTION public.insert_manual_transaction_internal_v1(
 p_amount numeric,p_currency text,p_unit_id bigint,p_variable_symbol text,p_date timestamptz,
 p_note text DEFAULT NULL,p_payment_info_id bigint DEFAULT NULL)
RETURNS bigint LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.write_cash_movement_internal(p_amount,p_currency,p_unit_id,p_variable_symbol,p_date,p_note,p_payment_info_id,'correction',NULL);
$$;
REVOKE ALL ON FUNCTION public.insert_manual_transaction_internal_v1(numeric,text,bigint,text,timestamptz,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
