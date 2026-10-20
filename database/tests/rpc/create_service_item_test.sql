BEGIN;

-- Regression tests for create_service_item.
--
-- Primary guard: occasions.services stored as JSON `null` (NOT SQL NULL) used
-- to make jsonb_set raise 22023 "cannot set path in scalar", because
-- COALESCE(services, '{}') only substitutes SQL NULL. The fix guards with
-- jsonb_typeof(...) = 'object'/'array'. This test locks the behaviour in.

DO $$
DECLARE
    v_user_id uuid;
    v_oc      bigint;
    v_result  jsonb;
    v_services jsonb;
    v_rejected boolean;
BEGIN
    -- Impersonate a real user so auth.uid() (used by the manager gate) resolves.
    PERFORM public.create_user_for_test('service-item-manager','service-item-manager@example.invalid');
    v_user_id:=public.get_user_id('service-item-manager');
    PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

    -- A fresh occasion whose services is JSON `null` — the exact state that
    -- triggered the bug on the live DB (occasions id 5 and 6).
    INSERT INTO public.occasions (title, link, start_time, end_time, services)
    VALUES ('Test Occasion Service Item',
            'test-svc-' || gen_random_uuid(),
            now(), now() + interval '1 day',
            'null'::jsonb)
    RETURNING id INTO v_oc;

    -- Make the caller a manager (create_service_item returns 403 otherwise).
    INSERT INTO public.occasion_users (occasion, "user", is_manager)
    VALUES (v_oc, v_user_id, true);

    -- 1. JSON-null services: create must succeed (previously errored 22023).
    v_result := public.create_service_item(v_oc, 'accommodation', 'A1', 'Hotel', 5);
    PERFORM assert_eq(v_result->>'code', '200',
        'create on JSON-null services should return 200');

    SELECT services INTO v_services FROM public.occasions WHERE id = v_oc;
    PERFORM assert_eq(jsonb_typeof(v_services), 'object',
        'services should have become a JSON object');
    PERFORM assert_eq(jsonb_typeof(v_services->'accommodation'), 'array',
        'accommodation entry should be a JSON array');
    PERFORM assert_jsonb_contains(v_services->'accommodation',
        '[{"code":"A1","title":"Hotel","reference":5}]'::jsonb,
        'created item should be persisted');

    -- 2. A second item is appended, the first is kept.
    v_result := public.create_service_item(v_oc, 'accommodation', 'A2', 'Hostel', 6);
    PERFORM assert_eq(v_result->>'code', '200', 'second create should return 200');
    SELECT services INTO v_services FROM public.occasions WHERE id = v_oc;
    PERFORM assert_eq(jsonb_array_length(v_services->'accommodation'), 2,
        'both accommodation items should be present');

    -- 3. Duplicate code within the same type is rejected and nothing is added.
    v_result := public.create_service_item(v_oc, 'accommodation', 'A1', 'Dup', 7);
    PERFORM assert_eq(v_result->>'code', '400', 'duplicate code should return 400');
    SELECT services INTO v_services FROM public.occasions WHERE id = v_oc;
    PERFORM assert_eq(jsonb_array_length(v_services->'accommodation'), 2,
        'duplicate must not be added');

    -- 4. A different service type on the same occasion coexists.
    v_result := public.create_service_item(v_oc, 'food', 'F1', 'Lunch', 9);
    PERFORM assert_eq(v_result->>'code', '200', 'food create should return 200');
    SELECT services INTO v_services FROM public.occasions WHERE id = v_oc;
    PERFORM assert_eq(jsonb_array_length(v_services->'accommodation'), 2,
        'accommodation array should be untouched by food create');
    PERFORM assert_eq(jsonb_array_length(v_services->'food'), 1,
        'food array should hold the new item');

    -- 5. The canonical command boundary rejects non-manager callers before
    -- entering the legacy JSON-returning domain handler.
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    v_rejected := false;
    BEGIN
        PERFORM public.create_service_item(
            v_oc, 'accommodation', 'A9', 'NoRights', 8);
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := SQLERRM = 'occasion manager required';
    END;
    PERFORM assert_eq(v_rejected, true, 'non-manager should be rejected');

    RAISE NOTICE 'create_service_item regression tests passed';
END $$ LANGUAGE plpgsql;

ROLLBACK; -- Always rollback: tests must not mutate data
