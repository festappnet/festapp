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
REVOKE ALL ON FUNCTION public.check_is_admin_of_organization(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.check_is_admin_of_organization(bigint) TO anon,authenticated,service_role;
