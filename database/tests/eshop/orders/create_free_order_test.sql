BEGIN;

-- 1. Setup Data
INSERT INTO organizations (id, title) VALUES (997, 'Test Org Free');
INSERT INTO units (id, organization, title) VALUES (997, 997, 'Test Unit Free');
INSERT INTO occasions (organization, id, unit, title, link, start_time, end_time) VALUES ((SELECT organization FROM public.units WHERE id=997), 125, 997, 'Test Occasion Free', 'free-link', now(), now() + interval '1 day');
INSERT INTO public.forms (id, key, occasion, data, is_open) VALUES (800, '00000000-0000-0000-0000-000000000800', 125, '{}', true);

-- Need a Bank Account for VS generation (even if free)
INSERT INTO eshop.bank_accounts (id, title, account_number, type, supported_currencies) VALUES (2000, 'Test Bank', '123/0100', 'FIO', ARRAY['CZK']);
INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority) VALUES (997, 2000, 1);

-- Need a Product Type (spot) and Product
INSERT INTO eshop.product_types (id, occasion, title, type) VALUES (900, 125, 'Free Ticket Type', 'spot');
INSERT INTO eshop.products (id, product_type, title, price, currency_code, is_hidden) VALUES (901, 900, 'Free Ticket', 0, 'CZK', false);

INSERT INTO public.form_fields(form,product_type,type) VALUES(800,900,'product_type');

-- 2. Call create_ticket_order with Price 0
-- We simulate a JSON payload for a free ticket
DO $$
DECLARE
    v_input jsonb;
    v_result jsonb;
    v_order_id bigint;
    v_state text;
BEGIN
    v_input := jsonb_build_object(
        'form', '00000000-0000-0000-0000-000000000800',
        'email', 'free@example.com',
        'ticket', jsonb_build_array(
            jsonb_build_object(
                'fields', jsonb_build_array(
                    jsonb_build_object('note', 'Free Ticket'),
                    jsonb_build_object('product_type', 901)
                )
            )
        )
    );

    -- Call function
    SELECT create_ticket_order(v_input) INTO v_result;
    
    RAISE NOTICE 'Result: %', v_result;

    -- Extract Order ID
    v_order_id := (v_result->'order'->>'id')::bigint;

    IF v_order_id IS NULL THEN
        RAISE EXCEPTION 'Order Creation Failed: %', v_result;
    END IF;

    -- Verify State is PAID
    SELECT state INTO v_state FROM eshop.orders WHERE id = v_order_id;
    
    IF v_state IS NULL OR v_state != 'paid' THEN
        RAISE EXCEPTION 'Free order % did not auto-transition to paid. State: %', v_order_id, v_state;
    END IF;

    RAISE NOTICE 'Free order test passed. Order % is %.', v_order_id, v_state;
END $$;

ROLLBACK;
