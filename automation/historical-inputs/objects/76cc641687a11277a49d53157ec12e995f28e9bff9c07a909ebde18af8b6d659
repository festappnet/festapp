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
