-- Test: Update Ticket Products Logic (update_ticket_products_wsv2)
-- Setup Data

-- Create Org/Unit
INSERT INTO organizations (id, title) VALUES (777, 'UpdateTest Org');
INSERT INTO units (id, organization, title) VALUES (777, 777, 'UpdateTest Unit');

-- Mock Auth User
DO $$
BEGIN
    INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-000000000007', 'tester@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES ('00000000-0000-0000-0000-000000000007', 'tester@example.com');
    PERFORM set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', true);
END $$;

-- Setup Bank Account
INSERT INTO eshop.bank_accounts (id, title, account_number, type, supported_currencies)
VALUES (7000, 'Test Bank', '1234/5678', 'FIO', ARRAY['CZK']);

-- Setup Occasion
INSERT INTO occasions (id, unit, title, link, start_time, end_time)
VALUES (777, 777, 'UpdateTest Occasion', 'update-test', now(), now() + interval '1 day');

-- Setup Product Types
INSERT INTO eshop.product_types (id, title, occasion) VALUES (701, 'Test Type', 777);

-- Setup Products (Catalog)
INSERT INTO eshop.products (id, product_type, price, currency_code, title, maximum, is_hidden, occasion)
VALUES
(8001, 701, 100.0, 'CZK', 'Product A', 10, false, 777),
(8002, 701, 200.0, 'CZK', 'Product B', 10, false, 777);

-- Grant Access
INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (777, '00000000-0000-0000-0000-000000000007', true);
INSERT INTO public.occasion_users (occasion, "user", is_manager, is_editor, is_editor_order)
VALUES (777, '00000000-0000-0000-0000-000000000007', true, true, true);

-- Helper Block
DO $$
DECLARE
    v_order_id bigint;
    v_payment_info_id bigint;
    v_ticket_id bigint;
    v_ticket_type_id bigint;
    v_price numeric;
    v_paid numeric;
BEGIN
    -- 1. Create Initial Order
    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, created_at, paid)
    VALUES (777777, 0.0, 'CZK', 7000, now(), 0.0) RETURNING id INTO v_payment_info_id;

    INSERT INTO eshop.orders (order_sequence, order_symbol, occasion, payment_info, state, price, currency_code, created_at)
    VALUES (public.next_order_sequence(777), public.generate_order_symbol(), 777, v_payment_info_id, 'created', 0.0, 'CZK', now()) RETURNING id INTO v_order_id;

    -- Create a Ticket (No order_id in table, linked via order_product_ticket? Or maybe schema in test was wrong?
    -- Checked function: uses "SELECT form FROM eshop.orders WHERE id = (SELECT order FROM eshop.order_product_ticket WHERE ticket = v_ticket_id LIMIT 1)"
    -- So yes, they are linked via order_product_ticket.
    -- BUT wait, the function also expects the ticket to ALREADY be linked to an order?
    -- Function does: "v_order_id := (SELECT order_id FROM eshop.tickets WHERE id = v_ticket_id);" ??
    -- Let's check the function code from view_file output.

    -- Create a Ticket (in DB)
    INSERT INTO eshop.tickets (occasion, state, ticket_symbol)
    VALUES (777, 'ordered', 'T-TEST') RETURNING id INTO v_ticket_id;

    -- Link it via link table
    INSERT INTO eshop.order_product_ticket ("order", ticket, product)
    VALUES (v_order_id, v_ticket_id, NULL);

    -- CRITICAL: Initialize orders.data so the function can find the ticket in JSON
    UPDATE eshop.orders
    SET data = jsonb_build_object(
        'tickets', jsonb_build_array(
            jsonb_build_object(
                'id', v_ticket_id,
                'products', '[]'::jsonb
            )
        )
    )
    WHERE id = v_order_id;

    RAISE NOTICE 'Setup Complete. Order: %, Ticket: %', v_order_id, v_ticket_id;

    -- SCENARIO 1: ADD PRODUCTS (Logic: 0 -> 300)
    -- Add Product A (100) and Product B (200)
    PERFORM public.update_ticket_products_wsv2(
        v_ticket_id,
        '[{"id": 8001, "price": 100.0}, {"id": 8002, "price": 200.0}]'::jsonb
    );

    -- Verify Price
    SELECT price INTO v_price FROM eshop.orders WHERE id = v_order_id;
    SELECT amount INTO v_paid FROM eshop.payment_info WHERE id = v_payment_info_id;

    IF v_price != 300.0 THEN
        RAISE EXCEPTION 'Scenario 1 Failed: Expected Price 300.0, got %', v_price;
    END IF;
    IF v_paid != 300.0 THEN
        RAISE EXCEPTION 'Scenario 1 Failed: Expected Payment Amount 300.0, got %', v_paid;
    END IF;
    RAISE NOTICE 'Scenario 1 (Add Products) PASSED. Price: %', v_price;


    -- SCENARIO 2: UPDATE PRICE (Logic: 300 -> 350)
    -- Change Product A price to 150 (Total 150 + 200 = 350)
    PERFORM public.update_ticket_products_wsv2(
        v_ticket_id,
        '[{"id": 8001, "price": 150.0}, {"id": 8002, "price": 200.0}]'::jsonb
    );

    -- Verify
    SELECT price INTO v_price FROM eshop.orders WHERE id = v_order_id;
    IF v_price != 350.0 THEN
        RAISE EXCEPTION 'Scenario 2 Failed: Expected Price 350.0, got %', v_price;
    END IF;
    RAISE NOTICE 'Scenario 2 (Update Price) PASSED. Price: %', v_price;


    -- SCENARIO 3: REMOVE PRODUCT (Logic: 350 -> 200)
    -- Remove Product A, keep Product B
    PERFORM public.update_ticket_products_wsv2(
        v_ticket_id,
        '[{"id": 8002, "price": 200.0}]'::jsonb
    );

    -- Verify
    SELECT price INTO v_price FROM eshop.orders WHERE id = v_order_id;
    IF v_price != 200.0 THEN
        RAISE EXCEPTION 'Scenario 3 Failed: Expected Price 200.0, got %', v_price;
    END IF;
    RAISE NOTICE 'Scenario 3 (Remove Product) PASSED. Price: %', v_price;


    -- SCENARIO 4: IDEMPOTENCY (Sequential)
    -- Call Update again with SAME data (Product B: 200)
    -- Expectation: Diff is 0, Price stays 200.
    PERFORM public.update_ticket_products_wsv2(
        v_ticket_id,
        '[{"id": 8002, "price": 200.0}]'::jsonb
    );

    -- Verify
    SELECT price INTO v_price FROM eshop.orders WHERE id = v_order_id;
    IF v_price != 200.0 THEN
        RAISE EXCEPTION 'Scenario 4 Failed: Expected Price 200.0, got %', v_price;
    END IF;
    RAISE NOTICE 'Scenario 4 (Sequential Idempotency) PASSED. Price: %', v_price;

END $$;

ROLLBACK;
