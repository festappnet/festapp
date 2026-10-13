-- Verify: insert_manual_transaction creates CASH account lazily, inserts manual
-- transaction, links it to payment_info, and triggers order → 'paid' state.

DO $$
DECLARE
    v_org_id bigint;
    v_unit_id bigint;
    v_user_id uuid := gen_random_uuid();
    v_bank_id bigint;
    v_pi_id bigint;
    v_occasion_id bigint;
    v_order_id bigint;
    v_vs text := floor(random()*1000000000)::text;
    v_acc_id int;
    v_paid_amount numeric;
    v_order_state text;
    v_trans_record eshop.transactions%ROWTYPE;
BEGIN
    -- 1. Setup: org, unit, mock user (manager)
    INSERT INTO public.organizations (title) VALUES ('Test Org IMT') RETURNING id INTO v_org_id;
    INSERT INTO public.units (organization, title) VALUES (v_org_id, 'Test Unit IMT') RETURNING id INTO v_unit_id;

    INSERT INTO auth.users (id, email) VALUES (v_user_id, 'test_imt_' || v_user_id || '@example.com');
    INSERT INTO public.user_info (id, email_readonly) VALUES (v_user_id, 'test_imt_' || v_user_id || '@example.com');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);
    INSERT INTO public.unit_users (unit, "user", is_manager) VALUES (v_unit_id, v_user_id, true);

    -- 2. Setup: bank account + payment_info + order
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('FIO Account IMT', 'TEST-' || floor(random()*1000000)::text || '/2010', 'FIO', ARRAY['CZK'])
    RETURNING id INTO v_bank_id;

    INSERT INTO eshop.payment_info (variable_symbol, amount, currency_code, bank_account, paid)
    VALUES (v_vs::bigint, 200.0, 'CZK', v_bank_id, 0)
    RETURNING id INTO v_pi_id;

    INSERT INTO public.occasions (unit, title, link, start_time, end_time)
    VALUES (v_unit_id, 'Test Occasion IMT', 'test-link-imt-' || floor(random()*1000000)::text, now(), now() + interval '1 day')
    RETURNING id INTO v_occasion_id;

    INSERT INTO eshop.orders (order_sequence, order_symbol, occasion, payment_info, state, price, currency_code)
    VALUES (public.next_order_sequence(v_occasion_id), public.generate_order_symbol(), v_occasion_id, v_pi_id, 'created', 200.0, 'CZK')
    RETURNING id INTO v_order_id;

    -- 3. Call the RPC (Pay 200 CZK CASH manually — full payment)
    PERFORM public.insert_manual_transaction(
        200.0::double precision,
        'CZK',
        v_unit_id::integer,
        v_vs,
        '2024-01-01 12:00:00',
        'Test Note'
    );

    -- 4. Verify: CASH account was lazy-created on the unit
    SELECT ba.id INTO v_acc_id
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    WHERE uba.unit = v_unit_id
    AND 'CZK' = ANY(ba.supported_currencies)
    AND ba.type = 'CASH';

    IF v_acc_id IS NULL THEN
        RAISE EXCEPTION 'CASH account was NOT lazy-created';
    END IF;

    -- Verify: transaction inserted
    SELECT * INTO v_trans_record
    FROM eshop.transactions
    WHERE bank_account_id = v_acc_id
    AND amount = 200.0
    AND currency = 'CZK'
    AND vs = v_vs
    AND transaction_type = 'manual'
    LIMIT 1;

    IF v_trans_record IS NULL THEN
        RAISE EXCEPTION 'Transaction was NOT inserted correctly';
    END IF;

    -- Verify: NOTE (mapped to message_for_recipient)
    IF v_trans_record.message_for_recipient IS DISTINCT FROM 'Test Note' THEN
        RAISE EXCEPTION 'Transaction NOTE mismatch. Expected "Test Note", got %', v_trans_record.message_for_recipient;
    END IF;

    -- Verify: payment_info.paid updated to 200
    SELECT paid INTO v_paid_amount FROM eshop.payment_info WHERE id = v_pi_id;
    IF v_paid_amount IS NULL OR v_paid_amount != 200.0 THEN
        RAISE EXCEPTION 'Payment Info was NOT updated. Expected 200.0, got %', v_paid_amount;
    END IF;

    -- Verify: order state transitioned to 'paid'
    SELECT state INTO v_order_state FROM eshop.orders WHERE id = v_order_id;
    IF v_order_state != 'paid' THEN
        RAISE EXCEPTION 'Order state was NOT updated to paid. Current state: %', v_order_state;
    END IF;

    RAISE NOTICE 'Test Passed: CASH account created, transaction inserted with NOTE, payment info updated, and order marked PAID.';
END $$;

-- Additional cash is a new payment fact, including legitimate excess after
-- tickets were sent. It must not replay the paid/issued transition or invoice.
DO $$
DECLARE
 actor uuid:=gen_random_uuid();org bigint;un bigint;oc bigint;bank bigint;pi bigint;ord bigint;tid bigint;
 original_tx bigint;original_fact jsonb;ticket_snapshot jsonb;pdf_snapshot jsonb;invoice_snapshot jsonb;
 email_count bigint;history_count bigint;payment_version bigint;manual_tx eshop.transactions;role_rejected boolean:=false;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 INSERT INTO public.organizations(title) VALUES('Sent additional payment regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Additional cash unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time)
 VALUES('Additional cash event',gen_random_uuid()::text,org,un,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id,email) VALUES(actor,actor::text||'@example.invalid');
 INSERT INTO public.user_info(id,email_readonly,organization) VALUES(actor,actor::text||'@example.invalid',org);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
 VALUES('Existing bank payment','FIO','SYNTHETIC',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,paid,currency_code,data)
 VALUES(bank,1900100,1900,1900,'CZK','{"fakturoid_invoice_id":123,"fakturoid_proforma_id":456}') RETURNING id INTO pi;
 INSERT INTO eshop.orders(occasion,payment_info,state,price,currency_code,order_sequence,order_symbol,data)
 VALUES(oc,pi,'sent',1900,'CZK',public.next_order_sequence(oc),public.generate_order_symbol(),'{"name":"Synthetic buyer"}') RETURNING id INTO ord;
 INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data)
 VALUES(oc,'sent','SYNTHETIC-'||gen_random_uuid()::text,'{"fields":[]}') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(ord,tid);
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,vs,ingest_source)
 VALUES(bank,pi,1900,'CZK',now(),'1900100','legacy') RETURNING id INTO original_tx;
 SELECT to_jsonb(t) INTO original_fact FROM eshop.transactions t WHERE id=original_tx;
 SELECT to_jsonb(t) INTO ticket_snapshot FROM eshop.tickets t WHERE id=tid;
 pdf_snapshot:=public.get_ticket_details_for_generating(tid);
 ASSERT pdf_snapshot#>>'{ticket,id}'=tid::text,'Initial sent ticket PDF details missing';
 SELECT data INTO invoice_snapshot FROM eshop.payment_info WHERE id=pi;
 SELECT email_payment_version INTO payment_version FROM eshop.orders WHERE id=ord;
 SELECT count(*) INTO email_count FROM public.email_messages WHERE order_id=ord;
 SELECT count(*) INTO history_count FROM eshop.orders_history WHERE "order"=ord;
 -- Bank/cash permission remains the actual unit-manager boundary.
 UPDATE public.unit_users SET is_manager=false,is_editor=true WHERE unit=un AND "user"=actor;
 BEGIN
  PERFORM public.insert_manual_transaction(100::double precision,'CZK',un::integer,'1900100',now()::text,'Additional cash',pi::integer);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'User is not manager.' THEN RAISE;END IF;role_rejected:=true;
 END;
 ASSERT role_rejected,'Unit editor bypassed cash manager guard';
 ASSERT (SELECT paid FROM eshop.payment_info WHERE id=pi)=1900,'Rejected cash altered payment';
 UPDATE public.unit_users SET is_manager=true,is_editor=false WHERE unit=un AND "user"=actor;
 -- Invoke exactly the canonical RPC used by DbOrders.insertManualTransaction.
 PERFORM public.insert_manual_transaction(100::double precision,'CZK',un::integer,'1900100',now()::text,'Additional cash',pi::integer);
 SELECT * INTO STRICT manual_tx FROM eshop.transactions WHERE payment_info=pi AND transaction_type='manual';
 ASSERT manual_tx.amount=100 AND manual_tx.ingest_source='manual' AND manual_tx.created_by=actor,'Additional financial fact wrong';
 ASSERT manual_tx.message_for_recipient='Additional cash','Cash note missing';
 ASSERT (SELECT type FROM eshop.bank_accounts WHERE id=manual_tx.bank_account_id)='CASH','Cash fact used an imported bank account';
 ASSERT (SELECT paid FROM eshop.payment_info WHERE id=pi)=2000,'Additional cash was capped at order price';
 ASSERT (SELECT amount FROM eshop.payment_info WHERE id=pi)=1900,'Payment obligation changed';
 ASSERT (SELECT price FROM eshop.orders WHERE id=ord)=1900,'Order price changed';
 ASSERT (SELECT state FROM eshop.orders WHERE id=ord)='sent','Issued order reverted to paid';
 ASSERT (SELECT email_payment_version FROM eshop.orders WHERE id=ord)=payment_version,'Payment transition version changed';
 ASSERT (SELECT to_jsonb(t) FROM eshop.tickets t WHERE id=tid)=ticket_snapshot,'Issued ticket/symbol/state/data changed';
 ASSERT public.get_ticket_details_for_generating(tid)=pdf_snapshot,'Issued PDF projection changed';
 ASSERT (SELECT data FROM eshop.payment_info WHERE id=pi)=invoice_snapshot,'Invoice metadata changed';
 ASSERT (SELECT to_jsonb(t) FROM eshop.transactions t WHERE id=original_tx)=original_fact,'Original bank fact rewritten';
 ASSERT (SELECT count(*) FROM public.email_messages WHERE order_id=ord)=email_count,'Additional payment duplicated ticket/invoice email';
 ASSERT (SELECT count(*) FROM eshop.orders_history WHERE "order"=ord)=history_count,'Additional payment replayed order transition';
 ASSERT EXISTS(SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_id=manual_tx.id AND method='manual_insert' AND actor_id=actor AND actor_kind='user'),'Cash pairing audit missing';
END $$;
