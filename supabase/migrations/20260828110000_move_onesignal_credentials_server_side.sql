CREATE TABLE public.organization_notification_secrets (
  organization bigint PRIMARY KEY
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  onesignal_rest_api_key text NOT NULL
    CHECK (length(onesignal_rest_api_key) > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.organization_notification_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.organization_notification_secrets
  FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO public.organization_notification_secrets(
  organization,
  onesignal_rest_api_key
)
SELECT id, data->>'ONESIGNAL_REST_API_KEY'
FROM public.organizations
WHERE nullif(data->>'ONESIGNAL_REST_API_KEY', '') IS NOT NULL
ON CONFLICT (organization) DO NOTHING;

UPDATE public.organizations
SET data = data - 'ONESIGNAL_REST_API_KEY'
WHERE data ? 'ONESIGNAL_REST_API_KEY';

CREATE OR REPLACE FUNCTION public.get_organization_notification_delivery_config(
  p_organization_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.require_service_role();

  SELECT jsonb_build_object(
    'onesignal_app_id', o.data->>'ONESIGNAL_APP_ID',
    'onesignal_rest_api_key', s.onesignal_rest_api_key,
    'default_url', o.data->>'DEFAULT_URL'
  )
  INTO v_result
  FROM public.organizations o
  JOIN public.organization_notification_secrets s
    ON s.organization = o.id
  WHERE o.id = p_organization_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_organization_notification_delivery_config(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_organization_notification_delivery_config(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.get_organization_admin(organization_id bigint)
RETURNS SETOF public.organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.organization_users
    WHERE "user" = auth.uid()
      AND organization = organization_id
      AND is_admin = true
  ) THEN
    RETURN QUERY
    SELECT o.id, o.created_at, o.updated_at,
      o.data - 'ONESIGNAL_REST_API_KEY', o.title, o.phone_prefixes
    FROM public.organizations o
    WHERE o.id = organization_id;
  ELSE
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_organization_admin(
  organization_id bigint,
  title text,
  data jsonb
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
      data = organizations.data || update_organization_admin.data
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
