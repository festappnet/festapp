BEGIN;
-- Coordinated expand. Production lock/index strategy requires measured readiness.
SET lock_timeout = '5s';
ALTER TABLE eshop.orders ADD COLUMN IF NOT EXISTS order_symbol text;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.orders'::regclass AND conname='orders_order_symbol_key') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_order_symbol_key UNIQUE(order_symbol);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.orders'::regclass AND conname='orders_order_symbol_format_check') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_order_symbol_format_check
   CHECK (order_symbol ~ '^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$') NOT VALID;
 END IF;
END $$;
-- Creation is RPC-only; existing notes/state writes already use authorized RPCs.
REVOKE INSERT, UPDATE, TRUNCATE, TRIGGER ON eshop.orders FROM PUBLIC, anon, authenticated, service_role;
-- Clear column grants too, including grants inherited from an earlier release.
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT attname FROM pg_attribute WHERE attrelid='eshop.orders'::regclass AND attnum>0 AND NOT attisdropped LOOP
  EXECUTE format('REVOKE INSERT (%I), UPDATE (%I) ON eshop.orders FROM PUBLIC, anon, authenticated, service_role', c.attname,c.attname);
 END LOOP;
END $$;
-- Invoker email producers use SELECT FOR UPDATE. PostgreSQL requires UPDATE
-- on at least one column for that lock; no identity or financial write grant.
GRANT UPDATE (note_hidden) ON eshop.orders TO service_role;
-- Private candidate generator. The global constraint owns uniqueness.
CREATE OR REPLACE FUNCTION public.generate_order_symbol()
RETURNS text LANGUAGE plpgsql VOLATILE
SET search_path = public, extensions AS $$
DECLARE
    alphabets text[] := ARRAY['123456789', 'ACEFGHIJKLMNPQRUVWXY'];
    bytes bytea := extensions.gen_random_bytes(64);
    pos integer := 0;
    b integer;
    alphabet text;
    symbol text := '';
BEGIN
    FOR pair IN 1..5 LOOP
        FOREACH alphabet IN ARRAY alphabets LOOP
            LOOP
                IF pos = length(bytes) THEN
                    bytes := extensions.gen_random_bytes(64);
                    pos := 0;
                END IF;
                b := get_byte(bytes, pos);
                pos := pos + 1;
                EXIT WHEN b < 256 - (256 % length(alphabet));
            END LOOP;
            symbol := symbol || substr(alphabet, (b % length(alphabet)) + 1, 1);
        END LOOP;
    END LOOP;
    RETURN symbol;
END;
$$;
ALTER FUNCTION public.generate_order_symbol() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.generate_order_symbol() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_ticket_order_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ? 'order_symbol' OR input_data ? 'orderSymbol'
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR SHARE;

        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;

        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        FOR allocation_attempt IN 1..10 LOOP
            INSERT INTO eshop.orders (created_at, updated_at, occasion, form, order_symbol)
            VALUES (now, now, occasion_id, form_id, public.generate_order_symbol())
            ON CONFLICT ON CONSTRAINT orders_order_symbol_key DO NOTHING
            RETURNING id, order_symbol INTO order_id, assigned_order_symbol;
            EXIT WHEN order_id IS NOT NULL;
            RAISE LOG 'order_symbol_collision attempt=%', allocation_attempt;
        END LOOP;
        IF order_id IS NULL THEN
            RAISE LOG 'order_symbol_allocation_exhausted';
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1013, 'message', 'Order symbol allocation exhausted')::TEXT;
        END IF;

        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            INSERT INTO eshop.tickets (state, occasion, ticket_symbol, note, created_at, updated_at)
            VALUES ('ordered', occasion_id, ticket_symbol, ticket_note, now, now)
            RETURNING id INTO ticket_id;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        generated_variable_symbol := generate_payment_variable_symbol(bank_account_id, form_id);
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_reminder_interval BIGINT;
                v_reminder_is_enabled BOOLEAN;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- Only queue reminder if deadline is in the future
                    IF v_deposit_deadline_ts > NOW() THEN
                        -- Get reminder interval from occasion form feature
                        SELECT elem->>'reminder_interval_seconds'
                        INTO v_reminder_interval
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        -- Check if reminder is enabled on the form feature
                        SELECT (elem->>'reminder_is_enabled')::boolean
                        INTO v_reminder_is_enabled
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        IF COALESCE(v_reminder_is_enabled, FALSE) AND v_reminder_interval IS NOT NULL THEN
                            PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',
                                jsonb_build_object('order_id',order_id,'is_deposit_reminder',true),organization_id,occasion_id,unit_id,
                                v_deposit_deadline_ts-make_interval(secs=>v_reminder_interval));
                        END IF;
                    END IF;
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE link = p_occasion_link
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE link = p_form_link
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders, conditionally filtering by form link
    IF v_form_id IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id AND o.form = v_form_id;
    ELSE
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_order_history(order_id bigint)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    v_occasion_id bigint;
    v_order_data jsonb;
    v_history_data jsonb;
    v_users_data jsonb;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT o.occasion, to_jsonb(o)
    INTO v_occasion_id, v_order_data
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- Check if the order exists
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
    END IF;

    -- Verify if the current user is an editor for the order's occasion
    IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this order history');
    END IF;

    -- Fetch history items for the order, ordered by creation date
    SELECT jsonb_agg(to_jsonb(h) || jsonb_build_object('order_symbol', v_order_data->>'order_symbol') ORDER BY h.created_at)
    INTO v_history_data
    FROM eshop.orders_history h
    WHERE h. "order" = order_id;

    -- Fetch unique users who created the history items
    WITH user_ids AS (
        SELECT DISTINCT created_by
        FROM eshop.orders_history
        WHERE "order" = order_id AND created_by IS NOT NULL
    )
    SELECT jsonb_agg(u.*)
    INTO v_users_data
    FROM public.user_info u
    WHERE u.id IN (SELECT created_by FROM user_ids);

    -- Return the combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'order', COALESCE(v_order_data, '{}'::jsonb),
            'history', COALESCE(v_history_data, '[]'::jsonb),
            'users', COALESCE(v_users_data, '[]'::jsonb)
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.get_latest_order_history(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT to_jsonb(o) || jsonb_build_object('order_symbol', (SELECT ord.order_symbol FROM eshop.orders ord WHERE ord.id=o."order"))
    INTO result
  FROM eshop.orders_history o
  WHERE o."order" = order_id AND (o.price <> 0 OR o.state IS DISTINCT FROM 'storno')
  -- Free orders also need cancellation emails; prefer the existing nonzero history.
  ORDER BY (o.price <> 0) DESC NULLS LAST, o.created_at DESC, o.id DESC
  LIMIT 1;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_email_occasion_context(p_occasion bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'unit',unit) FROM public.occasions WHERE id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_email_occasion_context(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_occasion_context(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.email_reporting_state(m public.email_messages) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN m.complained_at IS NOT NULL THEN 'complaint' WHEN m.bounced_at IS NOT NULL THEN 'bounce'
 WHEN m.last_error='post_action_failed' THEN 'post_action_failed' WHEN m.provider_failure IN ('reject','rendering_failure') THEN m.provider_failure
 WHEN m.workflow_state IN ('unknown','dead','suppressed','retry_wait') THEN m.workflow_state
 WHEN m.clicked_at IS NOT NULL THEN 'click' WHEN m.opened_at IS NOT NULL THEN 'open' WHEN m.delivered_at IS NOT NULL THEN 'delivery'
 WHEN m.provider_failure='delay' THEN 'delay' ELSE m.workflow_state END;
$$;
REVOKE ALL ON FUNCTION public.email_reporting_state(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_reporting_state(public.email_messages) TO service_role;

CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH messages AS (
 SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion
  AND workflow_state NOT IN ('cancelled','expired')),
 ranked AS (
 SELECT *,CASE WHEN reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed') THEN 0
 WHEN workflow_state IN ('pending','preparing','sending','blocked') AND target_time<=now() THEN 1
 WHEN workflow_state='accepted' THEN 2 ELSE 3 END rank FROM messages)
 SELECT coalesce(jsonb_object_agg(r.order_id,jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'message_id',r.message_id,'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),
 'scheduled_at',r.target_time,'attention_count',(SELECT count(*) FROM ranked n WHERE n.order_id=r.order_id AND rank=0),'loaded_at',now(),
 'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object('kind',message_kind,'state',reporting_state,'at',coalesce(delivered_at,accepted_at,created_at)) ORDER BY created_at DESC),'[]') FROM ranked n WHERE n.order_id=r.order_id))
),'{}'::jsonb) INTO v_summary FROM (SELECT DISTINCT ON (order_id) * FROM ranked ORDER BY order_id,rank,created_at DESC,id DESC) r;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_order_email_summary(p_order bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occ bigint;
BEGIN
 SELECT occasion INTO v_occ FROM eshop.orders WHERE id=p_order;
 IF v_occ IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
 RETURN coalesce(public.get_order_email_summaries(v_occ,ARRAY[p_order])->p_order::text,jsonb_build_object('state','unavailable','messages','[]'::jsonb,'loaded_at',now()));
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summary(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summary(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.email_report_allowed(p_org bigint,p_occasion bigint,p_user uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.get_is_admin_on_organization(p_org),false) OR
 (p_occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_org)
 AND coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false)
 AND (p_user IS NULL OR EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user)));
$$;
REVOKE ALL ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) TO authenticated,service_role;

DROP FUNCTION IF EXISTS public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz);
CREATE OR REPLACE FUNCTION public.get_email_delivery_page(p_occasion bigint,p_before bigint DEFAULT NULL,p_limit integer DEFAULT 30,p_order bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_state text DEFAULT NULL,p_organization bigint DEFAULT NULL,p_user uuid DEFAULT NULL,p_since timestamptz DEFAULT NULL,p_orders_only boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion,p_user),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_page_limit'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY id DESC),'[]') INTO v_result FROM (
 SELECT id,message_id,message_kind,order_id,(SELECT o.order_symbol FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=m.order_id AND oc.organization=m.organization AND o.occasion=m.occasion) order_symbol,created_at,accepted_at,delivered_at,bounced_at,complained_at,opened_at,clicked_at,
 public.email_reporting_state(m) state,tracking_policy,post_action_state,last_error FROM public.email_messages m
 WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion OR (p_user IS NOT NULL AND occasion IS NULL))
 AND (p_user IS NULL OR recipient_user=p_user) AND (p_since IS NULL OR created_at>=p_since) AND (p_before IS NULL OR id<p_before) AND (p_order IS NULL OR order_id=p_order)
 AND (NOT coalesce(p_orders_only,false) OR order_id IS NOT NULL)
 AND (p_kind IS NULL OR message_kind=p_kind) AND (p_state IS NULL OR public.email_reporting_state(m)=p_state)
 ORDER BY id DESC LIMIT p_limit) x;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_delivery_detail(p_message uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_id IS NULL THEN RAISE EXCEPTION 'email_detail_not_available'; END IF;
 IF NOT coalesce(public.email_report_allowed(m.organization,m.occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN jsonb_build_object('message',jsonb_build_object('id',m.message_id,'kind',m.message_kind,'state',public.email_reporting_state(m),'tracking_policy',m.tracking_policy,'opened_at',m.opened_at,'clicked_at',m.clicked_at,'post_action',m.post_action_state,'last_error',m.last_error,'provider_id',m.provider_message_id,'requested_by',m.data->>'requested_by'),
 'attempts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',attempt_id,'state',state,'at',created_at,'error',error_code,'provider_id',provider_message_id) ORDER BY created_at),'[]') FROM public.email_attempts WHERE message_id=p_message),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('type',event_type,'at',provider_time) ORDER BY provider_time),'[]') FROM (SELECT event_type,provider_time FROM public.email_delivery_events WHERE message_id=p_message ORDER BY provider_time DESC LIMIT 100) e));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_detail(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_detail(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.create_email_confirmation_receipt(p_command uuid,p_order bigint,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT message_id INTO v_message FROM public.email_messages WHERE message_kind='order_confirmation' AND data->>'command_id'=p_command::text AND order_id=p_order;
 IF v_message IS NULL THEN RETURN false; END IF;
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at) VALUES(p_hash,v_message,now()+interval '15 minutes');
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_email_confirmation_status(p_hash text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid; m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_confirmation_receipts SET reads=reads+1 WHERE token_hash=p_hash AND expires_at>now() AND reads<15 RETURNING message_id INTO v_message;
 IF v_message IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=v_message;
 RETURN CASE WHEN EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id AND e.invalid_recipient AND e.recipient=lower(m.recipient)) THEN 'invalid_email'
 WHEN m.bounced_at IS NOT NULL OR m.complained_at IS NOT NULL OR m.provider_failure IN ('reject','rendering_failure') THEN 'failed'
 WHEN m.delivered_at IS NOT NULL THEN 'delivered' WHEN m.workflow_state='accepted' THEN 'accepted' WHEN m.workflow_state IN ('unknown','dead','suppressed','expired','cancelled','retry_wait') THEN m.workflow_state ELSE 'queued' END;
END $$;
REVOKE ALL ON FUNCTION public.get_email_confirmation_status(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_confirmation_status(text) TO service_role;
CREATE OR REPLACE FUNCTION public.get_auth_email_context(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'recipient',public.get_user_delivery_email(id)) FROM public.user_info WHERE id=p_user);
END $$;
REVOKE ALL ON FUNCTION public.get_auth_email_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_email_context(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_email_delivery_overview(p_occasion bigint,p_organization bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN (SELECT jsonb_build_object('messages',count(*),'accepted',count(*) FILTER(WHERE accepted_at IS NOT NULL),
 'delivered',count(*) FILTER(WHERE delivered_at IS NOT NULL),'bounced',count(*) FILTER(WHERE bounced_at IS NOT NULL),
 'complained',count(*) FILTER(WHERE complained_at IS NOT NULL),'opened_messages',count(*) FILTER(WHERE opened_at IS NOT NULL),
 'clicked_messages',count(*) FILTER(WHERE clicked_at IS NOT NULL),'tracking_coverage',count(*) FILTER(WHERE tracking_policy<>'disabled'),
 'unknown',count(*) FILTER(WHERE workflow_state='unknown'),'dead',count(*) FILTER(WHERE workflow_state='dead'),
 'feedback_overdue',count(*) FILTER(WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=email_messages.message_id))) FROM public.email_messages WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_overview(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_overview(bigint,bigint) TO authenticated,service_role;

-- Private read boundary. RPC execution is service-only; owners may call it from
-- already authorized command facades. Invoker RLS/privileges remain in force.
CREATE OR REPLACE FUNCTION public.read_order_identity(p_order bigint, p_occasion bigint, p_organization bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
    RETURN (SELECT o.order_symbol FROM eshop.orders o
        JOIN public.occasions oc ON oc.id=o.occasion
        WHERE o.id=p_order AND o.occasion=p_occasion AND oc.organization=p_organization);
END;
$$;
ALTER FUNCTION public.read_order_identity(bigint,bigint,bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.read_order_identity(bigint,bigint,bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_order_identity(bigint,bigint,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(
  p_order jsonb,p_command_id uuid,p_client_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'order',p_order)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN
    v_result := v_begin->'response';
    IF v_result#>'{data,order}' IS NOT NULL AND v_result#>>'{data,order,order_symbol}' IS NULL THEN
      v_symbol := public.read_order_identity((v_result#>>'{data,order,id}')::bigint,
        v_occasion, (SELECT organization FROM public.occasions WHERE id=v_occasion));
      IF v_symbol IS NOT NULL THEN
        v_result := jsonb_set(v_result, '{data,order,order_symbol}', to_jsonb(v_symbol));
      END IF;
    END IF;
    RETURN v_result;
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1(p_order);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) TO anon,authenticated;

-- Temporary owner-only migration function, removed by the contract migration.
CREATE OR REPLACE FUNCTION public.backfill_order_symbols(p_ids bigint[])
RETURNS TABLE(order_id bigint, order_symbol text)
LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_id bigint; v_symbol text; v_constraint text; v_done boolean;
BEGIN
    FOREACH v_id IN ARRAY p_ids LOOP
        PERFORM 1 FROM eshop.orders o WHERE o.id=v_id AND o.order_symbol IS NULL FOR UPDATE;
        IF NOT FOUND THEN CONTINUE; END IF;
        v_done := false;
        FOR attempt IN 1..10 LOOP
            BEGIN
                v_symbol := public.generate_order_symbol();
                UPDATE eshop.orders o SET order_symbol=v_symbol WHERE o.id=v_id AND o.order_symbol IS NULL;
                v_done := true;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
                IF v_constraint <> 'orders_order_symbol_key' THEN RAISE; END IF;
                RAISE LOG 'order_symbol_backfill_collision attempt=%', attempt;
            END;
        END LOOP;
        IF NOT v_done THEN RAISE EXCEPTION 'order_symbol_backfill_exhausted'; END IF;
        order_id := v_id; order_symbol := v_symbol; RETURN NEXT;
    END LOOP;
END;
$$;
ALTER FUNCTION public.backfill_order_symbols(bigint[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.backfill_order_symbols(bigint[]) FROM PUBLIC, anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;

COMMIT;
