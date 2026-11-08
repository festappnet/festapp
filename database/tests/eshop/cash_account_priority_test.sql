-- Test: Exclude Cash Accounts from Priority Logic
-- Scenario:
-- 1. Create Unit, Occasion, Form
-- 2. Create Standard Bank Account (Priority 10)
-- 3. Create Cash Bank Account (Priority 0 - higher priority in terms of sorting)
-- 4. Verify create_ticket_order selects Standard Account (skipping Cash)
-- 5. Verify get_form_for_edit returns only Standard Account

-- Wrap in DO block to use PL/pgSQL variables and control structures
DO $$
DECLARE
    last_org_id BIGINT;
    previous_order_count BIGINT;
    last_unit_id BIGINT;
    last_occasion_id BIGINT;
    last_form_id BIGINT;
    last_form_key UUID;
    last_std_account_id BIGINT;
    last_cash_account_id BIGINT;
    last_pt_id BIGINT;
    last_product_id BIGINT;
    result_json JSONB;
    input_json JSONB;
    last_pi_id BIGINT;
    assigned_ba_id BIGINT;
    actor UUID;
BEGIN
    -- Exercise real authorization with an occasion form editor.
    PERFORM public.create_user_for_test('cash-priority-editor','cash-priority@example.invalid');
    actor:=public.get_user_id('cash-priority-editor');
    -- 1. Setup Data

    -- Create Organization
    INSERT INTO organizations (title) VALUES ('Test Org') RETURNING id INTO last_org_id;

    -- Create Unit
    INSERT INTO units (organization, title) VALUES (last_org_id, 'Test Unit') RETURNING id INTO last_unit_id;

    -- Create Occasion
    INSERT INTO occasions (organization, unit, title, is_open, start_time, end_time, link) VALUES ((SELECT organization FROM public.units WHERE id=last_unit_id), last_unit_id, 'Test Occasion', true, now(), now() + interval '1 year', 'test-occasion-link') RETURNING id INTO last_occasion_id;

    UPDATE public.user_info SET organization=last_org_id WHERE id=actor;
    INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_order_view)
    VALUES(last_occasion_id,actor,true,true,true);
    PERFORM set_config('request.jwt.claim.sub',actor::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);

    -- Create Form
    INSERT INTO forms (occasion, title, is_open, link)
    VALUES (last_occasion_id, 'Test Form', true, 'test-form-link') RETURNING id, key INTO last_form_id, last_form_key;
    PERFORM public.reserve_public_link_internal('form',last_form_id,'test-form-link',true);

    -- Create Standard Bank Account (FIO)
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('Standard Account', '123456/0100', 'FIO', ARRAY['CZK']) RETURNING id INTO last_std_account_id;

    -- Create Cash Account (CASH)
    INSERT INTO eshop.bank_accounts (title, account_number, type, supported_currencies)
    VALUES ('Cash Account', '', 'CASH', ARRAY['CZK']) RETURNING id INTO last_cash_account_id;

    -- Link Bank Accounts
    -- Standard: Low Priority (10)
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
    VALUES (last_unit_id, last_std_account_id, 10);

    -- Cash: High Priority (0) (lower number = higher priority)
    INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
    VALUES (last_unit_id, last_cash_account_id, 0);

    -- Create Product
    INSERT INTO eshop.product_types (occasion, title, type) VALUES (last_occasion_id, 'General', 'spot') RETURNING id INTO last_pt_id;

    INSERT INTO eshop.products (occasion, product_type, title, price, currency_code)
    VALUES (last_occasion_id, last_pt_id, 'Test Product', 100, 'CZK') RETURNING id INTO last_product_id;
    INSERT INTO public.form_fields(form,product_type,type) VALUES(last_form_id,last_pt_id,'product_type');


    -- 2. Test get_form_for_edit (Should only see Standard Account)
    -- Act
    SELECT get_form_for_edit('test-form-link') INTO result_json;

    -- Assert
    -- available_bank_accounts should have length 1
    PERFORM assert_equals(
        jsonb_array_length(result_json->'data'->'available_bank_accounts')::text,
        '1',
        'get_form_for_edit should return exactly 1 bank account (excluding CASH)'
    );

    -- Assert that the returned account is the Standard one
    PERFORM assert_equals(
        (result_json->'data'->'available_bank_accounts'->0->>'id')::bigint,
        last_std_account_id,
        'The available account must be the Standard Account'
    );


    -- 3. Test create_ticket_order (Should pick Standard Account despite lower priority)
    -- Prepare Input
    input_json := jsonb_build_object(
        'form', last_form_key,
        'email', 'test@test.com',
        'ticket', jsonb_build_array(
            jsonb_build_object(
                'fields', jsonb_build_array(
                     jsonb_build_object('product_type', last_product_id)
                )
            )
        )
    );

    -- Act
    SELECT create_ticket_order(input_json) INTO result_json;

    -- Assert
    PERFORM assert_equals(
        (result_json->'code')::int,
        200,
        'Create ticket order should succeed'
    );

    PERFORM assert_equals(
        (result_json->'order'->'payment_info'->>'currency_code')::text,
        'CZK',
        'Currency should be CZK'
    );

    -- Crucial Assertion: Check which bank account was used
    SELECT payment_info INTO last_pi_id FROM eshop.orders WHERE id = (result_json->'order'->>'id')::bigint;
    SELECT bank_account INTO assigned_ba_id FROM eshop.payment_info WHERE id = last_pi_id;

    PERFORM assert_equals(
        assigned_ba_id,
        last_std_account_id,
        'Order should be assigned to Standard Bank Account, NOT Cash Account'
    );

    IF assigned_ba_id = last_cash_account_id THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Order MUST NOT be assigned to Cash Account';
    END IF;


    -- 4. Test ONLY Cash Account Scenario (Should Fail)
    -- Setup: Remove Standard Account linking, leave only Cash Account
    DELETE FROM eshop.unit_bank_accounts WHERE unit = last_unit_id AND bank_account = last_std_account_id;
    SELECT count(*) INTO previous_order_count FROM eshop.orders WHERE form=last_form_id;

    -- Act & Assert
    -- Act
    SELECT create_ticket_order(input_json) INTO result_json;

    -- Assert
    PERFORM assert_equals(
        (result_json->'code')::int,
        1013,
        'Bank method without an eligible recipient is rejected by payment availability'
    );

    PERFORM assert_equals(result_json->>'message','PAYMENT_METHOD_UNAVAILABLE','Cash account cannot satisfy bank availability');
    PERFORM assert_equals((SELECT count(*) FROM eshop.orders WHERE form=last_form_id),previous_order_count,'Rejected bank checkout creates no order');

    -- Re-Raise Exception to rollback transaction? No, run_db_tests execution wraps it in transaction and rollsback anyway.
    -- But since we are in a DO block, we don't automatically trigger "ROLLBACK" unless we fail.
    -- The outer JS runner does ROLLBACK.

END $$;
