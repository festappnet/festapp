CREATE OR REPLACE FUNCTION generate_payment_variable_symbol(p_bank_account_id BIGINT, p_form_id BIGINT)
RETURNS BIGINT
SET search_path = public, extensions AS $$
DECLARE
    -- Variables for form configuration
    v_form_data JSONB;
    v_vs_config JSONB;
    v_vs_type TEXT;
    v_starting_number BIGINT;
    v_max_symbol_for_form BIGINT;

    -- General variable for the symbol to be returned
    v_candidate_symbol BIGINT;

    -- Variables for the random generation fallback
    v_digit_count INT := 4;
    v_attempt_count INT := 0;
    v_max_attempts INT := 1;
    v_safety_counter INT := 0; -- Safety break for the sequential loop
BEGIN
    IF public.payment_reference_scope_enabled_internal(p_form_id) THEN
      RAISE EXCEPTION 'PAYMENT_REFERENCE_RESERVATION_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM eshop.payment_reference_namespaces n
      WHERE n.canonical_account=public.try_payment_reference_account_internal((SELECT account_number FROM eshop.bank_accounts WHERE id=p_bank_account_id))
      AND (n.allocation_enabled OR EXISTS(SELECT 1 FROM eshop.payment_reference_reservations r WHERE r.namespace_id=n.id))) THEN
      RAISE EXCEPTION 'PAYMENT_REFERENCE_SHARED_ACCOUNT_REQUIRES_ENROLLMENT'; END IF;
    -- 1. Fetch the configuration data for the given form
    SELECT data INTO v_form_data FROM public.forms WHERE id = p_form_id;

    -- Raise an error if the form does not exist
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Form with ID % not found.', p_form_id;
    END IF;

    -- 2. Check for custom variable symbol configuration within the JSONB data
    -- We use COALESCE to default to 'random' if the setting is missing, making the function robust.
    v_vs_config := v_form_data -> 'variable_symbol';
    v_vs_type := COALESCE(v_vs_config ->> 'type', 'random');

    -- 3. Main logic: Choose between 'sequence' and 'random' generation
    IF v_vs_type = 'sequence' THEN
        ----------------------------------------------------
        -- LOGIC FOR SEQUENTIAL VARIABLE SYMBOL GENERATION --
        ----------------------------------------------------

        -- Get the defined starting number from the form's configuration
        v_starting_number := (v_vs_config ->> 'starting_number')::BIGINT;
        IF v_starting_number IS NULL THEN
            RAISE EXCEPTION 'Form with ID % is configured for sequential variable symbols, but "starting_number" is missing in its data.', p_form_id;
        END IF;

        -- Find the highest existing variable symbol used for this specific form.
        -- We must join through the orders table to link payments to a form.
        SELECT MAX(pi.variable_symbol)
        INTO v_max_symbol_for_form
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON pi.id = o.payment_info
        WHERE o.form = p_form_id;

        -- Determine the first candidate for our new variable symbol.
        -- If no previous symbol exists for this form, use the starting number.
        -- Otherwise, take the highest existing symbol and add 1.
        -- The GREATEST function handles the edge case where the starting_number was increased after symbols were already generated.
        IF v_max_symbol_for_form IS NULL THEN
            v_candidate_symbol := v_starting_number;
        ELSE
            v_candidate_symbol := GREATEST(v_max_symbol_for_form + 1, v_starting_number);
        END IF;

        -- Loop to ensure the candidate symbol is unique for the target bank account.
        -- If the symbol is already taken, increment and check again.
        LOOP
            IF NOT EXISTS (
                SELECT 1
                FROM eshop.payment_info
                WHERE variable_symbol = v_candidate_symbol AND bank_account = p_bank_account_id
            ) THEN
                RETURN v_candidate_symbol; -- The symbol is unique, return it.
            END IF;

            -- The symbol was taken, so we increment and try the next one.
            v_candidate_symbol := v_candidate_symbol + 1;

            -- Add a safety break to prevent an infinite loop in unusual circumstances.
            v_safety_counter := v_safety_counter + 1;
            IF v_safety_counter > 1000 THEN
                RAISE EXCEPTION 'Could not find a unique sequential variable symbol for bank account % after 1000 attempts.', p_bank_account_id;
            END IF;
        END LOOP;

    ELSE
        ------------------------------------------------
        -- LOGIC FOR RANDOM VARIABLE SYMBOL GENERATION --
        ------------------------------------------------

        LOOP
            -- Generate a random number with the current digit count
            v_candidate_symbol := FLOOR(RANDOM() * (POWER(10, v_digit_count) - POWER(10, v_digit_count - 1))) + POWER(10, v_digit_count - 1);

            -- Ensure uniqueness within the bank_account
            IF NOT EXISTS (
                SELECT 1
                FROM eshop.payment_info
                WHERE variable_symbol = v_candidate_symbol AND bank_account = p_bank_account_id
            ) THEN
                RETURN v_candidate_symbol; -- Return the unique variable symbol
            END IF;

            -- Increment attempt count and adjust digit count after each failure
            v_attempt_count := v_attempt_count + 1;

            -- Extend digit count after reaching max attempts
            IF v_attempt_count >= v_max_attempts THEN
                v_digit_count := v_digit_count + 1;
                v_attempt_count := 0; -- Reset attempt count for the extended digit count
            END IF;

            -- Fail entirely if the system cannot generate a unique symbol after too many attempts
            IF v_digit_count > 10 THEN -- Arbitrary upper limit for digit count
                RAISE EXCEPTION 'Failed to generate a unique random variable symbol after too many attempts.';
            END IF;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.generate_payment_variable_symbol(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
