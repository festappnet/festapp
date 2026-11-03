CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text,
    p_note text DEFAULT NULL,
    p_payment_info_id int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
    v_candidate_ids bigint[];
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

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
        'manual',
        auth.uid(),
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;
    ELSIF p_variable_symbol IS NOT NULL AND p_variable_symbol ~ '^[0-9]{1,10}$' THEN
        SELECT array_agg(pi.id ORDER BY pi.id) INTO v_candidate_ids
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        JOIN public.occasions oc ON oc.id = o.occasion
        WHERE pi.variable_symbol = p_variable_symbol::bigint
          AND upper(trim(pi.currency_code::text)) = upper(trim(p_currency))
          AND oc.unit = p_unit_id;
        IF cardinality(v_candidate_ids) = 1 THEN
          v_payment_info_id := v_candidate_ids[1];
        END IF;
    END IF;

    IF v_payment_info_id IS NOT NULL THEN
        PERFORM public.apply_transaction_pairing(
          v_new_transaction_id, v_payment_info_id, 'manual_insert', 'user'
        );
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision,text,integer,text,text,text,integer)
  TO authenticated;
