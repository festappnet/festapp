BEGIN;

-- Tests for get_occasion_seo_data
-- Note: This requires existing data. 'posezeni2026' is known to exist in this snapshot.

DO $$
DECLARE
    result jsonb;
BEGIN
    -- 1. Test Valid Slug
    result := public.get_occasion_seo_data('posezeni2026')::jsonb;
    
    IF result IS NULL THEN
        RAISE EXCEPTION 'Test Failed: Link posezeni2026 should return data';
    END IF;

    IF (result->>'title') IS NULL THEN
         RAISE EXCEPTION 'Test Failed: Result missing title. Got: %', result;
    END IF;

    RAISE NOTICE 'Test Valid Slug Passed: %', result->>'title';

    -- 2. Test Invalid Slug (Should return null)
    result := public.get_occasion_seo_data('non_existent_slug_12345')::jsonb;
    IF result IS NOT NULL THEN
         RAISE EXCEPTION 'Test Failed: Invalid slug should return NULL. Got: %', result;
    END IF;
    
    RAISE NOTICE 'Test Invalid Slug Passed (Correctly NULL)';
END;
$$;

ROLLBACK; -- Always rollback in tests not intended to modify data
