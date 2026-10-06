
BEGIN;
    -- Import assertions
    -- \i scripts/tests/helpers/assertions.sql
    -- Assertions are loaded by the test runner

    -- Test 1: generate_request_secret
    DO $$
    DECLARE
        v_secret text;
        v_count int;
    BEGIN
        v_secret := public.generate_request_secret(300);

        PERFORM assert_not_null(v_secret, 'Generated secret should not be null');

        SELECT count(*) INTO v_count FROM public.request_secrets WHERE secret = v_secret;
        PERFORM assert_eq(v_count, 1, 'Secret should be present in request_secrets table');
    END $$;

    -- Test 2: get_external_services
    DO $$
    DECLARE
        v_org_id bigint;
        v_unit_id bigint;
        v_occasion_id bigint;
        v_order_id bigint;
        v_service_id bigint;
        v_rec record;
        v_found boolean := false;
    BEGIN
        -- Setup
        INSERT INTO public.organizations (title) VALUES ('RPC Test Org') RETURNING id INTO v_org_id;
        INSERT INTO public.units (organization, title) VALUES (v_org_id, 'RPC Test Unit') RETURNING id INTO v_unit_id;
        INSERT INTO public.occasions (organization, unit, title, link, start_time, end_time)
        VALUES (v_org_id, v_unit_id, 'RPC Test Occasion', 'rpc-test-' || gen_random_uuid(), now(), now() + interval '1 day')
        RETURNING id INTO v_occasion_id;

        -- Create dummy Order
        INSERT INTO eshop.orders (order_symbol, occasion, created_at, updated_at)
        VALUES (public.generate_order_symbol(), v_occasion_id, now(), now())
        RETURNING id INTO v_order_id;

        -- Insert External Service
        INSERT INTO eshop.external_services (type, data, unit)
        VALUES ('TEST_SERVICE', '{"key": "value"}'::jsonb, v_unit_id)
        RETURNING id INTO v_service_id;

        -- Execution
        FOR v_rec IN SELECT * FROM public.get_external_services(v_order_id) LOOP
            v_found := true;
            PERFORM assert_eq(v_rec.id, v_service_id, 'Service ID mismatch');
            PERFORM assert_eq(v_rec.type, 'TEST_SERVICE', 'Service Type mismatch');
            PERFORM assert_eq(v_rec.unit, v_unit_id, 'Unit ID mismatch');
        END LOOP;

        PERFORM assert_true(v_found, 'Should have found at least one external service');

    EXCEPTION WHEN OTHERS THEN
        -- Verify cleaner rollback or helpful error
        RAISE NOTICE 'Test failed with %', SQLERRM;
        RAISE;
    END $$;
