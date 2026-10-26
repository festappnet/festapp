CREATE OR REPLACE FUNCTION get_current_organization_data() RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    organization_id bigint;
    org_data jsonb;
    organization_user record;
BEGIN
    -- Retrieve the organization ID associated with the current authenticated user
    SELECT organization INTO organization_id
    FROM organization_users
    WHERE "user" = auth.uid()
      AND is_admin = true
    LIMIT 1;

    -- If the user is not associated with any organization as an admin, return a 403 code
    IF organization_id IS NULL THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Retrieve the organization data as jsonb
    SELECT jsonb_build_object(
        'id', id,
        'title', title,
        'data', data
    ) INTO org_data
    FROM organizations
    WHERE id = organization_id;

    -- Return the organization data with a 200 code
    RETURN jsonb_build_object('code', 200, 'data', org_data);
END;
$$;