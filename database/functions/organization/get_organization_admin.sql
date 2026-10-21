CREATE OR REPLACE FUNCTION public.get_organization_admin(organization_id bigint)
RETURNS SETOF public.organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify admin status
  IF EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    -- Return the organization record without server-only delivery secrets.
    RETURN QUERY
    SELECT o.id, o.created_at, o.updated_at,
      o.data - 'ONESIGNAL_REST_API_KEY', o.title, o.phone_prefixes
    FROM organizations o
    WHERE o.id = organization_id;
  ELSE
    -- Raise distinct exception or return nothing
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;
