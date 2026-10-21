CREATE OR REPLACE FUNCTION public.update_organization_admin(
  organization_id bigint,
  title text,
  data jsonb,
  phone_prefixes text[]
)
RETURNS SETOF public.organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF update_organization_admin.data ? 'ONESIGNAL_REST_API_KEY' THEN
    RAISE invalid_parameter_value
      USING MESSAGE = 'OneSignal REST API key is managed server-side';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    RETURN QUERY
    UPDATE public.organizations
    SET title = COALESCE(update_organization_admin.title, organizations.title),
      data = organizations.data || update_organization_admin.data,
      phone_prefixes = COALESCE(
        update_organization_admin.phone_prefixes,
        organizations.phone_prefixes
      )
    WHERE id = organization_id
    RETURNING organizations.id, organizations.created_at,
      organizations.updated_at,
      organizations.data - 'ONESIGNAL_REST_API_KEY',
      organizations.title, organizations.phone_prefixes;
  ELSE
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.update_organization_admin(bigint, text, jsonb);
