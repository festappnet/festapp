-- 1. Drop ALL possible variations of the overloaded function to clean up
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(numeric, text, int, text, timestamp with time zone, text);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text, int);
DROP FUNCTION IF EXISTS public.insert_manual_transaction(double precision, text, int, text, text, text, bigint);

-- 2. Define the Canonical Function (using BIGINT for IDs)
CREATE OR REPLACE FUNCTION public.insert_manual_transaction(
    p_amount double precision,
    p_currency text,
    p_unit_id int,
    p_date text, -- Text date input for robustness
    p_variable_symbol text DEFAULT NULL,
    p_note text DEFAULT NULL,
    p_payment_info_id bigint DEFAULT NULL -- CORRECT TYPE
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
    INSERT INTO eshop.transactions (
        bank_account_id,
        transaction_id,
        amount,
        currency,
        date,
        vs,
        comment,
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

    -- 3. Link to Payment Info
    -- Priority 1: Explicit Payment Info ID
    IF p_payment_info_id IS NOT NULL THEN
         v_payment_info_id := p_payment_info_id;
    -- Priority 2: Variable Symbol
    ELSIF p_variable_symbol IS NOT NULL AND p_variable_symbol != '' THEN
        SELECT id INTO v_payment_info_id
        FROM eshop.payment_info
        WHERE variable_symbol = p_variable_symbol::bigint
        LIMIT 1;
    END IF;

    -- Perform Link
    IF v_payment_info_id IS NOT NULL THEN
            PERFORM public.add_transaction_to_payment_info(v_new_transaction_id, v_payment_info_id);
    END IF;

END;
$$;

-- Grant permissions explicitly
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text, bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.insert_manual_transaction(double precision, text, int, text, text, text, bigint) TO anon;

NOTIFY pgrst, 'reload schema';

-- 3. Check for supabase_migrations table and DROP IT if it is in public (as requested by user)
-- DO $$
-- BEGIN
--     IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'supabase_migrations') THEN
--         DROP TABLE public.supabase_migrations;
--         RAISE NOTICE 'Dropped public.supabase_migrations table as requested.';
--     ELSE
--         RAISE NOTICE 'Table public.supabase_migrations does not exist (it might be in another schema or already gone).';
--     END IF;
-- END $$;
