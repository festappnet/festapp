-- Migration: Consolidated Features (Admin Org ID + SEO RPC)
-- Description: Deploys functions for Admin ID retrieval and SEO Data.

-- 1. Get User's Admin Organization ID
CREATE OR REPLACE FUNCTION get_my_admin_organization_id()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  org_id bigint;
BEGIN
  SELECT organization INTO org_id
  FROM organization_users
  WHERE "user" = auth.uid()
    AND is_admin = true
  LIMIT 1;

  RETURN org_id;
END;
$$;

-- 2. Add RPC for SEO Data Retrieval
-- Accessed by public (anon) role to generate OG tags
CREATE OR REPLACE FUNCTION get_occasion_seo_data(p_link_slug TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with permissions of creator to access potentially restricted org data (for just title)
SET search_path = public
AS $$
DECLARE
    v_result JSON;
    v_occasion_id BIGINT;
    v_form_header TEXT;
BEGIN
    -- 1. Try to find occasion via Form Link
    SELECT occasion, header INTO v_occasion_id, v_form_header
    FROM forms
    WHERE link = p_link_slug
    LIMIT 1;

    -- 2. If not found, try to find occasion via Occasion Link
    IF v_occasion_id IS NULL THEN
        SELECT id INTO v_occasion_id
        FROM occasions
        WHERE link = p_link_slug
        LIMIT 1;
    END IF;

    -- 3. If occasion found, fetch SEO data
    IF v_occasion_id IS NOT NULL THEN
        SELECT json_build_object(
            'title', o.title,
            'description', o.description,
            'form_description', v_form_header,
            'image', o.data->>'image',
            'org_title', org.title,
            'unit_title', u.title
        )
        INTO v_result
        FROM occasions o
        JOIN organizations org ON o.organization = org.id
        LEFT JOIN units u ON o.unit = u.id
        WHERE o.id = v_occasion_id;
    END IF;

    RETURN v_result;
END;
$$;

-- Grant access to anon
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_occasion_seo_data(TEXT) TO service_role;
