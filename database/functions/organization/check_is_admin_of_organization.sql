CREATE OR REPLACE FUNCTION check_is_admin_of_organization(organization_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  RETURN public.can_manage_organization_settings(organization_id);
END;
$$;
