-- Verify get_occasion_seo_data RPC:
--   1. Returns SEO data (title, description, image, org_title) for a valid slug
--   2. Returns NULL for a missing slug

DO $$
DECLARE
    v_org_id bigint;
    v_occasion_id bigint;
    v_slug text := 'seo-test-event-slug-' || floor(random()*1000000)::text;
    v_missing_slug text := 'non-existent-slug-' || floor(random()*1000000)::text;
    v_result JSON;
BEGIN
    -- 1. Setup
    INSERT INTO public.organizations (title)
    VALUES ('SEO Test Org')
    RETURNING id INTO v_org_id;

    INSERT INTO public.occasions (organization, title, link, description, data, start_time, end_time)
    VALUES (
        v_org_id,
        'SEO Test Event',
        v_slug,
        'Best event ever',
        '{"image": "https://example.com/poster.jpg"}'::jsonb,
        NOW(),
        NOW() + interval '1 day'
    )
    RETURNING id INTO v_occasion_id;

    -- 2. Success Case
  PERFORM pg_temp.adopt_public_link_fixtures();
    v_result := get_occasion_seo_data(v_slug);
    PERFORM assert_equals((v_result->>'title'), 'SEO Test Event', 'Title should match');
    PERFORM assert_equals((v_result->>'org_title'), 'SEO Test Org', 'Org Title should match');
    PERFORM assert_equals((v_result->>'image'), 'https://example.com/poster.jpg', 'Image URL should match');

    -- 3. Missing Slug
    v_result := get_occasion_seo_data(v_missing_slug);
    IF v_result IS NOT NULL THEN
        RAISE EXCEPTION 'Expected NULL result for missing slug, got: %', v_result;
    END IF;
END $$;
