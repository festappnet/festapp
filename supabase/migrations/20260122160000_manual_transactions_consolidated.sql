-- Add created_by column to transactions if not exists
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'eshop' AND table_name = 'transactions' AND column_name = 'created_by') THEN
        ALTER TABLE eshop.transactions ADD COLUMN created_by UUID REFERENCES public.user_info(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'eshop' AND table_name = 'transactions' AND column_name = 'sender_name') THEN
        ALTER TABLE eshop.transactions ADD COLUMN sender_name TEXT NULL;
    END IF;
END $$;

-- RLS Policy: Allow managers to see transactions for their units
DROP POLICY IF EXISTS "Managers can view transactions for their units" ON eshop.transactions;

CREATE POLICY "Managers can view transactions for their units"
ON eshop.transactions
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 
        FROM eshop.unit_bank_accounts uba
        JOIN public.unit_users uu ON uba.unit = uu.unit
        WHERE uba.bank_account = eshop.transactions.bank_account_id
          AND uu."user" = auth.uid()
          AND uu.is_manager = true
    )
);

-- Drop previous/conflicting definitions
DROP FUNCTION IF EXISTS public.insert_manual_transaction(numeric, text, int, text, timestamp with time zone, text);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);

-- Re-define RPC with payment logic
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text, -- Text date input for robustness
    p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    -- Cast date
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

    IF v_account_id IS NULL THEN
        -- Create Bank Account
        INSERT INTO eshop.bank_accounts (
            title, 
            type, 
            supported_currencies, 
            account_number, 
            account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 
            'CASH', 
            ARRAY[p_currency], 
            '', 
            ''
        )
        RETURNING id INTO v_account_id;

        -- Link to Unit
        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    -- sender_name not included; superseded by counter_account_name
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type
    ) VALUES (
        v_account_id,
        ('-1' || (extract(epoch from now()) * 1000)::bigint::text)::bigint, 
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    -- Only if variable symbol is provided
    IF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        -- Find payment info that matches VS (relaxed match)
        BEGIN
            SELECT id INTO v_payment_info_id
            FROM eshop.payment_info
            WHERE variable_symbol = p_variable_symbol::bigint
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
             -- If cast fails (e.g. user entered "ABC"), we just ignore linking
             v_payment_info_id := NULL;
        END;

        IF v_payment_info_id IS NOT NULL THEN
             PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
        END IF;
    END IF;

END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO postgres;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO anon;

NOTIFY pgrst, 'reload schema';
CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    transaction_type text;
    payment_info_currency character(3);
    payment_info_record eshop.payment_info%ROWTYPE;
    associated_order_id bigint;
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    --- Retrieve the associated order_id from payment_info
     SELECT pi.bank_account INTO bank_acc
     FROM eshop.payment_info pi
     WHERE pi.id = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_admin_for_bank_account(bank_acc);

     SELECT o.occasion
     INTO occasion_id
     FROM eshop.orders o
     WHERE o.payment_info = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_editor_order_on_occasion(occasion_id);
    
    -- Check if the transaction is linked to the specified payment_info
    -- (We don't need to check link if we are deleting? Well, yes, we assume we are deleting it FROM this payment info context)
    IF NOT EXISTS (
        SELECT 1
        FROM eshop.transactions
        WHERE id = p_transaction_id
          AND payment_info = p_payment_info_id
    ) THEN
        RAISE EXCEPTION 'Transaction % is not linked to Payment Info %.', p_transaction_id, p_payment_info_id;
    END IF;

    -- Retrieve the transaction amount, currency and TYPE
    SELECT t.amount, t.currency, t.transaction_type
    INTO transaction_amount, transaction_currency, transaction_type
    FROM eshop.transactions t
    WHERE t.id = p_transaction_id
      AND t.payment_info = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % not found.', p_transaction_id;
    END IF;

    IF transaction_type != 'manual' THEN
         RAISE EXCEPTION 'Transaction % is not of type manual (cash). Cannot delete non-manual transactions via this operation.', p_transaction_id;
    END IF;

    -- Retrieve the payment_info currency_code
    SELECT pi.currency_code
    INTO payment_info_currency
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment Info % does not exist.', p_payment_info_id;
    END IF;

    -- Check if currencies match
    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch: Transaction currency (%) does not match Payment Info currency (%)', transaction_currency, payment_info_currency;
    END IF;

    -- Adjust the paid or returned column based on the transaction amount
    IF transaction_amount > 0 THEN
        -- Ensure that the payment_info has enough 'paid' amount to deduct
        IF (SELECT COALESCE(paid, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient paid amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) - transaction_amount
        WHERE id = p_payment_info_id;
    ELSE
        -- Transaction was a return; ensure enough 'returned' amount to deduct
        IF (SELECT COALESCE(returned, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient returned amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + transaction_amount
        WHERE id = p_payment_info_id;
    END IF;

    -- Fetch the updated payment_info record
    SELECT *
    INTO payment_info_record
    FROM eshop.payment_info
    WHERE id = p_payment_info_id;

    -- DELETE the transaction entirely
    DELETE FROM eshop.transactions
    WHERE id = p_transaction_id;

    RAISE NOTICE 'Manual Transaction % successfully deleted from Payment Info %.', p_transaction_id, p_payment_info_id;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to delete Transaction % from Payment Info %: %', p_transaction_id, p_payment_info_id, SQLERRM;
END;
$$ SECURITY DEFINER;
CREATE OR REPLACE FUNCTION get_report_for_occasion(occasion_id bigint)
RETURNS TEXT AS $$
DECLARE
    total_spots             INT;
    booked_spots            INT;
    free_spots              INT;
    total_tickets_ordered   INT;
    total_tickets_paid      INT;
    total_tickets_sent      INT;
    total_tickets_used      INT;
    total_tickets_canceled  INT;
    total_orders            INT;
    ordered_orders          INT;
    paid_orders             INT;
    sent_orders             INT;
    canceled_orders         INT;

    -- For per-currency revenue
    rec_rev     RECORD;
    currency_count INT;
    single_cc    TEXT;
    total_revenue     NUMERIC;
    paid_revenue      NUMERIC;
    paid_cash         NUMERIC; -- NEW
    paid_bank         NUMERIC; -- NEW
    returned_revenue  NUMERIC;
    result_revenue    NUMERIC;
    remaining_balance NUMERIC;
    revenue_section   TEXT;

    -- Variables for product type counts
    rec_product_type     RECORD;
    current_product_type TEXT := '';
    product_type_section TEXT := E'===========\nPočet zaplacených produktů podle typu:\n';
BEGIN
    -- 1) Spots ... (Unchanged)
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE order_product_ticket IS NOT NULL),
        COUNT(*) FILTER (WHERE order_product_ticket IS NULL)
    INTO
        total_spots, booked_spots, free_spots
    FROM eshop.spots
    WHERE occasion = occasion_id;

    -- 2) Tickets ... (Unchanged)
    SELECT
        COUNT(DISTINCT t.id) FILTER (WHERE t.state = 'ordered'),
        COUNT(DISTINCT t.id) FILTER (WHERE t.state = 'paid'),
        COUNT(DISTINCT t.id) FILTER (WHERE t.state = 'sent'),
        COUNT(DISTINCT t.id) FILTER (WHERE t.state = 'used'),
        COUNT(DISTINCT t.id) FILTER (WHERE t.state = 'storno')
    INTO
        total_tickets_ordered,
        total_tickets_paid,
        total_tickets_sent,
        total_tickets_used,
        total_tickets_canceled
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
    WHERE t.occasion = occasion_id;

    -- 3) Orders ... (Unchanged)
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE state = 'ordered'),
        COUNT(*) FILTER (WHERE state = 'paid'),
        COUNT(*) FILTER (WHERE state = 'sent'),
        COUNT(*) FILTER (WHERE state = 'storno')
    INTO
        total_orders, ordered_orders, paid_orders, sent_orders, canceled_orders
    FROM eshop.orders
    WHERE occasion = occasion_id;

    -- 4) Count distinct currencies
    SELECT
        COUNT(DISTINCT o.currency_code)
    INTO
        currency_count
    FROM eshop.orders o
    WHERE o.occasion = occasion_id;

    IF currency_count = 1 THEN
        -- Single currency: compute sums directly
        SELECT
            o.currency_code,
            COALESCE(SUM(o.price),   0),
            COALESCE(SUM(pi.paid),   0),
            COALESCE(SUM(pi.returned),0),
            -- Manual (Cash)
            COALESCE(SUM(
                (SELECT COALESCE(SUM(t.amount), 0) 
                 FROM eshop.transactions t 
                 WHERE t.payment_info = pi.id AND t.transaction_type = 'manual')
            ), 0),
            -- Bank (Others = Total Paid - Manual? Or explicit sum?)
            -- Using explicit sum ensures we track what is actually IN transactions.
            -- However, pi.paid might technically differ if there were manual DB edits.
            -- User wants distinction. Let's calculate Bank as Paid - Cash to ensure they sum up to Paid?
            -- No, "Normal transaction and cash transaction".
            -- If we trust pi.paid is the master total, then Bank = pi.paid - Cash.
            -- BUT, let's sum transactions for 'bank' explicitly to see if they match? 
            -- Actually, to be safe and consistent with the total 'Paid' line:
            --   Total Paid = X
            --     Cash: Y
            --     Bank: Z
            -- If Y+Z != X, it might be confusing. 
            -- Safest approach: 
            --   Cash = Sum(Manual Transactions)
            --   Bank = PaymentInfo.Paid - Cash (Treat 'Paid' as the source of truth for total, and Cash as the specific component).
            -- This handles cases where transactions might be missing but balance was set.
            -- ... Actually, if transactions are the ONLY way to pay, then Sum(Trans) == Paid.
            -- Let's go with: Bank = Paid - Cash.
            COALESCE(SUM(pi.paid), 0) - 
            COALESCE(SUM(
                (SELECT COALESCE(SUM(t.amount), 0) 
                 FROM eshop.transactions t 
                 WHERE t.payment_info = pi.id AND t.transaction_type = 'manual')
            ), 0)
        INTO
            single_cc,
            total_revenue,
            paid_revenue,
            returned_revenue,
            paid_cash,
            paid_bank
        FROM eshop.orders o
        LEFT JOIN eshop.payment_info pi ON pi.id = o.payment_info
        WHERE o.occasion = occasion_id
        GROUP BY o.currency_code;

        result_revenue    := paid_revenue - returned_revenue;
        remaining_balance := total_revenue - (paid_revenue - returned_revenue);

        revenue_section := E'===========\nPřehled tržeb:\n' ||
            E'    • Suma všech objednávek: '   || to_char(total_revenue,     'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'    • Suma přijatých částek: '  || to_char(paid_revenue,      'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'         - Banka: '             || to_char(paid_bank,         'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'         - Hotovost: '          || to_char(paid_cash,         'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'    • Suma vrácených částek: '  || to_char(returned_revenue,  'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'    • Výsledná částka: '         || to_char(result_revenue,    'FM99999990.00') || ' ' || single_cc || E'\n' ||
            E'    • Zbývající částka: '       || to_char(remaining_balance,'FM99999990.00') || ' ' || single_cc || E'\n';
    ELSE
        -- Multiple currencies: loop per currency
        revenue_section := E'===========\nPřehled tržeb podle měny:\n';
        FOR rec_rev IN
            SELECT
                o.currency_code,
                COALESCE(SUM(o.price),   0) AS total_revenue,
                COALESCE(SUM(pi.paid),   0) AS paid_revenue,
                COALESCE(SUM(pi.returned),0) AS returned_revenue,
                -- Cash
                COALESCE(SUM(
                    (SELECT COALESCE(SUM(t.amount), 0) 
                     FROM eshop.transactions t 
                     WHERE t.payment_info = pi.id AND t.transaction_type = 'manual')
                ), 0) AS paid_cash
            FROM eshop.orders o
            LEFT JOIN eshop.payment_info pi ON pi.id = o.payment_info
            WHERE o.occasion = occasion_id
            GROUP BY o.currency_code
            ORDER BY o.currency_code
        LOOP
            result_revenue    := rec_rev.paid_revenue - rec_rev.returned_revenue;
            remaining_balance := rec_rev.total_revenue - rec_rev.paid_revenue;
            paid_bank         := rec_rev.paid_revenue - rec_rev.paid_cash;
            
            revenue_section := revenue_section ||
                E' - ' || rec_rev.currency_code || E':\n' ||
                E'    • Suma všech objednávek: '   || to_char(rec_rev.total_revenue,    'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'    • Suma přijatých částek: '  || to_char(rec_rev.paid_revenue,     'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'         - Banka: '             || to_char(paid_bank,                'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'         - Hotovost: '          || to_char(rec_rev.paid_cash,        'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'    • Suma vrácených částek: '  || to_char(rec_rev.returned_revenue, 'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'    • Výsledná částka: '         || to_char(result_revenue,           'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n' ||
                E'    • Zbývající částka: '       || to_char(remaining_balance,       'FM99999990.00') || ' ' || rec_rev.currency_code || E'\n';
        END LOOP;
    END IF;

    -- 5) Products by type ... (Unchanged)
    FOR rec_product_type IN
        SELECT
            pt.title   AS product_type,
            p.title    AS product_title,
            COUNT(opt.product) AS ordered_count
        FROM eshop.order_product_ticket opt
        JOIN eshop.products p          ON opt.product      = p.id
        JOIN eshop.product_types pt    ON p.product_type   = pt.id
        JOIN eshop.orders o            ON o.id             = opt."order"
        WHERE p.occasion = occasion_id
          AND o.state NOT IN ('storno','ordered')
        GROUP BY pt.title, p.title
        ORDER BY pt.title, p.title
    LOOP
        IF rec_product_type.product_type <> current_product_type THEN
            current_product_type := rec_product_type.product_type;
            product_type_section := product_type_section || E' - ' || current_product_type || E':\n';
        END IF;
        product_type_section := product_type_section ||
            E'    • ' || rec_product_type.product_title || E': ' || rec_product_type.ordered_count || E'\n';
    END LOOP;
    IF product_type_section = E'===========\nPočet zaplacených produktů podle typu:\n' THEN
        product_type_section := product_type_section || E' - Žádné zaplacené produkty.\n';
    END IF;

    -- 6) Assemble final report ... (Unchanged)
    RETURN
        E'===========\n' ||
        E'Počet míst celkem: '     || to_char(total_spots,              'FM9999') || E'\n' ||
        E'Počet volných: '          || to_char(free_spots,               'FM9999') || E'\n' ||
        E'Počet obsazených: '       || to_char(booked_spots,             'FM9999') || E'\n' ||
        E'Počet objednaných: '      || to_char(total_tickets_ordered,    'FM9999') || E'\n' ||
        E'Počet zaplacených: '      || to_char(total_tickets_paid,       'FM9999') || E'\n' ||
        E'Počet odeslaných: '       || to_char(total_tickets_sent,       'FM9999') || E'\n' ||
        E'Počet využitých: '        || to_char(total_tickets_used,       'FM9999') || E'\n' ||
        E'Počet storno: '           || to_char(total_tickets_canceled,   'FM9999') || E'\n' ||
        E'===========\n' ||
        E'Počet objednávek celkem: '|| to_char(total_orders,             'FM9999') || E'\n' ||
        E'Objednáno: '              || to_char(ordered_orders,           'FM9999') || E'\n' ||
        E'Zaplaceno: '              || to_char(paid_orders,              'FM9999') || E'\n' ||
        E'Odesláno: '               || to_char(sent_orders,              'FM9999') || E'\n' ||
        E'Storno: '                 || to_char(canceled_orders,          'FM9999') || E'\n' ||
        product_type_section ||
        revenue_section ||
        E'===========';
EXCEPTION
    WHEN OTHERS THEN
        RETURN E'An unexpected error occurred: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
-- RLS Policy: Allow managers to see transactions for their units
DROP POLICY IF EXISTS "Managers can view transactions for their units" ON eshop.transactions;

CREATE POLICY "Managers can view transactions for their units"
ON eshop.transactions
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 
        FROM eshop.unit_bank_accounts uba
        JOIN public.unit_users uu ON uba.unit = uu.unit
        WHERE uba.bank_account = eshop.transactions.bank_account_id
          AND uu."user" = auth.uid()
          AND uu.is_manager = true
    )
);

-- Drop previous/conflicting definitions if any (from development process)
DROP FUNCTION IF EXISTS public.insert_manual_transaction(numeric, text, int, text, timestamp with time zone, text);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);

-- Re-define RPC with payment logic
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text, -- Text date input for robustness
    p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    -- Cast date
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

    IF v_account_id IS NULL THEN
        -- Create Bank Account
        INSERT INTO eshop.bank_accounts (
            title, 
            type, 
            supported_currencies, 
            account_number, 
            account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 
            'CASH', 
            ARRAY[p_currency], 
            '', 
            ''
        )
        RETURNING id INTO v_account_id;

        -- Link to Unit
        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    -- Use explicit cast for generated transaction_id
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type,
        sender_name
    ) VALUES (
        v_account_id,
        ('-1' || (extract(epoch from now()) * 1000)::bigint::text)::bigint, 
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        'manual',
        'Hotovost / Cash'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    -- Only if variable symbol is provided
    IF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        -- Find payment info that matches VS (relaxed match)
        BEGIN
            SELECT id INTO v_payment_info_id
            FROM eshop.payment_info
            WHERE variable_symbol = p_variable_symbol::bigint
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
             -- If cast fails (e.g. user entered "ABC"), we just ignore linking
             v_payment_info_id := NULL;
        END;

        IF v_payment_info_id IS NOT NULL THEN
             PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
        END IF;
    END IF;

END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO postgres;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO anon;

NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload schema';
-- RLS Policy: Allow managers to see transactions for their units
DROP POLICY IF EXISTS "Managers can view transactions for their units" ON eshop.transactions;

CREATE POLICY "Managers can view transactions for their units"
ON eshop.transactions
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 
        FROM eshop.unit_bank_accounts uba
        JOIN public.unit_users uu ON uba.unit = uu.unit
        WHERE uba.bank_account = eshop.transactions.bank_account_id
          AND uu."user" = auth.uid()
          AND uu.is_manager = true
    )
);

-- Drop previous/conflicting definitions
DROP FUNCTION IF EXISTS public.insert_manual_transaction(numeric, text, int, text, timestamp with time zone, text);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);

-- Re-define RPC with payment logic
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text, -- Text date input for robustness
    p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    -- Cast date
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

    IF v_account_id IS NULL THEN
        -- Create Bank Account
        INSERT INTO eshop.bank_accounts (
            title, 
            type, 
            supported_currencies, 
            account_number, 
            account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 
            'CASH', 
            ARRAY[p_currency], 
            '', 
            ''
        )
        RETURNING id INTO v_account_id;

        -- Link to Unit
        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    -- sender_name not included; superseded by counter_account_name
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type
    ) VALUES (
        v_account_id,
        ('-1' || (extract(epoch from now()) * 1000)::bigint::text)::bigint, 
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    -- Only if variable symbol is provided
    IF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        -- Find payment info that matches VS (relaxed match)
        BEGIN
            SELECT id INTO v_payment_info_id
            FROM eshop.payment_info
            WHERE variable_symbol = p_variable_symbol::bigint
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
             -- If cast fails (e.g. user entered "ABC"), we just ignore linking
             v_payment_info_id := NULL;
        END;

        IF v_payment_info_id IS NOT NULL THEN
             PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
        END IF;
    END IF;

END;
$$;

GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO postgres;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text) TO anon;

NOTIFY pgrst, 'reload schema';
-- Re-define RPC with payment logic
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_date text, -- Text date input for robustness
    p_variable_symbol text DEFAULT NULL,
    p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    -- Cast date
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

    IF v_account_id IS NULL THEN
        -- Create Bank Account
        INSERT INTO eshop.bank_accounts (
            title, 
            type, 
            supported_currencies, 
            account_number, 
            account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 
            'CASH', 
            ARRAY[p_currency], 
            '', 
            ''
        )
        RETURNING id INTO v_account_id;

        -- Link to Unit
        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    -- Use comment for p_note, NULL for message_for_recipient
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        comment,
        transaction_type
    ) VALUES (
        v_account_id,
        ('-1' || (extract(epoch from now()) * 1000)::bigint::text)::bigint, 
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        'manual'
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    -- Only if variable symbol is provided
    IF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        -- Find payment info that matches VS (relaxed match)
        BEGIN
            SELECT id INTO v_payment_info_id
            FROM eshop.payment_info
            WHERE variable_symbol = p_variable_symbol::bigint
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
             -- If cast fails (e.g. user entered "ABC"), we just ignore linking
             v_payment_info_id := NULL;
        END;

        IF v_payment_info_id IS NOT NULL THEN
             PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
        END IF;
    END IF;

END;
$$;

NOTIFY pgrst, 'reload schema';
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    IF current_state != 'ordered' AND current_state != 'created' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered" or "created" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now()
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state != 'storno';

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;

NOTIFY pgrst, 'reload schema';
-- Re-define RPC with payment logic
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);

DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text, int);

CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_variable_symbol text,
    p_date text, -- Text date input for robustness
    p_note text DEFAULT NULL,
    p_payment_info_id int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id int;
    v_date timestamp with time zone;
    v_new_transaction_id bigint;
    v_payment_info_id bigint;
BEGIN
    -- Check permissions (must be Unit Manager)
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    -- Cast date
    v_date := p_date::timestamp with time zone;

    -- 1. Find or Create CASH account
    SELECT ba.id INTO v_account_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = p_unit_id 
      AND ba.type = 'CASH'
      AND p_currency = ANY(ba.supported_currencies);

    IF v_account_id IS NULL THEN
        -- Create Bank Account
        INSERT INTO eshop.bank_accounts (
            title, 
            type, 
            supported_currencies, 
            account_number, 
            account_number_human_readable
        ) VALUES (
            'Cash Account (' || p_currency || ')', 
            'CASH', 
            ARRAY[p_currency], 
            '', 
            ''
        )
        RETURNING id INTO v_account_id;

        -- Link to Unit
        INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
        VALUES (p_unit_id, v_account_id, 0);
    END IF;

    -- 2. Insert Transaction
    -- Use explicit cast for generated transaction_id
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        message_for_recipient,
        transaction_type,
        sender_name,
        created_by
    ) VALUES (
        v_account_id,
        ('-1' || (extract(epoch from now()) * 1000)::bigint::text)::bigint, 
        p_amount,
        p_currency,
        v_date,
        p_variable_symbol,
        p_note,
        'manual',
        'Hotovost / Cash',
        auth.uid()
    )
    RETURNING id INTO v_new_transaction_id;

    -- 3. Link to Payment Info & Update Order State
    -- Priority 1: Explicit Payment Info ID
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;
    -- Priority 2: Variable Symbol
    ELSIF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        -- Find payment info that matches VS (relaxed match)
        BEGIN
            SELECT id INTO v_payment_info_id
            FROM eshop.payment_info
            WHERE variable_symbol = p_variable_symbol::bigint
            LIMIT 1;
        EXCEPTION WHEN OTHERS THEN
             -- If cast fails (e.g. user entered "ABC"), we just ignore linking
             v_payment_info_id := NULL;
        END;
    END IF;

    -- Perform Link
    IF v_payment_info_id IS NOT NULL THEN
            PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
    END IF;

END;
$$;

NOTIFY pgrst, 'reload schema';
-- 1. Create Unified Helper Function
CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_price numeric;
    v_state text;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Get Paid Amount from Payment Info
    SELECT paid INTO v_paid
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    -- If fully paid, transition to 'paid' (if valid state)
    -- Use COALESCE(v_paid, 0) because newly created payment_info has NULL paid
    IF COALESCE(v_paid, 0) >= v_price THEN
        PERFORM public.update_order_and_tickets_to_paid(p_order_id);
    END IF;


END;
$$;

-- 2. Update add_transaction_to_payment_info to use the helper
CREATE OR REPLACE FUNCTION public.add_transaction_to_payment_info(p_transaction_id bigint, payment_info_id bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    payment_info_currency character(3);
    payment_info_record eshop.payment_info%ROWTYPE;
    associated_order_id bigint;
BEGIN
    -- Check if the transaction already has a payment_info assigned
    IF EXISTS (
        SELECT 1
        FROM eshop.transactions
        WHERE id = p_transaction_id
          AND payment_info IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Transaction already linked to a payment_info';
    END IF;

    -- Retrieve the transaction amount and currency
    SELECT t.amount, t.currency
    INTO transaction_amount, transaction_currency
    FROM eshop.transactions t
    WHERE t.id = p_transaction_id;

    -- Retrieve the payment_info currency_code
    SELECT pi.currency_code
    INTO payment_info_currency
    FROM eshop.payment_info pi
    WHERE pi.id = payment_info_id;

    -- Check if currencies match
    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch: Transaction currency (%) does not match Payment Info currency (%)', transaction_currency, payment_info_currency;
    END IF;

    -- Update the paid or returned column based on the transaction amount
    IF transaction_amount > 0 THEN
        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) + transaction_amount
        WHERE id = payment_info_id;
    ELSE
        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + ABS(transaction_amount)
        WHERE id = payment_info_id;
    END IF;

    -- Fetch the updated payment_info record (for logging or return if needed, but primarily we need order id now)
    SELECT *
    INTO payment_info_record
    FROM eshop.payment_info
    WHERE id = payment_info_id;

    -- Find the associated order ID
    SELECT o.id
    INTO associated_order_id
    FROM eshop.orders o
    WHERE o.payment_info = payment_info_id
    LIMIT 1;

    -- Call the Unified Helper to resolve state
    IF associated_order_id IS NOT NULL THEN
        PERFORM public.recalculate_order_payment_status(associated_order_id);
    END IF;

    -- Update the transaction's payment_info reference
    UPDATE eshop.transactions
    SET payment_info = payment_info_id
    WHERE id = p_transaction_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.recalculate_order_payment_status(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalculate_order_payment_status(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.recalculate_order_payment_status(bigint) TO postgres;

NOTIFY pgrst, 'reload schema';
-- 1. Update Helper Function to handle reversion
CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_price numeric;
    v_state text;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Get Paid Amount from Payment Info
    SELECT paid INTO v_paid
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    IF COALESCE(v_paid, 0) >= v_price THEN
        -- Fully Paid -> Move to Paid
        IF v_state != 'paid' AND (v_state = 'ordered' OR v_state = 'created' OR v_state = 'expired') THEN
             PERFORM public.update_order_and_tickets_to_paid(p_order_id);
        END IF;
    ELSE
        -- Underpaid -> Revert to Ordered (if currently Paid)
        IF v_state = 'paid' THEN
            -- Revert Order
            UPDATE eshop.orders
            SET state = 'ordered', updated_at = now()
            WHERE id = p_order_id;
            
            -- Revert Tickets (only those that are 'paid')
            UPDATE eshop.tickets
            SET state = 'valid', updated_at = now() -- or 'ordered'?'valid'? 'ordered' seems safer for system consistency if not paid. 

            FROM eshop.order_product_ticket
            WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
            AND eshop.order_product_ticket."order" = p_order_id
            AND eshop.tickets.state = 'paid';
        END IF;
    END IF;
END;
$$;

-- 2. Update remove_transaction_from_payment_info_ws to use helper
CREATE OR REPLACE FUNCTION public.remove_transaction_from_payment_info_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    payment_info_currency character(3);
    payment_info_record eshop.payment_info%ROWTYPE;
    associated_order_id bigint;
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    --- Retrieve the associated order_id from payment_info
     SELECT pi.bank_account INTO bank_acc
     FROM eshop.payment_info pi
     WHERE pi.id = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_admin_for_bank_account(bank_acc);

     SELECT o.occasion
     INTO occasion_id
     FROM eshop.orders o
     WHERE o.payment_info = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_editor_order_on_occasion(occasion_id);
    
    -- Check if linked
    IF NOT EXISTS (SELECT 1 FROM eshop.transactions WHERE id = p_transaction_id AND payment_info = p_payment_info_id) THEN
        RAISE EXCEPTION 'Transaction % is not linked to Payment Info %.', p_transaction_id, p_payment_info_id;
    END IF;

    -- Retrieve transaction info
    SELECT t.amount, t.currency INTO transaction_amount, transaction_currency
    FROM eshop.transactions t WHERE t.id = p_transaction_id AND t.payment_info = p_payment_info_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Transaction not found or not linked.'; END IF;

    -- Retrieve payment info currency
    SELECT pi.currency_code INTO payment_info_currency
    FROM eshop.payment_info pi WHERE pi.id = p_payment_info_id;

    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch.';
    END IF;

    -- Adjust paid/returned
    IF transaction_amount > 0 THEN
        IF (SELECT COALESCE(paid, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient paid amount.';
        END IF;

        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) - transaction_amount
        WHERE id = p_payment_info_id;
    ELSE
        IF (SELECT COALESCE(returned, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient returned amount.';
        END IF;

        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + transaction_amount
        WHERE id = p_payment_info_id;
    END IF;

    -- Unlink
    UPDATE eshop.transactions
    SET payment_info = NULL
    WHERE id = p_transaction_id;

    -- Recalculate State
    SELECT o.id INTO associated_order_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    IF associated_order_id IS NOT NULL THEN
        PERFORM public.recalculate_order_payment_status(associated_order_id);
    END IF;

    RAISE NOTICE 'Transaction unlinked and state recalculated.';
END;
$$;

-- 3. Update delete_manual_transaction_ws to use helper
CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    transaction_type text;
    payment_info_currency character(3);
    associated_order_id bigint;
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    --- Retrieve the associated order_id from payment_info
     SELECT pi.bank_account INTO bank_acc
     FROM eshop.payment_info pi
     WHERE pi.id = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_admin_for_bank_account(bank_acc);

     SELECT o.occasion
     INTO occasion_id
     FROM eshop.orders o
     WHERE o.payment_info = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_editor_order_on_occasion(occasion_id);
    
    -- Check link
    IF NOT EXISTS (SELECT 1 FROM eshop.transactions WHERE id = p_transaction_id AND payment_info = p_payment_info_id) THEN
        RAISE EXCEPTION 'Transaction % is not linked to Payment Info %.', p_transaction_id, p_payment_info_id;
    END IF;

    -- Retrieve info
    SELECT t.amount, t.currency, t.transaction_type INTO transaction_amount, transaction_currency, transaction_type
    FROM eshop.transactions t WHERE t.id = p_transaction_id AND t.payment_info = p_payment_info_id;

    IF transaction_type != 'manual' THEN
         RAISE EXCEPTION 'Transaction % is not manual.', p_transaction_id;
    END IF;

    -- Currency check
    SELECT pi.currency_code INTO payment_info_currency FROM eshop.payment_info pi WHERE pi.id = p_payment_info_id;
    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch.';
    END IF;

    -- Adjust paid/returned
    IF transaction_amount > 0 THEN
        IF (SELECT COALESCE(paid, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient paid amount.';
        END IF;

        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) - transaction_amount
        WHERE id = p_payment_info_id;
    ELSE
        IF (SELECT COALESCE(returned, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient returned amount.';
        END IF;

        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + transaction_amount
        WHERE id = p_payment_info_id;
    END IF;

    -- DELETE
    DELETE FROM eshop.transactions WHERE id = p_transaction_id;

    -- Recalculate State
    SELECT o.id INTO associated_order_id
    FROM eshop.orders o
    WHERE o.payment_info = p_payment_info_id
    LIMIT 1;

    IF associated_order_id IS NOT NULL THEN
        PERFORM public.recalculate_order_payment_status(associated_order_id);
    END IF;

    RAISE NOTICE 'Manual transaction deleted and state recalculated.';
END;
$$;

NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION public.get_transactions_for_order(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_occasion_id bigint;
BEGIN

  SELECT occasion INTO v_occasion_id FROM eshop.orders WHERE id = order_id;
  IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION 'User is not authorized to view transactions for this occasion.' USING ERRCODE = 'P0001';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'payment_info', (
        SELECT to_jsonb(pi)
        FROM eshop.payment_info pi
        WHERE pi.id = o.payment_info
      ),
      'transactions', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(t) || jsonb_build_object('createdByName', 
                trim(both from COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, ''))
            )
        )
        FROM eshop.transactions t
        LEFT JOIN public.user_info ui ON t.created_by = ui.id
        WHERE t.payment_info = o.payment_info
      ), '[]'::jsonb)
    )
    FROM eshop.orders o
    WHERE o.id = order_id
  );
END;
$$;

NOTIFY pgrst, 'reload schema';
