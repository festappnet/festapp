CREATE OR REPLACE FUNCTION check_is_admin_of_organization(organization_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  );
END;
$$;
