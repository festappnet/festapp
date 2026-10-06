-- Test: create_ticket_order
-- Goal: Verify order creation flow, including price calculation and stock check.

DO $$
DECLARE
    v_unit_id bigint;
    v_occasion_id bigint;
    v_form_id bigint;
    v_form_key uuid;
    v_product_type_id bigint;
    v_product_id bigint;
    v_spot_id bigint;
    v_acc_id bigint;
    v_secret_id bigint;
    v_input_data jsonb;
    v_result jsonb;
    v_user_email text := 'test@example.com';
    v_user_id uuid;
BEGIN
    -- 1. Setup Full Environment (Self-Contained)

    -- Create User Context (Required for some checks, though usually anonymous is fine for orders)
    SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    -- If no user, mock one? create_ticket_order usually works anonymously.
    -- set_config('request.jwt.claim.sub', ...); -- Not strictly needed for anonymous order.

    -- Create Org & Unit
    INSERT INTO public.organizations (title) VALUES ('Test Org Eshop') RETURNING id INTO v_unit_id; -- Reuse variable for linking, actually separate IDs
    INSERT INTO public.units (title, organization) VALUES ('Test Unit Eshop', v_unit_id) RETURNING id INTO v_unit_id;

    -- Create Bank Account (CZK)
    INSERT INTO eshop.secrets (secret) VALUES ('test_secret_eshop') RETURNING id INTO v_secret_id;
    INSERT INTO eshop.bank_accounts (title, supported_currencies, secret, type)
    VALUES ('Test Bank CZK', ARRAY['CZK'], v_secret_id, 'FIO') RETURNING id INTO v_acc_id;

    -- Link Bank Account to Unit
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (v_unit_id, v_acc_id, 1);

    -- Create Occasion
    INSERT INTO public.occasions (title, unit, link, start_time, end_time)
    VALUES ('Test Occasion Eshop', v_unit_id, 'test-occ-eshop-' || floor(random()*100000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    -- Create Form (Open)
    INSERT INTO public.forms (title, occasion, is_open)
    VALUES ('Test Form Eshop', v_occasion_id, true)
    RETURNING id, key INTO v_form_id, v_form_key;

    -- Create Product Type (Spot)
    INSERT INTO eshop.product_types (title, occasion, type)
    VALUES ('Test PT Spot', v_occasion_id, 'spot')
    RETURNING id INTO v_product_type_id;

    -- Create Product (CZK)
    INSERT INTO eshop.products (title, product_type, currency_code, price, is_hidden, occasion)
    VALUES ('Test Product CZK', v_product_type_id, 'CZK', 100, false, v_occasion_id)
    RETURNING id INTO v_product_id;

    -- Link Product to Form
    INSERT INTO public.form_fields (form, product_type) VALUES (v_form_id, v_product_type_id);

    -- Create Spot
    INSERT INTO eshop.spots (title, product, occasion, secret)
    VALUES ('Test Spot', v_product_id, v_occasion_id, gen_random_uuid())
    RETURNING id INTO v_spot_id;

    -- 2. Construct Order Input
    -- { form: key, email: ..., ticket: [ { spot: spot_id } ] }
    v_input_data := jsonb_build_object(
        'form', v_form_key,
        'email', v_user_email,
        'secret', (SELECT secret FROM eshop.spots WHERE id = v_spot_id),
        'ticket', jsonb_build_array(
            jsonb_build_object('spot', v_spot_id)
        )
    );

    -- 3. Execute Order Creation
    SELECT create_ticket_order(v_input_data) INTO v_result;

    -- 4. Verify
    -- Expect 200 (Success)
    PERFORM assert_eq((v_result->>'code')::int, 200, 'Order creation should succeed (200). Got: ' || COALESCE(v_result->>'code', 'NULL') || ' Msg: ' || COALESCE(v_result->>'message', ''));

    PERFORM assert_not_null(v_result->'order'->>'id', 'Order ID must be returned');
    PERFORM assert_true(v_result#>>'{order,order_symbol}' ~ '^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$', 'Canonical order symbol returned');
    PERFORM assert_eq(v_result#>>'{order,order_symbol}',
        (SELECT order_symbol FROM eshop.orders WHERE id=(v_result#>>'{order,id}')::bigint), 'Response uses persisted symbol');
    PERFORM assert_eq(public.get_order_details_for_email((v_result#>>'{order,id}')::bigint)#>>'{data,order,order_symbol}',
        v_result#>>'{order,order_symbol}', 'Email row JSON contains identity');

    -- Verify Status 'ordered'
    PERFORM assert_eq(
        (SELECT state FROM eshop.orders WHERE id = (v_result->'order'->>'id')::bigint)::text,
        'ordered',
        'Order state should be ordered'
    );
END;
$$ LANGUAGE plpgsql;
