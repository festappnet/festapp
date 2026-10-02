-- Preserve the current capability while exposing an organization-owned switch.
ALTER TABLE public.external_login_clients
  ADD COLUMN provisioned boolean NOT NULL DEFAULT false;
UPDATE public.external_login_clients SET provisioned = enabled;
ALTER TABLE public.external_login_clients
  ADD CONSTRAINT external_login_client_requires_provisioning CHECK (NOT enabled OR provisioned);
UPDATE public.organizations o
SET data = coalesce(o.data, '{}'::jsonb) || jsonb_build_object(
  'IS_GOOGLE_LOGIN_ENABLED', EXISTS (
    SELECT 1 FROM public.external_login_clients c WHERE c.organization=o.id AND c.enabled
  ))
WHERE NOT coalesce(o.data, '{}'::jsonb) ? 'IS_GOOGLE_LOGIN_ENABLED';
UPDATE public.external_login_clients c
SET enabled = c.provisioned AND (o.data->>'IS_GOOGLE_LOGIN_ENABLED')::boolean IS TRUE
FROM public.organizations o WHERE o.id=c.organization;

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

  IF update_organization_admin.data ? 'IS_GOOGLE_LOGIN_ENABLED'
     AND jsonb_typeof(update_organization_admin.data->'IS_GOOGLE_LOGIN_ENABLED') IS DISTINCT FROM 'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE = 'Google login setting must be boolean';
  END IF;

  -- Verify admin status
  IF EXISTS (
    SELECT 1
    FROM organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    -- Update the organization record
    RETURN QUERY
    UPDATE organizations
    SET 
      title = COALESCE(update_organization_admin.title, organizations.title),
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

    -- Project the organization switch onto operator-provisioned clients in the
    -- same transaction. Unprovisioned platforms must never become available.
    IF update_organization_admin.data ? 'IS_GOOGLE_LOGIN_ENABLED' THEN
      UPDATE public.external_login_clients c
      SET enabled = c.provisioned AND
          (update_organization_admin.data->>'IS_GOOGLE_LOGIN_ENABLED')::boolean
      WHERE c.organization = organization_id;
    END IF;
  ELSE
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;
