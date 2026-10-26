-- Test: get_sync_occasions returns valid public occasion data
-- This test runs on the LOCAL database and validates the RPC output format.
DO $$
DECLARE
    v_result jsonb;
    v_occasion_count int;
    v_org_id bigint;
    v_test_occasion_id bigint;
BEGIN
    RAISE NOTICE 'Starting Sync via HTTP Test...';

    -- 1. Setup: Find or create a test organization
    SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
    IF v_org_id IS NULL THEN
        INSERT INTO public.organizations (title) VALUES ('Sync Test Org') RETURNING id INTO v_org_id;
    END IF;

    -- 2. Create a test occasion that matches sync criteria
    INSERT INTO public.occasions (
        link, title, description, data, start_time, end_time,
        is_open, is_hidden, is_promoted, organization,
        features, created_at, updated_at
    ) VALUES (
        'sync-test-' || extract(epoch from now())::text,
        'Sync Test Occasion',
        'Test occasion for sync RPC',
        '{"image": "https://example.com/test.jpg", "remaining_places": 42}'::jsonb,
        now() + interval '1 day',
        now() + interval '2 days',
        true,   -- is_open
        false,  -- is_hidden
        true,   -- is_promoted
        v_org_id,
        '[{"code": "schedule", "is_enabled": true}]'::jsonb,
        now(), now()
    ) RETURNING id INTO v_test_occasion_id;

    -- 3. Test: get_sync_occasions returns data
    v_result := get_sync_occasions(v_org_id);

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'FAIL: get_sync_occasions returned NULL';
    END IF;

    v_occasion_count := jsonb_array_length(v_result);
    IF v_occasion_count < 1 THEN
        RAISE EXCEPTION 'FAIL: Expected at least 1 occasion, got %', v_occasion_count;
    END IF;

    RAISE NOTICE 'OK: get_sync_occasions returned % occasions for org %', v_occasion_count, v_org_id;

    -- 4. Validate returned fields
    IF NOT (v_result->0 ? 'id') THEN RAISE EXCEPTION 'FAIL: Missing id field'; END IF;
    IF NOT (v_result->0 ? 'title') THEN RAISE EXCEPTION 'FAIL: Missing title field'; END IF;
    IF NOT (v_result->0 ? 'data') THEN RAISE EXCEPTION 'FAIL: Missing data field'; END IF;
    IF NOT (v_result->0 ? 'features') THEN RAISE EXCEPTION 'FAIL: Missing features field'; END IF;
    IF NOT (v_result->0 ? 'start_time') THEN RAISE EXCEPTION 'FAIL: Missing start_time field'; END IF;
    IF NOT (v_result->0 ? 'link') THEN RAISE EXCEPTION 'FAIL: Missing link field'; END IF;

    RAISE NOTICE 'OK: All required fields present in response';

    -- 5. Test: Hidden occasions are NOT returned
    UPDATE public.occasions SET is_hidden = true WHERE id = v_test_occasion_id;
    v_result := get_sync_occasions(v_org_id);

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_result) elem
        WHERE (elem->>'id')::bigint = v_test_occasion_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Hidden occasion should not be returned';
    END IF;
    RAISE NOTICE 'OK: Hidden occasion correctly excluded';

    -- 6. Test: Non-promoted occasions are NOT returned
    UPDATE public.occasions SET is_hidden = false, is_promoted = false WHERE id = v_test_occasion_id;
    v_result := get_sync_occasions(v_org_id);

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_result) elem
        WHERE (elem->>'id')::bigint = v_test_occasion_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Non-promoted occasion should not be returned';
    END IF;
    RAISE NOTICE 'OK: Non-promoted occasion correctly excluded';

    -- 7. Test: Closed occasions are NOT returned
    UPDATE public.occasions SET is_promoted = true, is_open = false WHERE id = v_test_occasion_id;
    v_result := get_sync_occasions(v_org_id);

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_result) elem
        WHERE (elem->>'id')::bigint = v_test_occasion_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Closed occasion should not be returned';
    END IF;
    RAISE NOTICE 'OK: Closed occasion correctly excluded';

    -- 8. Test: NULL organization returns all matching occasions
    UPDATE public.occasions SET is_open = true WHERE id = v_test_occasion_id;
    v_result := get_sync_occasions(NULL);

    IF v_result IS NULL OR jsonb_array_length(v_result) < 1 THEN
        RAISE EXCEPTION 'FAIL: NULL org_id should return occasions';
    END IF;
    RAISE NOTICE 'OK: NULL org_id returns % occasions', jsonb_array_length(v_result);

    -- Cleanup
    DELETE FROM public.occasions WHERE id = v_test_occasion_id;

    RAISE NOTICE '✅ All sync_via_http tests passed!';
END;
$$;
