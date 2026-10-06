BEGIN;

-- 1. Setup Data
INSERT INTO organizations (id, title) VALUES (998, 'Test Org Refactor');
INSERT INTO units (id, organization, title) VALUES (998, 998, 'Test Unit Refactor');
INSERT INTO occasions (id, unit, title, link, start_time, end_time) VALUES (124, 998, 'Test Occasion Refactor', 'refactor-link', now(), now() + interval '1 day');

-- Create Order 1 (Created state)
INSERT INTO eshop.orders (order_sequence, order_symbol, id, occasion, state, price, currency_code, created_at)
VALUES (public.next_order_sequence(124), public.generate_order_symbol(), 6001, 124, 'created', 100.0, 'CZK', now());

-- Create Order 2 (Ordered state)
INSERT INTO eshop.orders (order_sequence, order_symbol, id, occasion, state, price, currency_code, created_at)
VALUES (public.next_order_sequence(124), public.generate_order_symbol(), 6002, 124, 'ordered', 100.0, 'CZK', now());

-- Create Tickets for Order 2
INSERT INTO eshop.tickets (id, state, created_at, occasion) VALUES (7001, 'ordered', now(), 124);
INSERT INTO eshop.order_product_ticket ("order", ticket, product) VALUES (6002, 7001, null); -- simplified join

-- 2. Call Original Function on 'created' order
SELECT public.update_order_and_tickets_to_paid(6001);

-- Verify
DO $$
DECLARE
    v_state text;
BEGIN
    SELECT state INTO v_state FROM eshop.orders WHERE id = 6001;
    IF v_state != 'paid' THEN
        RAISE EXCEPTION 'Order 6001 (created) did not transition to paid. State: %', v_state;
    END IF;
END $$;

-- 3. Call Original Function on 'ordered' order with tickets
SELECT public.update_order_and_tickets_to_paid(6002);

-- Verify
DO $$
DECLARE
    v_order_state text;
    v_ticket_state text;
BEGIN
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = 6002;
    IF v_order_state != 'paid' THEN
        RAISE EXCEPTION 'Order 6002 (ordered) did not transition to paid. State: %', v_order_state;
    END IF;

    SELECT state INTO v_ticket_state FROM eshop.tickets WHERE id = 7001;
    IF v_ticket_state != 'paid' THEN
        RAISE EXCEPTION 'Ticket 7001 did not transition to paid. State: %', v_ticket_state;
    END IF;

    RAISE NOTICE 'Original function regression test passed.';
END $$;

ROLLBACK;
