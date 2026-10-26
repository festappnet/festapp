CREATE OR REPLACE FUNCTION get_is_admin_on_occasion(oc bigint) RETURNS boolean
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    is_admin_var boolean;
    organization_id bigint;
BEGIN
    IF public.is_demo_occasion(oc) THEN RETURN false; END IF;
    -- Retrieve the organization ID associated with the given occasion
    SELECT organization INTO organization_id
    FROM occasions
    WHERE id = oc;

    -- Check if the current authenticated user is an admin in the organization
    SELECT is_admin INTO is_admin_var
    FROM organization_users
    WHERE organization = organization_id
      AND "user" = auth.uid();

    -- Return true if the user is an admin, otherwise false
    RETURN COALESCE(is_admin_var, false);
END;
$$;
